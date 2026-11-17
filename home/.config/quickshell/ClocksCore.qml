// The logic behind the Clocks singleton, kept apart so the test harness can build a second copy
// over the same state file and call it a shell reload (as QuietCore does). See Clocks.qml for the
// overview, and clocks.js for the parsing.
//
// One Timer (`due`) is armed for the next thing that is due: a timer ending, an alarm minute, a
// repeat of the alarm sound. Nothing polls. A 1 Hz Timer (`ticker`) runs only while some view
// that shows seconds has called watch(key, true). The bar's own minute tick (Sys.nowHM) is the
// catch-up after the laptop slept: Qt's timers stand still during suspend.
//
// State in $XDG_STATE_HOME/clocks.json (times are ms since the epoch):
//   timers  [{ id, label, endsAt, total, pausedLeft (0 = running), done, alarm (rings like an alarm: a snooze) }]
//   alarms  [{ id, label, time "07:30", days ["mon"..] or [] with date "2026-11-15", enabled, lastFired }]
//   stopwatch { running, startedAt, accum, laps [elapsed ms at each lap] }
// Settings in ~/.config/shell/clocks.json (JsonFile): cities [{ name, tz }], snoozeMinutes, sound.
import QtQuick
import Quickshell
import Quickshell.Io
import "clocks.js" as C

