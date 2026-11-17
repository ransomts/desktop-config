// Travel reminder for the charge limit. Opt-in: off until ~/.config/shell/power.json says so.
//   ~/.config/shell/power.json (written with these defaults when missing, edits apply live)
//     { "travelWords": ["flight", "travel", "conference"],   case-insensitive substrings of an event title
//       "remind": false,                                     the switch: true turns the reminder on
//       "eveningAt": "19:00" }                               the reminder comes at the first minute after this
// When it is evening, a charge limit is active and tomorrow's agenda (agenda-day DATE) has an all-day
// or timed event whose title holds one of the words, ask() fires once for that day. The shell shows
// it on the island (shell.qml: island.say({kind: "charge", glyph, title, sub, ms, run: Charge.set("full_charge")})).
// Asked-days are remembered in $XDG_STATE_HOME/charge-travel.json so a shell reload does not ask twice.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: tr

    // ---- what it reads (tests replace the clock) ----
    readonly property string hm: Sys.nowHM
    property string dateOverride: ""                    // tests: "2026-11-14"
    function isoToday() { return dateOverride !== "" ? dateOverride : Qt.formatDate(new Date(), "yyyy-MM-dd") }
    function isoTomorrow() {
        const p = isoToday().split("-").map(Number)
        const d = new Date(p[0], p[1] - 1, p[2] + 1, 12)
        return Qt.formatDate(d, "yyyy-MM-dd")
    }
    // pure: the first event of the list whose title has one of the words, or null
    function match(events, words) {
        const ws = (words || []).map(w => String(w).toLowerCase()).filter(w => w !== "")
        for (const e of events || []) {
            const t = String(e.title || "").toLowerCase()
            if (ws.some(w => t.indexOf(w) >= 0)) return e
        }
        return null
    }

    // ---- settings ----
    property var cfg: ({ travelWords: ["flight", "travel", "conference"], remind: false, eveningAt: "19:00" })
    readonly property string cfgPath: Quickshell.env("POWER_CONFIG") || Quickshell.env("HOME") + "/.config/shell/power.json"
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/charge-travel.json"
    property bool cfgLoaded: false
    property bool stateLoaded: false
    property string askedFor: ""                        // the date (tomorrow's) already handled
    property bool checking: false
    property string lastMatch: ""

    signal ask(string eventTitle, string eventDate)

    function evening() { return hm >= String(cfg.eveningAt || "19:00") }
    function consider() {
        if (!cfgLoaded || !stateLoaded || cfg.remind !== true || checking) return
        if (!Charge.loaded || !Charge.limited || !evening()) return
        const day = isoTomorrow()
        if (askedFor === day) return
        checking = true
        agenda.command = Sys.clean.concat([Sys.bin + "agenda-day", day])
        agenda.running = true
    }
    onHmChanged: consider()
    Connections { target: Charge; function onLimitedChanged() { tr.consider() } function onLoadedChanged() { tr.consider() } }
    onCfgLoadedChanged: consider()
    onStateLoadedChanged: consider()
    onCfgChanged: consider()

    Process {
        id: agenda
        stdout: StdioCollector {
            onStreamFinished: {
                tr.checking = false
                let ev = []
                try { ev = JSON.parse(text) } catch (e) { return }              // no answer: try again next minute
                const day = tr.isoTomorrow()
                tr.askedFor = day
                stateFile.setText(JSON.stringify({ asked: day }))
                const hit = tr.match(ev, tr.cfg.travelWords)
                if (hit) { tr.lastMatch = hit.title; tr.ask(hit.title, day) }
            }
        }
    }

    FileView {
        id: stateFile
        path: tr.statePath
        printErrors: false
        onLoaded: { try { tr.askedFor = String(JSON.parse(text()).asked || "") } catch (e) {} tr.stateLoaded = true }
        onLoadFailed: tr.stateLoaded = true
    }
    FileView {
        id: cfgFile
        path: tr.cfgPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let o = null
            try { o = JSON.parse(text()) } catch (e) { console.warn("Charge travel: bad JSON in", tr.cfgPath) }
            const d = { travelWords: ["flight", "travel", "conference"], remind: false, eveningAt: "19:00" }
            if (o && typeof o === "object") {
                if (Array.isArray(o.travelWords)) d.travelWords = o.travelWords.map(String)
                if (typeof o.remind === "boolean") d.remind = o.remind
                if (typeof o.eveningAt === "string" && /^\d\d:\d\d$/.test(o.eveningAt)) d.eveningAt = o.eveningAt
            }
            tr.cfg = d
            tr.cfgLoaded = true
        }
        onLoadFailed: {
            tr.cfgLoaded = true
            Quickshell.execDetached(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && [ -e \"$1\" ] || printf '%s\\n' \"$2\" > \"$1\"",
                "sh", tr.cfgPath, JSON.stringify(tr.cfg, null, 2)])
        }
    }
}
