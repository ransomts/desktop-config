// Break reminders: the logic behind the Breaks singleton (kept apart so the test harness can
// build a second copy and call it a shell reload).
//
// Once a minute, while enabled, it asks "was there input in that minute?". The answer comes from the
// counters keystats and mousestats already keep: the sum of every count in ~/.local/state/keystats/counts.json
// ("keys") and mouse.json ("actions") is compared with the sum a minute ago. Only totals are read, never
// which key: the files hold counts, no text and no timestamps. (The files' modification times are no use:
// both scripts rewrite them every minute whether or not anything was pressed.) Two FileViews reload, no
// process is started. The counters only see the Moonlander keyboard and pointer clicks and wheel turns, not the laptop's own
// keyboard and not pointer movement: typing on the laptop alone does not count as work.
//
// A minute with input adds one to `workMin`; `restMinutes` minutes in a row without input is a real break and
// puts it back to 0 without a word (so does a gap in the minutes, such as suspend). When `workMin`
// reaches `workMinutes`, nudge(minutes) fires, unless one of these holds (the count carries on and the
// nudge comes at the first minute they are all clear):
//   presenting ($XDG_RUNTIME_DIR/presenting exists), a call (Sys.micInUse or Sys.videoInUse),
//   Do Not Disturb (Notif.dnd), or a nudge less than `snoozeMinutes` ago.
// A nudge that is ignored repeats every snoozeMinutes. State (count, rest run, last nudge, last sum) is kept in
// $XDG_STATE_HOME/breaks-state.json, so a shell reload in the middle of a stretch neither forgets it nor nudges at once.
//
// ~/.config/shell/breaks.json (written with these defaults when missing, edits apply live):
//   { "enabled": false,         the user opts in: `qs ipc call breaks on`
//     "workMinutes": 50,        active minutes before the nudge
//     "restMinutes": 5,         minutes without input that count as a break
//     "snoozeMinutes": 15 }     minimum time between two nudges
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: core

    // ---- settings ----
    readonly property var defaults: ({ enabled: false, workMinutes: 50, restMinutes: 5, snoozeMinutes: 15 })
    property var cfg: defaults
    readonly property bool enabled: cfg.enabled === true
    readonly property int workMinutes: cfg.workMinutes
    readonly property int restMinutes: cfg.restMinutes
    readonly property int snoozeMinutes: cfg.snoozeMinutes
    readonly property string cfgPath: Quickshell.env("BREAKS_CONFIG") || Quickshell.env("HOME") + "/.config/shell/breaks.json"
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/breaks-state.json"
    readonly property string statsDir: Quickshell.env("KEYSTATS_DIR") || Quickshell.env("HOME") + "/.local/state/keystats"
    property int pollMs: 60000

    // ---- state ----
    property int workMin: 0                 // active minutes in this stretch
    property int restRun: 0                 // minutes in a row without input
    property real lastNudge: 0              // epoch ms, 0: none in this stretch
    property real lastTick: 0               // epoch ms of the last minute looked at
    property var lastTotal: null            // the sum at that minute
    property string reason: ""              // why the last due nudge was held back: presenting | call | dnd | snooze | ""
    property bool stateLoaded: false
    property bool useIdle: false            // take activity from userIdle instead of the counters
    property bool userIdle: false           // no input for a minute (IdleMonitor in Breaks.qml)
    property bool cfgLoaded: false
    property bool forcePresenting: false    // tests
    readonly property bool presenting: forcePresenting || presentFile.present
    readonly property bool inCall: Sys.micInUse || Sys.videoInUse
    readonly property string line: enabled && workMin > 0 ? "Working for " + (workMin >= 60 ? Math.floor(workMin / 60) + " h " + ("0" + workMin % 60).slice(-2) + " min" : workMin + " min") : ""

    signal nudge(int minutes)

    // One minute. `total` is the sum of the two counters; nothing else is looked at.
    function step(nowMs, total) {
        if (!enabled) return
        if (lastTick > 0) {
            const missed = Math.round((nowMs - lastTick) / 60000) - 1     // minutes nobody looked (suspend, shell reload)
            if (missed > 0) { restRun += missed; if (restRun >= restMinutes) { workMin = 0; lastNudge = 0 } }
        }
        // With an idle monitor (Breaks.qml gives one in the real shell) "active" is any input on any device in the
        // last minute. The counters alone only see the Moonlander and mouse clicks, so laptop typing went uncounted.
        const active = useIdle ? !userIdle : (lastTotal !== null && total > lastTotal)         // a smaller sum means a counter file was reset, not activity
        lastTotal = total
        lastTick = nowMs
        if (active) { restRun = 0; workMin++ } else restRun++
        if (restRun >= restMinutes) { workMin = 0; lastNudge = 0 }              // a real break: start over, silently
        reason = ""
        if (workMin >= workMinutes) {
            const r = presenting ? "presenting" : inCall ? "call" : Notif.dnd ? "dnd"
                    : (lastNudge > 0 && nowMs - lastNudge < snoozeMinutes * 60000) ? "snooze" : ""
            reason = r
            if (r === "") { lastNudge = nowMs; nudge(workMin) }
        }
        save()
    }

    // ---- reading the counters (async: step runs when both have answered) ----
    property real keyTotal: 0
    property real mouseTotal: 0
    property int waiting: 0
    function poll() {
        if (!enabled || waiting > 0) return
        waiting = 2
        presentFile.reload()
        keyFile.reload(); mouseFile.reload()
    }
    function checkPresenting() { presentFile.reload() }
    function got() {                      // the FileViews also load once by themselves when created: only answers to poll() count
        if (waiting <= 0) return
        if (--waiting === 0) step(Date.now(), keyTotal + mouseTotal)
    }
    function sum(o) { let n = 0; for (const k in o) n += Number(o[k]) || 0; return n }
    FileView {
        id: keyFile
        path: core.statsDir + "/counts.json"
        printErrors: false
        onLoaded: { try { core.keyTotal = core.sum(JSON.parse(text()).keys) } catch (e) { core.keyTotal = 0 } core.got() }
        onLoadFailed: { core.keyTotal = 0; core.got() }
    }
    FileView {
        id: mouseFile
        path: core.statsDir + "/mouse.json"
        printErrors: false
        onLoaded: { try { core.mouseTotal = core.sum(JSON.parse(text()).actions) } catch (e) { core.mouseTotal = 0 } core.got() }
        onLoadFailed: { core.mouseTotal = 0; core.got() }
    }
    Timer { interval: core.pollMs; running: core.enabled && core.stateLoaded; repeat: true; onTriggered: core.poll() }

    // ---- commands ----
    function reset() { workMin = 0; restRun = 0; lastNudge = 0; save() }
    function setEnabled(on) {
        if (on === enabled) return
        writeCfg(Object.assign({}, cfg, { enabled: on }))
        lastTick = 0; lastTotal = null; reset()                  // a fresh start: the first minute only takes a baseline
    }
    function setKey(key, value) {
        if (key === "enabled") { const v = String(value).toLowerCase(); if (!/^(true|false|on|off|1|0)$/.test(v)) return "enabled takes on or off"; setEnabled(/^(true|on|1)$/.test(v)); return status() }
        if (!/^(workMinutes|restMinutes|snoozeMinutes)$/.test(key)) return "unknown key " + key + " (enabled, workMinutes, restMinutes, snoozeMinutes)"
        const n = Math.round(Number(value))
        if (!isFinite(n) || n < 1 || n > 600) return key + " takes a whole number of minutes from 1 to 600"
        const c = Object.assign({}, cfg); c[key] = n
        writeCfg(c)
        return status()
    }
    function writeCfg(c) { cfg = c; if (cfgLoaded) cfgFile.setText(JSON.stringify(c, null, 2) + "\n") }
    function status() {
        if (!enabled) return "off (qs ipc call breaks on)"
        return "on, " + (workMin > 0 ? "working " + workMin + " min" : "no stretch in progress") + ", nudge at " + workMinutes + ", break " + restMinutes + ", snooze " + snoozeMinutes
            + (reason !== "" ? ", nudge held back: " + reason : "")
    }

    // ---- persistence ----
    function save() {
        if (!stateLoaded) return
        stateFile.setText(JSON.stringify({ workMin: workMin, restRun: restRun, lastNudge: lastNudge, lastTick: lastTick, lastTotal: lastTotal }))
    }
    FileView {
        id: stateFile
        path: core.statePath
        printErrors: false
        onLoaded: {
            try {
                const o = JSON.parse(text())
                core.workMin = Math.max(0, Math.round(Number(o.workMin) || 0))
                core.restRun = Math.max(0, Math.round(Number(o.restRun) || 0))
                core.lastNudge = Number(o.lastNudge) || 0
                core.lastTick = Number(o.lastTick) || 0
                core.lastTotal = typeof o.lastTotal === "number" ? o.lastTotal : null
            } catch (e) {}
            core.stateLoaded = true
        }
        onLoadFailed: core.stateLoaded = true
    }
    FileView {
        id: cfgFile
        path: core.cfgPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let o = null
            try { o = JSON.parse(text()) } catch (e) { console.warn("Breaks: bad JSON in", core.cfgPath) }
            const c = Object.assign({}, core.defaults)
            if (o && typeof o === "object") {
                if (typeof o.enabled === "boolean") c.enabled = o.enabled
                for (const k of ["workMinutes", "restMinutes", "snoozeMinutes"]) {
                    const n = Math.round(Number(o[k]))
                    if (isFinite(n) && n >= 1 && n <= 600) c[k] = n
                }
            }
            core.cfg = c
            core.cfgLoaded = true
        }
        onLoadFailed: {
            core.cfg = core.defaults
            core.cfgLoaded = true
            Quickshell.execDetached(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && [ -e \"$1\" ] || printf '%s\\n' \"$2\" > \"$1\"",
                "sh", core.cfgPath, JSON.stringify(core.defaults, null, 2)])
        }
    }
    // $XDG_RUNTIME_DIR/presenting exists while presenting; read when a minute is looked at and when it changes
    FileView {
        id: presentFile
        property bool present: false
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/presenting"
        printErrors: false
        watchChanges: core.enabled
        onFileChanged: reload()
        onLoaded: present = true
        onLoadFailed: present = false
    }
    onEnabledChanged: if (enabled) presentFile.reload()
}