Scope {
    id: core
    property var island: null                       // set by the shell: island.say({kind, glyph, title, sub, ms, run})
    property var clockFn: null                      // tests: () => ms; null = the real clock
    function now() { return clockFn ? clockFn() : Date.now() }
    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
    property string stateFile: stateDir + "/clocks.json"
    property string configFile: Quickshell.env("CLOCKS_CONFIG") || Quickshell.env("HOME") + "/.config/shell/clocks.json"
    property var lockCmd: ["hyprctl", "locked"]     // prints "true" while the session is locked
    property bool bootWatch: true                   // listen to the bar's minute tick (tests turn it off)

    // ---- state ----
    property var timers: []
    property var alarms: []
    property var stopwatch: ({ running: false, startedAt: 0, accum: 0, laps: [] })
    property int seq: 0
    property double nowMs: Date.now()               // what views show; moved by the ticker, by changes and by the minute
    property var ringing: []                        // [{ rid, kind, id, label, alarm, repeats, repeatAt, whileLocked }]
    property var missed: []                         // text of alarms that went by while the laptop was off (this run)
    property bool loaded: false
    property string soundName: "complete"
    signal fired(var info)                          // tests and other features can listen

    // ---- settings ----
    JsonFile {
        id: cfgFile
        path: core.configFile
        defaults: ({ cities: [{ name: "UTC", tz: "UTC" }, { name: "London", tz: "Europe/London" }, { name: "Tokyo", tz: "Asia/Tokyo" }], snoozeMinutes: 5, sound: true })
        watch: core.worldWatchers > 0 || core.settingsOpen
    }
    property bool settingsOpen: false
    readonly property alias config: cfgFile
    readonly property var cities: {
        const l = cfgFile.values.cities
        const out = []
        if (Array.isArray(l)) for (const c of l) if (c && typeof c.tz === "string" && C.tzShape(c.tz)) out.push({ name: String(c.name || c.tz.split("/").pop().replace(/_/g, " ")).slice(0, 24), tz: c.tz })
        return out.slice(0, 8)
    }
    readonly property int snoozeMinutes: { const v = Number(cfgFile.values.snoozeMinutes); return v >= 1 && v <= 120 ? Math.round(v) : 5 }
    readonly property bool soundOn: cfgFile.values.sound !== false

    // ---- persistence ----
    FileView {
        id: file
        path: core.stateFile
        blockLoading: true
        blockWrites: true
        printErrors: false
    }
    function save() {
        if (!loaded) return
        file.setText(JSON.stringify({ v: 1, seq: seq, timers: timers, alarms: alarms, stopwatch: stopwatch }, null, 1) + "\n")
    }
    function load() {
        let o = null
        try { o = JSON.parse(file.text()) } catch (e) { o = null }
        if (o && typeof o === "object") {
            if (Array.isArray(o.timers)) timers = o.timers.filter(t => t && typeof t.id === "string" && typeof t.endsAt === "number" && t.total > 0)
            if (Array.isArray(o.alarms)) alarms = o.alarms.filter(a => a && typeof a.id === "string" && C.parseTime(a.time) !== "")
                .map(a => ({ id: a.id, label: String(a.label || ""), time: a.time, days: Array.isArray(a.days) ? a.days : [], date: a.date || "", enabled: a.enabled !== false, lastFired: Number(a.lastFired) || 0 }))
            const s = o.stopwatch
            if (s && typeof s === "object") stopwatch = { running: s.running === true, startedAt: Number(s.startedAt) || 0, accum: Number(s.accum) || 0, laps: Array.isArray(s.laps) ? s.laps.filter(x => typeof x === "number") : [] }
            seq = Number(o.seq) || 0
        }
        loaded = true
        nowMs = now()
    }
    // what came due while the shell was down is rung a few seconds after start, when the island exists (the shell hands it over right after creating this)
    property int startDelayMs: 3000
    Timer { id: startUp; interval: Math.max(1, core.startDelayMs); onTriggered: core.check() }
    Component.onCompleted: { load(); if (startDelayMs <= 0) check(); else startUp.start() }

    FileView {                                      // alarm-clock-elapsed if this sound theme has it, else complete
        path: "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
        blockLoading: true
        printErrors: false
        onLoaded: core.soundName = "alarm-clock-elapsed"
    }

    // ---- the one timer, and the ticker ----
    function nextDueAt() {
        const t = now()
        let best = 0
        const take = x => { if (x > 0 && (best === 0 || x < best)) best = x }
        for (const tm of timers) if (C.timerRunning(tm)) take(tm.endsAt)
        for (const a of alarms) if (a.enabled) take(C.nextOccurrence(a, Math.max(t, a.lastFired || 0)))
        for (const r of ringing) if (r.repeatAt > 0) take(r.repeatAt)
        return best
    }
    function arm() {
        const d = nextDueAt()
        if (d === 0) { due.stop(); return }
        due.interval = Math.max(20, Math.min(2147483000, d - now() + 30))
        due.restart()
    }
    Timer { id: due; onTriggered: core.check() }
    readonly property int dueIn: due.running ? due.interval : 0       // ms the one timer was armed for (tests)
    readonly property bool dueRunning: due.running
    property var watchers: ({})
    readonly property int watcherCount: Object.keys(watchers).length
    function watch(key, on) {
        const w = Object.assign({}, watchers)
        if (on) w[key] = true; else delete w[key]
        watchers = w
        if (on) nowMs = now()
    }
    readonly property bool tickerRunning: ticker.running
    Timer {
        id: ticker
        interval: 1000
        repeat: true
        running: core.watcherCount > 0
        onTriggered: { core.nowMs = core.now(); const d = core.nextDueAt(); if (d > 0 && d <= core.nowMs) core.check() }
    }
    Connections {
        target: core.bootWatch ? Sys : null
        function onNowHMChanged() { core.minuteTick() }
    }
    function minuteTick() {
        nowMs = now()
        check()                                     // catch up after a sleep: Qt's timers did not run
        if (worldWatchers > 0) refreshWorldIfStale()
        if (ringing.some(r => r.whileLocked)) askLock("recheck")
    }

    // ---- going off ----
    function check() {
        const t = now()
        nowMs = t
        let changed = false
        const ts = timers.slice()
        for (let i = 0; i < ts.length; i++) {
            const tm = ts[i]
            if (!C.timerRunning(tm) || tm.endsAt > t) continue
            ts[i] = Object.assign({}, tm, { done: true })
            changed = true
            ring(tm.alarm ? "alarm" : "timer", tm, t - tm.endsAt)
        }
        if (changed) timers = ts
        const al = alarms.slice()
        let alChanged = false
        for (let i = 0; i < al.length; i++) {
            const a = al[i]
            if (!a.enabled) continue
            const o = C.lastOccurrence(a, t)
            if (o <= 0 || o <= (a.lastFired || 0)) continue
            al[i] = Object.assign({}, a, { lastFired: t, enabled: a.date ? false : true })
            alChanged = true
            if (t - o <= C.MISSED_MS) ring("alarm", a, t - o)
            else missedNote(a, o)
        }
        if (alChanged) alarms = al
        let rep = false
        const rs = ringing.slice()
        for (let i = 0; i < rs.length; i++) {
            const r = rs[i]
            if (!(r.repeatAt > 0) || r.repeatAt > t) continue
            rs[i] = Object.assign({}, r, { repeats: r.repeats - 1, repeatAt: r.repeats > 1 ? t + 30000 : 0 })
            rep = true
            if (soundOn) Sys.sound(soundName)
        }
        if (rep) ringing = rs
        if (changed || alChanged) save()
        arm()
    }

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function plain(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    property int ringSeq: 0
    function ago(ms) {
        const m = Math.round(ms / 60000)
        return m < 1 ? "" : m < 60 ? m + " min ago" : Math.floor(m / 60) + " h " + (m % 60) + " min ago"
    }
    // kind "alarm" | "timer"; item the alarm or timer; lateMs how long after its moment we noticed
    function ring(kind, item, lateMs) {
        const late = lateMs > 30000
        const alarmLike = kind === "alarm"
        const rid = "r" + (++ringSeq)
        const label = item.label || ""
        const title = alarmLike ? (label || "Alarm") : (label ? label + " is done" : "Timer done")
        const when = alarmLike && item.time ? item.time : ""
        const lateText = late ? "late: it was due " + C.clockText(now() - lateMs) + (ago(lateMs) !== "" ? ", " + ago(lateMs) : "") : ""
        const sub = [when, !alarmLike ? C.fmtDuration(item.total / 1000) : "", lateText, alarmLike ? "click to snooze " + snoozeMinutes + " min" : "click to dismiss"].filter(s => s !== "").join("  ·  ")
        const dnd = Notif.dnd
        const info = { rid: rid, kind: kind, id: item.id, label: label, title: title, sub: sub, late: late, dnd: dnd }
        ringing = ringing.concat([{ rid: rid, kind: kind, id: item.id, label: label, alarm: alarmLike, title: title, sub: sub, repeats: alarmLike ? 2 : 0, repeatAt: alarmLike ? now() + 30000 : 0, whileLocked: false }])
        say(info)
        // a normal notification as well, so it lands in the list. An alarm is critical: it pops up through
        // Do Not Disturb (set on purpose); a timer is normal: with DND on it is listed without a popup.
        Sys.run("notify-send -a Clock -i alarm-symbolic" + (alarmLike ? " -u critical" : "") + " -h boolean:suppress-sound:true "
                + shq(title) + " " + shq(plain(sub.replace(/  ·  click to .*$/, ""))))
        if (soundOn && (alarmLike || !dnd)) Sys.sound(soundName)
        fired(info)
        askLock("fire")
    }
    function say(info) {
        if (!island) return
        const rid = info.rid
        island.say({ kind: "clock-" + rid, glyph: info.kind === "alarm" ? Icons.bell : Icons.clock, title: info.title, sub: info.sub, ms: 600000,
                     run: function () { info.kind === "alarm" ? core.snoozeRing(rid) : core.dismissRing(rid) } })
    }
    function missedNote(a, o) {
        const text = a.time + (a.label ? " " + a.label : "") + " went by while the laptop was off"
        missed = missed.concat([text]).slice(-10)
        Sys.run("notify-send -a Clock -u low -h boolean:suppress-sound:true " + shq("Missed alarm") + " " + shq(plain(text)))
    }

    // ---- locked screen: it rings anyway (the sound and the list), and is shown again on the island after unlocking ----
    property string lockMode: ""
    Process {
        id: lockProc
        command: core.lockCmd
        stdout: StdioCollector {
            onStreamFinished: {
                const locked = text.trim() === "true"
                if (core.lockMode === "fire" && locked) core.ringing = core.ringing.map(r => Object.assign({}, r, { whileLocked: true }))
                if (core.lockMode === "recheck" && !locked) core.unlocked()
            }
        }
    }
    function askLock(mode) { lockMode = mode; lockProc.running = false; lockProc.running = true }
    function unlocked() {                           // also called by the shell when lock-screen says hello (Pet.greet)
        const back = ringing.filter(r => r.whileLocked)
        if (back.length === 0) return
        ringing = ringing.map(r => r.whileLocked ? Object.assign({}, r, { whileLocked: false }) : r)
        for (const r of back) say(r)
    }

    // ---- acknowledging ----
    function ringOf(rid) { return ringing.find(r => r.rid === rid) || null }
    function dropRing(rid) { ringing = ringing.filter(r => r.rid !== rid) }
    function dismissRing(rid) {
        const r = ringOf(rid)
        if (!r) return false
        dropRing(rid)
        if (r.kind === "timer") removeTimer(r.id)
        else if (r.kind === "alarm" && timers.some(t => t.id === r.id && t.done)) removeTimer(r.id)
        arm()
        return true
    }
    function snoozeRing(rid) {
        const r = ringOf(rid)
        if (!r || !r.alarm) return "nothing to snooze"
        dropRing(rid)
        if (timers.some(t => t.id === r.id)) removeTimer(r.id)      // a snooze that rang again
        const id = addTimerMs(snoozeMinutes * 60000, r.label, true)
        return "snoozed " + snoozeMinutes + " min" + (r.label ? ": " + r.label : "") + " (" + id + ")"
    }
    function snooze() {                             // the newest alarm that is ringing
        for (let i = ringing.length - 1; i >= 0; i--) if (ringing[i].alarm) return snoozeRing(ringing[i].rid)
        return "nothing is ringing"
    }
    function dismissAll() { for (const r of ringing.slice()) dismissRing(r.rid) }

    // ---- timers ----
    function newId(p) { seq++; return p + seq.toString(36) + Date.now().toString(36).slice(-3) }
    function addTimerMs(ms, label, alarmLike) {
        if (timers.length >= 30) return ""
        const t = now()
        const id = newId("t")
        timers = timers.concat([{ id: id, label: String(label || ""), endsAt: t + ms, total: ms, pausedLeft: 0, done: false, alarm: alarmLike === true }])
        nowMs = t
        save(); arm()
        return id
    }
    function addTimer(seconds, label) { return addTimerMs(Math.round(seconds * 1000), label, false) }
    function timerById(id) { return timers.find(t => t.id === id) || null }
    function patchTimer(id, o) { timers = timers.map(t => t.id === id ? Object.assign({}, t, o) : t); nowMs = now(); save(); arm() }
    function pauseTimer(id) { const t = timerById(id); if (t && C.timerRunning(t)) patchTimer(id, { pausedLeft: Math.max(1, t.endsAt - now()) }) }
    function resumeTimer(id) { const t = timerById(id); if (t && t.pausedLeft > 0) patchTimer(id, { endsAt: now() + t.pausedLeft, pausedLeft: 0 }) }
    function togglePause(id) { const t = timerById(id); if (!t || t.done) return; if (t.pausedLeft > 0) resumeTimer(id); else pauseTimer(id) }
    function resetTimer(id) {
        const t = timerById(id)
        if (!t) return
        for (const r of ringing.filter(r => r.id === id)) dropRing(r.rid)
        patchTimer(id, t.pausedLeft > 0 ? { pausedLeft: t.total, done: false } : { endsAt: now() + t.total, pausedLeft: 0, done: false })
    }
    function removeTimer(id) { timers = timers.filter(t => t.id !== id); for (const r of ringing.filter(r => r.id === id)) dropRing(r.rid); nowMs = now(); save(); arm() }
    function cancelTimers() { for (const t of timers.slice()) removeTimer(t.id) }
    function timerSpec(spec) {
        const p = C.parseTimer(spec)
        if (p.error) return "error: " + p.error
        const id = addTimer(p.seconds, p.label)
        return id === "" ? "error: too many timers" : "timer " + C.fmtDuration(p.seconds) + (p.label ? ": " + p.label : "") + " started (" + id + ")"
    }
    readonly property int runningCount: timers.filter(C.timerRunning).length
    readonly property string tip: C.tipText(timers, nowMs)
    function tipFor(minute) { return C.tipText(timers, now()) }     // `minute` (Sys.nowHM) is only there so a binding re-runs each minute

    // ---- alarms ----
    function addAlarm(o) {
        const t = now()
        if (C.parseTime(o.time) === "" || alarms.length >= 40) return ""
        const id = newId("a")
        alarms = alarms.concat([{ id: id, label: String(o.label || ""), time: o.time, days: o.days || [], date: o.date || "", enabled: true, lastFired: t }])
        nowMs = t
        save(); arm()
        return id
    }
    function alarmSpec(spec) {
        const p = C.parseAlarm(spec, now())
        if (p.error) return "error: " + p.error
        const id = addAlarm(p)
        return id === "" ? "error: could not add" : "alarm " + p.time + (p.label ? " " + p.label : "") + " set for " + (C.whenText(p, now()) || p.date) + " (" + id + ")"
    }
    function alarmById(id) { return alarms.find(a => a.id === id) || null }
    function patchAlarm(id, o) { alarms = alarms.map(a => a.id === id ? Object.assign({}, a, o) : a); nowMs = now(); save(); arm() }
    function setAlarmEnabled(id, on) {
        const a = alarmById(id)
        if (!a) return
        if (on && a.date && C.at(C.dateFromYmd(a.date), a.time) <= now()) return      // a one-off whose day has passed cannot come back
        patchAlarm(id, { enabled: on, lastFired: on ? now() : a.lastFired })
    }
    function removeAlarm(id) { alarms = alarms.filter(a => a.id !== id); nowMs = now(); save(); arm() }
    function editAlarm(id, spec) {                  // from the settings page: "7:30 weekdays label"
        const p = C.parseAlarm(spec, now())
        if (p.error) return p.error
        patchAlarm(id, { time: p.time, days: p.days, date: p.date, label: p.label, enabled: true, lastFired: now() })
        return ""
    }
    function alarmLine(a) { return a.time + (a.label ? "  " + a.label : "") }
    function alarmWhen(a) { return C.whenText(a, nowMs) }
    function nextAlarmAt() {
        let best = 0
        for (const a of alarms) if (a.enabled) { const o = C.nextOccurrence(a, Math.max(nowMs, a.lastFired || 0)); if (o > 0 && (best === 0 || o < best)) best = o }
        return best
    }

    // ---- stopwatch ----
    function swElapsed() { return stopwatch.accum + (stopwatch.running ? Math.max(0, now() - stopwatch.startedAt) : 0) }
    readonly property var stopwatchView: ({ running: stopwatch.running, elapsed: stopwatch.accum + (stopwatch.running ? Math.max(0, nowMs - stopwatch.startedAt) : 0), laps: stopwatch.laps })
    function stopwatchAction(action) {
        const s = stopwatch, t = now()
        if (action === "toggle") action = s.running ? "stop" : "start"
        if (action === "start") { if (!s.running) stopwatch = { running: true, startedAt: t, accum: s.accum, laps: s.laps } }
        else if (action === "stop") { if (s.running) stopwatch = { running: false, startedAt: 0, accum: s.accum + t - s.startedAt, laps: s.laps } }
        else if (action === "lap") { if (s.running) stopwatch = { running: true, startedAt: s.startedAt, accum: s.accum, laps: s.laps.concat([swElapsed()]).slice(-50) } }
        else if (action === "reset") stopwatch = { running: false, startedAt: 0, accum: 0, laps: [] }
        else if (action !== "status") return "usage: stopwatch start|stop|toggle|lap|reset|status"
        nowMs = t
        save()
        return (stopwatch.running ? "running " : "stopped ") + C.fmtElapsed(swElapsed()) + (stopwatch.laps.length ? ", " + stopwatch.laps.length + " laps" : "")
    }

    // ---- listing and cancelling (IPC) ----
    function list() {
        const t = now(), out = []
        timers.forEach((tm, i) => out.push("timer " + tm.id + "  " + (tm.done ? "done" : C.fmtLeft(C.timerLeftMs(tm, t) / 1000) + (tm.pausedLeft > 0 ? " paused" : " left")) + (tm.label ? "  " + tm.label : "")))
        alarms.forEach(a => out.push("alarm " + a.id + "  " + a.time + "  " + (C.whenText(a, t) || "-") + (a.enabled ? "" : "  off") + (a.label ? "  " + a.label : "")))
        out.push("stopwatch  " + (stopwatch.running ? "running " : "stopped ") + C.fmtElapsed(swElapsed()))
        return out.join("\n")
    }
    function cancel(id) {
        id = String(id).trim()
        if (id === "all") { const n = timers.length; cancelTimers(); return "cancelled " + n + " timers" }
        if (timerById(id)) { removeTimer(id); return "timer " + id + " cancelled" }
        if (alarmById(id)) { removeAlarm(id); return "alarm " + id + " removed" }
        return "error: no timer or alarm " + id
    }
    function status() { return C.summary({ timers: timers, alarms: alarms, stopwatch: stopwatchView }, now()) + (ringing.length ? "  [" + ringing.length + " ringing]" : "") }
    readonly property string summaryText: C.summary({ timers: timers, alarms: alarms, stopwatch: stopwatchView }, nowMs)

    // ---- the launcher ----
    function launcherRows(q, view) {
        const rows = C.launcherRows(q, { timers: timers, alarms: alarms, stopwatch: Object.assign({}, stopwatchView, { elapsed: swElapsed() }) }, now())
        const close = () => { if (view && view.close) view.close() }
        return rows.map(r => {
            const a = r.act
            return { label: r.label, sub: r.sub, icon: "", glyph: a && a.type.startsWith("alarm") ? Icons.bell : Icons.clock,
                     run: function () { close(); if (a) core.act(a) } }
        })
    }
    function act(a) {
        if (a.type === "timer") addTimer(a.seconds, a.label)
        else if (a.type === "alarm") addAlarm(a)
        else if (a.type === "pause") togglePause(a.id)
        else if (a.type === "cancel") removeTimer(a.id)
        else if (a.type === "reset") resetTimer(a.id)
        else if (a.type === "alarmtoggle") { const x = alarmById(a.id); if (x) setAlarmEnabled(a.id, !x.enabled) }
        else if (a.type === "alarmdelete") removeAlarm(a.id)
        else if (a.type === "stopwatch") stopwatchAction(a.action)
    }

    // ---- the world clock: offsets come from bin/tz-now (Qt's JS has no time zones); kept until the next switch ----
    property var world: ({})                        // tz -> { ok, offset (s), abbr, next (s) }
    property var worldKeys: ({})
    readonly property int worldWatchers: Object.keys(worldKeys).length
    function worldWatch(key, on) {
        const w = Object.assign({}, worldKeys)
        if (on) w[key] = true; else delete w[key]
        worldKeys = w
        if (on) { nowMs = now(); refreshWorld() }
    }
    function refreshWorld() {
        if (cities.length === 0) return
        worldProc.command = Sys.clean.concat([Sys.bin + "tz-now", "--at", String(Math.floor(now() / 1000))]).concat(cities.map(c => c.tz))
        worldProc.running = false
        worldProc.running = true
    }
    onCitiesChanged: if (worldWatchers > 0) refreshWorldIfStale()
    function refreshWorldIfStale() {
        const t = now() / 1000
        if (cities.some(c => !world[c.tz] || (world[c.tz].next > 0 && world[c.tz].next <= t))) refreshWorld()
    }
    Process {
        id: worldProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const w = Object.assign({}, core.world)
                    for (const r of JSON.parse(text)) w[r.tz] = r
                    core.world = w
                } catch (e) { console.warn("Clocks: tz-now gave nothing usable") }
            }
        }
    }
    readonly property int localOffsetSec: { nowMs; return -new Date(nowMs).getTimezoneOffset() * 60 }
    readonly property var worldLines: cities.map(c => {
        const w = world[c.tz]
        if (!w || !w.ok) return { name: c.name, tz: c.tz, ok: false, time: "", diff: "", note: w ? "unknown zone" : "…", abbr: "" }
        const t = C.worldTime(nowMs, w.offset, localOffsetSec)      // an offset past its `next` is re-asked on the minute tick
        return { name: c.name, tz: c.tz, ok: true, time: t.time, diff: C.diffText(t.diffHours), note: t.dayShift === 0 ? "" : t.dayShift > 0 ? "tomorrow" : "yesterday", abbr: w.abbr || "" }
    })
    // zone names for the settings page's check (read on demand)
    property var zoneNames: []
    function loadZones() { if (zoneNames.length === 0) { zonesProc.running = false; zonesProc.running = true } }
    Process {
        id: zonesProc
        command: Sys.clean.concat([Sys.bin + "tz-now", "--list"])
        stdout: StdioCollector { onStreamFinished: core.zoneNames = text.split("\n").filter(s => s !== "") }
    }
    function validZone(tz) { return C.tzShape(tz) && zoneNames.indexOf(tz) >= 0 }      // false until loadZones() has answered
    function setCities(l) { cfgFile.set("cities", l) }
}
