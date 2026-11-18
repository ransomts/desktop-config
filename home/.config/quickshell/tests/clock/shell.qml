// Tests for the clock tools (Clocks.qml / ClocksCore.qml / clocks.js / bin/tz-now / ClockPanel.qml in
// Calendar.qml / SettingsClock.qml). NOT part of the shell: ~/.local/bin/clock-test copies the real files
// next to these stubs (Sys, Notif; Settings* parts as plain windows) and runs it offscreen with TZ
// America/New_York. Time is a fake clock (`fake`, ms): every core is built over it, so "a night's sleep"
// is one assignment. A reload is a second ClocksCore over the same state file. Every command and sound
// goes to the Sys stub; nothing is run. Each case logs CTEST PASS or FAIL; the last line is
// "CTEST RESULT pass N fail M". Pictures go to $CLOCK_TEST_OUT if set.
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "clocks.js" as C

ShellRoot {
    id: root
    property int passed: 0
    property int failed: 0
    function check(what, ok, detail) {
        if (ok) passed++; else failed++
        console.log("CTEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
    }
    function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
    readonly property string state: Quickshell.env("XDG_STATE_HOME")
    readonly property string picDir: Quickshell.env("CLOCK_TEST_OUT")

    // ---- the fake clock: local time, TZ America/New_York ----
    property double fake: 0
    function tm(y, mo, d, h, mi, s) { return new Date(y, mo - 1, d, h, mi, s || 0).getTime() }
    function min(n) { return n * 60000 }
    readonly property double sat10: tm(2026, 11, 14, 10, 0)      // a Saturday
    readonly property double mon0730: tm(2026, 11, 16, 7, 30)

    Component { id: islandComp; QtObject { property var calls: []; function say(m) { calls = calls.concat([m]) } } }
    Component { id: coreComp; ClocksCore { bootWatch: false; startDelayMs: 0; lockCmd: ["echo", "false"]; clockFn: () => root.fake } }
    property int coreN: 0
    function mk(file) {                   // a core over state file `file` (same name = a reload of it)
        return coreComp.createObject(root, { stateFile: state + "/" + file + ".json", island: islandComp.createObject(root) })   // island given up front: a reload rings at once
    }
    function fresh() { return mk("c" + (++coreN)) }
    function notifies(match) { return Sys.runs.filter(r => String(r).indexOf("notify-send") === 0 && (!match || String(r).indexOf(match) >= 0)) }
    function wipe() { Sys.forget(); Notif.dnd = false }
    TestEvent { id: ev }
    FileView { id: modeFile; path: Quickshell.env("HOME") + "/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark"; printErrors: false; blockWrites: true }
    function setDark(d) { modeFile.setText(d ? "true\n" : "false\n"); Theme.reload() }

    // ---- UI helpers ----
    function findAll(item, pred, acc) {
        acc = acc || []
        if (!item) return acc
        if (pred(item)) acc.push(item)
        for (const k of (item.children || [])) findAll(k, pred, acc)
        return acc
    }
    function byName(item, name) { return findAll(item, x => x.objectName === name && x.visible) }
    function click(item) {
        const w = item.Window.window
        if (w && !w.active) w.requestActivate()
        const p = item.mapToItem(null, item.width / 2, item.height / 2)
        ev.mouseClick(w, p.x, p.y, Qt.LeftButton, Qt.NoModifier, -1)
    }
    function textsOf(item) { return findAll(item, x => x.text !== undefined && x.visible && x.width > 0 && x.cursorPosition === undefined).map(x => String(x.text)) }
    property int grabbing: 0
    property double holdUntil: 0
    function picture(item, name, then) {
        if (!picDir) { if (then) then(); return }
        grabbing++
        const ok = item.grabToImage(r => { r.saveToFile(picDir + "/" + name + ".png"); console.log("CTEST picture " + name); if (then) then(); holdUntil = Date.now() + 250; grabbing-- })
        if (!ok) { console.log("CTEST FAIL picture " + name + " not taken"); failed++; grabbing-- }
    }

    // ---- hosts for the views ----
    Rectangle { id: nothing; visible: false; width: 1; height: 1 }
    FloatingWindow {
        id: calWin
        visible: true
        implicitWidth: 332; implicitHeight: 1000
        color: "#2b3a55"
        Rectangle {
            id: calCard
            anchors.fill: parent
            color: Theme.solidBg
            Calendar { id: cal; x: 16; y: 16; width: 300; today: new Date(root.sat10) }
        }
    }
    readonly property var panel: findAll(calCard, x => x.objectName === "clockPanel")[0]
    FloatingWindow {
        id: setWin
        visible: false
        implicitWidth: 640; implicitHeight: 940
        color: Theme.solidBg
        Rectangle { id: setCard; anchors.fill: parent; color: Theme.solidBg; SettingsClock { id: setPage; anchors.fill: parent; anchors.margins: 12 } }
    }
    QtObject { id: viewStub; property int closed: 0; function close() { closed++ } }

    function parseCases() {
        const timers = [["10m tea", 600, "tea"], ["1h30", 5400, ""], ["25", 1500, ""], ["90s", 90, ""], ["1.5h", 5400, ""], ["45 min", 2700, ""],
                        ["1 hour 15 minutes", 4500, ""], ["1:30", 90, ""], ["1:02:03", 3723, ""], ["1m30 pasta", 90, "pasta"], ["for 5m eggs", 300, "eggs"],
                        ["2h", 7200, ""], ["30 s", 30, ""], ["2,5h", 9000, ""], ["  10M  Tea Time ", 600, "Tea Time"]]
        for (const [s, secs, label] of timers) { const r = C.parseTimer(s); check("timer spec \"" + s + "\"", r.seconds === secs && r.label === label, JSON.stringify(r)) }
        for (const s of ["", "abc", "0", "-5", "99999h", "1:75", "tea 10m", "m", "10x"]) check("bad timer spec \"" + s + "\"", !!C.parseTimer(s).error, JSON.stringify(C.parseTimer(s)))
        const wk = ["mon", "tue", "wed", "thu", "fri"], all = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        const alarms = [["7:30", "07:30", [], "2026-11-15", ""], ["11:00", "11:00", [], "2026-11-14", ""], ["6:45am weekdays stand-up", "06:45", wk, "", "stand-up"],
                        ["tomorrow 9", "09:00", [], "2026-11-15", ""], ["mon wed fri 7", "07:00", ["mon", "wed", "fri"], "", ""], ["7:30 2026-11-20 flight", "07:30", [], "2026-11-20", "flight"],
                        ["every day 6am", "06:00", all, "", ""], ["monday 8", "08:00", [], "2026-11-16", ""], ["mondays 8", "08:00", ["mon"], "", ""], ["7pm", "19:00", [], "2026-11-14", ""],
                        ["noon lunch", "12:00", [], "2026-11-14", "lunch"], ["12am tomorrow", "00:00", [], "2026-11-15", ""], ["weekends 9 sleep in", "09:00", ["sat", "sun"], "", "sleep in"],
                        ["mon-fri 7:15", "07:15", wk, "", ""], ["6:45 am", "06:45", [], "2026-11-15", ""], ["at 7 take pills", "07:00", [], "2026-11-15", "take pills"], ["0730", "07:30", [], "2026-11-15", ""]]
        for (const [s, time, days, date, label] of alarms) { const r = C.parseAlarm(s, sat10); check("alarm spec \"" + s + "\"", r.time === time && same(r.days, days) && r.date === date && r.label === label, JSON.stringify(r)) }
        for (const s of ["", "25:00", "tomorrow", "7:30 2026-02-31", "today 8", "tomorrow 9 weekdays", "13pm", "7:60", "standup"]) check("bad alarm spec \"" + s + "\"", !!C.parseAlarm(s, sat10).error, JSON.stringify(C.parseAlarm(s, sat10)))
        check("duration formats", C.fmtLeft(252) === "4:12" && C.fmtLeft(3725) === "1:02:05" && C.fmtDuration(5400) === "1 h 30 min" && C.fmtDuration(600) === "10 min", C.fmtLeft(252) + C.fmtLeft(3725))
        check("tz name shape", C.tzShape("Europe/London") && C.tzShape("UTC") && C.tzShape("America/Argentina/Buenos_Aires") && !C.tzShape("../etc") && !C.tzShape("a b") && !C.tzShape(""))
        // when an alarm rings: weekdays from a Saturday, a single date, the latest ring so far
        const a = { time: "07:30", days: wk, date: "" }
        check("next weekday ring is Monday 07:30", C.nextOccurrence(a, sat10) === mon0730, new Date(C.nextOccurrence(a, sat10)))
        check("next ring after Monday's is Tuesday's", C.nextOccurrence(a, mon0730) === tm(2026, 11, 17, 7, 30))
        check("last ring at Monday 07:31 is 07:30", C.lastOccurrence(a, tm(2026, 11, 16, 7, 31)) === mon0730)
        check("last ring on Saturday morning is Friday's", C.lastOccurrence(a, sat10) === tm(2026, 11, 13, 7, 30))
        check("a past one-off date has no next ring", C.nextOccurrence({ time: "07:30", days: [], date: "2026-11-01" }, sat10) === 0)
        check("summary line", C.summary({ timers: [{ id: "a", done: false, pausedLeft: 0 }, { id: "b", done: false, pausedLeft: 5 }], alarms: [{ time: "07:30", days: wk, date: "", enabled: true, lastFired: 0 }], stopwatch: {} }, sat10) === "2 timers · next alarm Mon 07:30",
              C.summary({ timers: [{ id: "a", done: false, pausedLeft: 0 }], alarms: [{ time: "07:30", days: wk, date: "", enabled: true, lastFired: 0 }], stopwatch: {} }, sat10))
        check("empty summary line", C.summary({ timers: [], alarms: [], stopwatch: {} }, sat10) === "Timers, alarms, clocks")
        return 200
    }

    property var cases: [
        { name: "parsing: timers, alarms, ring times", run: function() { return parseCases() } },

        { name: "timers: several at once, pause, resume, reset", run: function() {
            wipe(); fake = sat10
            const c = fresh()
            const t1 = c.addTimer(600, "tea"), t2 = c.addTimer(60, ""), t3 = c.addTimer(3600, "oven")
            check("three timers run at once", c.timers.length === 3 && c.runningCount === 3)
            check("the one timer is armed for the soonest (60 s)", c.dueRunning && Math.abs(c.dueIn - 60000) < 300, c.dueIn)
            fake += 30000; c.check()
            check("nothing rings after 30 s", c.ringing.length === 0 && c.island.calls.length === 0)
            c.pauseTimer(t1)
            check("pausing keeps what is left", c.timerById(t1).pausedLeft === 570000, c.timerById(t1).pausedLeft)
            fake += min(5); c.check()
            check("a paused timer does not ring, the 60 s one did, once", c.ringing.length === 1 && c.island.calls.length === 1 && c.timerById(t2).done, JSON.stringify(c.ringing))
            c.resumeTimer(t1)
            check("resume ends it 570 s from now", c.timerById(t1).endsAt === fake + 570000 && c.timerById(t1).pausedLeft === 0)
            fake += 100000; c.resetTimer(t1)
            check("reset starts it again from the full 10 min", c.timerById(t1).endsAt === fake + 600000)
            check("only paused-or-running timers arm the timer", c.dueRunning)
            c.pauseTimer(t1); c.pauseTimer(t3); c.removeTimer(t2)
            check("all paused: nothing armed", !c.dueRunning && c.runningCount === 0)
            c.resumeTimer(t3)
            check("resumed one arms it again", c.dueRunning)
            c.cancelTimers()
            check("cancel removes them all and disarms", c.timers.length === 0 && !c.dueRunning)
            return 100
        } },
        { name: "timers: ring (island, notification, sound) and DND", run: function() {
            wipe(); fake = sat10
            const c = fresh()
            c.addTimer(60, "tea")
            fake += 61000; c.check()
            const m = c.island.calls[0]
            check("island message has the label, stays up and can be clicked", m && m.title === "tea is done" && m.ms >= 300000 && typeof m.run === "function" && m.kind.startsWith("clock-"), JSON.stringify(m))
            check("a notification as well, normal urgency", notifies("tea is done").length === 1 && notifies().every(n => n.indexOf("critical") < 0), JSON.stringify(Sys.runs))
            check("sound plays", Sys.played.length === 1 && (Sys.played[0] === "alarm-clock-elapsed" || Sys.played[0] === "complete"), JSON.stringify(Sys.played))
            m.run()
            check("a click dismisses and removes the finished timer", c.ringing.length === 0 && c.timers.length === 0)
            wipe(); Notif.dnd = true
            c.addTimer(60, "pasta"); fake += 61000; c.check()
            check("DND: timers still show on the island", c.island.calls.length === 2 && c.island.calls[1].title === "pasta is done")
            check("DND: and are listed (a normal notification Notif keeps without a popup), no sound", notifies("pasta").length === 1 && notifies().every(n => n.indexOf("critical") < 0) && Sys.played.length === 0)
            Notif.dnd = false
            return 100
        } },
        { name: "timers: survive a reload; one that ended while suspended rings once, late", run: function() {
            wipe(); fake = sat10
            const a = mk("reload1")
            a.addTimer(600, "tea"); const id = a.addTimer(1800, "bake")
            fake += min(2)
            const b = mk("reload1")                      // the shell reloaded two minutes in
            check("both timers are back with their end times", b.timers.length === 2 && b.timerById(id).endsAt === sat10 + 1800000)
            check("it rings at the same moment as before", b.dueRunning)
            fake = sat10 + min(60)                       // the laptop slept an hour: Qt's timer did not fire
            check("nothing rang yet (asleep)", b.island.calls.length === 0)
            b.minuteTick()                               // the bar's minute tick on wake
            check("both ring on wake, once each", b.island.calls.length === 2 && notifies().length === 2, b.island.calls.length)
            check("marked late", b.island.calls.every(m => m.sub.indexOf("late") >= 0), b.island.calls[0].sub)
            b.minuteTick(); b.check()
            check("and not again", b.island.calls.length === 2 && notifies().length === 2)
            const c = mk("reload1")                      // another reload with them finished
            check("a finished timer does not ring after a reload", c.island.calls.length === 0 && c.timers.every(t => t.done))
            return 100
        } },
        { name: "timers: ring while Qt's timer is armed (the real one-shot)", run: function() {
            wipe(); fake = sat10
            const c = coreComp.createObject(root, { stateFile: state + "/real.json", clockFn: null, island: islandComp.createObject(root) })    // the real clock
            root.liveCore = c
            c.addTimer(0.3, "blink")
            check("armed", c.dueRunning)
            return 700
        } },
        { name: "timers: the armed timer fired by itself", run: function() {
            const c = root.liveCore
            // the fake clock stands still, so the Timer woke and found nothing due: it must not spin
            check("rang by itself on the real clock, once", c.island.calls.length === 1 && c.island.calls[0].title === "blink is done", c.island.calls.length)
            c.check()
            check("an extra check does not ring it twice", c.island.calls.length === 1)
            check("and disarms after the last one", !c.dueRunning)
            return 100
        } },

        { name: "alarms: weekdays, once per occurrence", run: function() {
            wipe(); fake = sat10
            const c = fresh()
            const id = c.addAlarm({ time: "07:30", days: ["mon", "tue", "wed", "thu", "fri"], date: "", label: "stand-up" })
            check("armed for Monday", c.dueRunning && c.nextAlarmAt() === mon0730)
            fake = tm(2026, 11, 15, 12, 0); c.check()
            check("Sunday: nothing", c.island.calls.length === 0)
            fake = mon0730 + 5000; c.check()
            check("Monday 07:30: rings once, critical notification, sound", c.island.calls.length === 1 && c.island.calls[0].title === "stand-up" && notifies("critical").length === 1 && Sys.played.length === 1, JSON.stringify(Sys.runs))
            c.check(); c.minuteTick()
            check("same minute again: not twice", c.island.calls.length === 1)
            check("a recurring alarm stays on", c.alarmById(id).enabled)
            fake = tm(2026, 11, 17, 7, 30, 1); c.check()
            check("Tuesday: rings again", c.island.calls.length === 2)
            check("next is Wednesday", c.nextAlarmAt() === tm(2026, 11, 18, 7, 30))
            return 100
        } },
        { name: "alarms: a single date; off means off; a new one does not ring for a time that has gone", run: function() {
            wipe(); fake = sat10
            const c = fresh()
            c.addAlarm({ time: "09:00", days: [], date: "2026-11-15", label: "tomorrow" })
            const off = c.addAlarm({ time: "10:30", days: [], date: "2026-11-14", label: "off one" })
            c.setAlarmEnabled(off, false)
            const daily = c.addAlarm({ time: "09:00", days: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"], date: "", label: "earlier today" })
            fake = tm(2026, 11, 14, 10, 45); c.check()
            check("disabled and already-gone alarms are silent", c.island.calls.length === 0)
            fake = tm(2026, 11, 15, 9, 0, 3); c.check()
            check("the one-off rings on its date, and the daily at 09:00 too", c.island.calls.length === 2, c.island.calls.map(m => m.title).join())
            check("the one-off switches itself off", !c.alarmById(c.alarms[0].id).enabled && c.alarmById(daily).enabled)
            fake = tm(2026, 11, 16, 9, 0, 3); c.check()
            check("only the daily comes back", c.island.calls.length === 3)
            c.setAlarmEnabled(c.alarms[0].id, true)
            check("a past one-off cannot be switched back on", !c.alarms[0].enabled)
            return 100
        } },
        { name: "alarms: the shell reloaded at the minute still rings; long off means only a quiet note", run: function() {
            wipe(); fake = sat10
            const a = mk("rl2")
            a.addAlarm({ time: "07:30", days: ["mon", "tue", "wed", "thu", "fri"], date: "", label: "stand-up" })
            fake = mon0730 + 20000                       // reloading right then
            const b = mk("rl2")
            check("rings after the reload (20 s past), not marked late", b.island.calls.length === 1 && b.island.calls[0].sub.indexOf("late") < 0, JSON.stringify(b.island.calls))
            const c = mk("rl2")
            check("and a second reload does not ring it again", c.island.calls.length === 0)
            wipe(); fake = sat10
            const d = mk("rl3")
            d.addAlarm({ time: "07:30", days: ["mon", "tue", "wed", "thu", "fri"], date: "", label: "gym" })
            fake = mon0730 + min(25)                     // the laptop was off, switched on 25 minutes past
            const e = mk("rl3")
            check("more than 10 minutes late: no ring, no island, no sound", e.island.calls.length === 0 && Sys.played.length === 0 && e.ringing.length === 0)
            check("only a quiet low-urgency note", notifies("Missed alarm").length === 1 && notifies("Missed alarm")[0].indexOf("-u low") >= 0 && e.missed.length === 1, JSON.stringify(Sys.runs))
            const f = mk("rl3")
            check("the note is made once", notifies("Missed alarm").length === 1 && f.island.calls.length === 0)
            wipe(); fake = sat10
            const g = mk("rl4")
            g.addAlarm({ time: "07:30", days: ["mon"], date: "", label: "late" })
            fake = mon0730 + min(9) + 30000
            const h = mk("rl4")
            check("9.5 minutes late still rings, marked late", h.island.calls.length === 1 && h.island.calls[0].sub.indexOf("late") >= 0, JSON.stringify(h.island.calls))
            return 100
        } },
        { name: "alarms: through Do Not Disturb, snooze by click and by IPC call", run: function() {
            wipe(); fake = sat10; Notif.dnd = true
            const c = fresh()
            c.addAlarm({ time: "10:05", days: [], date: "2026-11-14", label: "wake up" })
            fake = tm(2026, 11, 14, 10, 5, 2); c.check()
            check("DND on: the alarm still shows, is critical (pops up) and makes its sound", c.island.calls.length === 1 && notifies("critical").length === 1 && Sys.played.length === 1)
            check("the island offers snooze on click", c.island.calls[0].sub.indexOf("snooze 5 min") >= 0, c.island.calls[0].sub)
            c.island.calls[0].run()
            check("click snoozes 5 minutes: a timer ringing like an alarm", c.timers.length === 1 && c.timers[0].alarm && c.timers[0].total === 300000 && c.timers[0].label === "wake up" && c.ringing.length === 0)
            wipe(); Notif.dnd = true
            fake += min(5) + 1000; c.check()
            check("it rings again as an alarm, through DND", c.island.calls.length === 2 && c.island.calls[1].title === "wake up" && notifies("critical").length === 1 && Sys.played.length === 1)
            const r = c.snooze()
            check("snooze() (IPC) snoozes the ringing one", r.indexOf("snoozed 5 min") === 0 && c.timers.length === 1 && !c.timers[0].done, r)
            check("snooze() with nothing ringing says so", (c.cancel("all"), c.snooze()) === "nothing is ringing")
            Notif.dnd = false
            return 100
        } },
        { name: "alarms: the sound repeats twice more, 30 s apart, if not answered", run: function() {
            wipe(); fake = sat10
            const c = fresh()
            c.addAlarm({ time: "10:01", days: [], date: "2026-11-14", label: "" })
            fake = tm(2026, 11, 14, 10, 1, 1); c.check()
            check("armed for the repeat", c.dueRunning && Sys.played.length === 1)
            fake += 31000; c.check(); fake += 31000; c.check(); fake += 31000; c.check()
            check("three sounds in all, then quiet", Sys.played.length === 3, Sys.played.length)
            c.dismissAll()
            check("dismissed: nothing armed", !c.dueRunning && c.ringing.length === 0)
            return 100
        } },
        { name: "locked screen: rings, and is shown again after unlocking", run: function() {
            wipe(); fake = sat10
            const c = fresh()
            c.lockCmd = ["echo", "true"]
            c.addAlarm({ time: "10:02", days: [], date: "2026-11-14", label: "locked one" })
            fake = tm(2026, 11, 14, 10, 2, 1); c.check()
            root.liveCore = c
            return 600
        } },
        { name: "locked screen: after the unlock", run: function() {
            const c = root.liveCore
            check("it noticed the lock", c.ringing.length === 1 && c.ringing[0].whileLocked, JSON.stringify(c.ringing))
            check("sound and list entry happened at once", Sys.played.length >= 1 && notifies("locked one").length === 1)
            const before = c.island.calls.length
            c.unlocked()
            check("unlocked(): the island shows it again, once", c.island.calls.length === before + 1 && c.island.calls[before].title === "locked one" && !c.ringing[0].whileLocked)
            c.unlocked()
            check("and not a third time", c.island.calls.length === before + 1)
            c.dismissAll()
            return 100
        } },

        { name: "stopwatch: start, lap, stop, across a reload", run: function() {
            wipe(); fake = sat10
            const a = mk("sw1")
            a.stopwatchAction("start")
            fake += 65000
            a.stopwatchAction("lap")
            fake += 5000
            check("elapsed is 70 s", a.swElapsed() === 70000 && a.stopwatch.laps.length === 1 && a.stopwatch.laps[0] === 65000)
            const b = mk("sw1")                          // the shell reloaded while it ran
            check("still running after the reload, elapsed kept", b.stopwatch.running && b.swElapsed() === 70000)
            fake += 10000
            check("and counting", b.swElapsed() === 80000)
            b.stopwatchAction("stop")
            fake += 99000
            const c = mk("sw1")
            check("stopped: elapsed frozen across another reload", !c.stopwatch.running && c.swElapsed() === 80000 && c.stopwatch.laps.length === 1)
            c.stopwatchAction("start"); fake += 1000
            check("resume continues from where it stopped", c.swElapsed() === 81000)
            c.stopwatchAction("reset")
            check("reset zeroes it and the laps", c.swElapsed() === 0 && c.stopwatch.laps.length === 0 && !c.stopwatch.running)
            check("a bad action is refused", c.stopwatchAction("dance").indexOf("usage") === 0)
            check("a running stopwatch arms nothing (it only counts)", !c.dueRunning)
            return 100
        } },

        { name: "the one-timer rule: no ticker unless a view showing seconds is open", run: function() {
            wipe(); fake = sat10
            const c = fresh()
            c.addTimer(600, "tea"); c.stopwatchAction("start")
            check("a running timer and stopwatch, nothing watching: no 1 Hz ticker", !c.tickerRunning && c.dueRunning)
            c.watch("panel", true)
            check("a view that shows seconds starts the ticker", c.tickerRunning)
            c.watch("settings", true); c.watch("panel", false)
            check("it stays while any view is open", c.tickerRunning)
            c.watch("settings", false)
            check("and stops with the last one", !c.tickerRunning)
            c.cancelTimers()
            check("with nothing due the one timer is off too", !c.dueRunning && !c.tickerRunning)
            return 100
        } },

        { name: "world clock: UTC offsets from tz-now, New York spring forward", run: function() {
            wipe()
            const w = fresh(); root.liveCore = w
            w.setCities([{ name: "New York", tz: "America/New_York" }, { name: "London", tz: "Europe/London" }, { name: "Nowhere", tz: "Mars/Base" }])
            fake = Date.UTC(2026, 2, 8, 6, 30)           // 06:30 UTC, 01:30 in New York, 30 minutes before the switch
            w.worldWatch("t", true)
            return 900
        } },
        { name: "world clock: before and after the New York switch", run: function() {
            const w = root.liveCore
            let ny = w.worldLines[0], lon = w.worldLines[1]
            check("New York is EST (UTC-5) at 01:30", ny.ok && ny.time === "01:30" && ny.abbr === "EST", JSON.stringify(ny))
            check("its next change is 07:00 UTC (02:00 EST)", w.world["America/New_York"].next === Date.UTC(2026, 2, 8, 7, 0) / 1000, w.world["America/New_York"].next)
            check("London is GMT, 06:30", lon.time === "06:30" && lon.abbr === "GMT", JSON.stringify(lon))
            check("an unknown zone is flagged, not shown as UTC", !w.worldLines[2].ok && w.worldLines[2].note === "unknown zone", JSON.stringify(w.worldLines[2]))
            root.fake = Date.UTC(2026, 2, 8, 7, 1)
            w.minuteTick()                               // the bar's minute: the offset is stale, ask again
            return 900
        } },
        { name: "world clock: after the switch", run: function() {
            const w = root.liveCore
            const ny = w.worldLines[0]
            check("New York is EDT (UTC-4) at 03:01 and says so", ny.time === "03:01" && ny.abbr === "EDT", JSON.stringify(ny))
            check("the day did not shift", ny.note === "", ny.note)
            // the local zone of this test run is New York too: "same time"
            check("compared with here: same time", ny.diff === "same time", ny.diff)
            check("pure conversion across the switch: 06:59 UTC is 01:59, 07:00 UTC is 03:00", C.worldTime(Date.UTC(2026, 2, 8, 6, 59), -18000, 0).time === "01:59" && C.worldTime(Date.UTC(2026, 2, 8, 7, 0), -14400, 0).time === "03:00")
            root.fake = Date.UTC(2026, 2, 29, 0, 30)     // London springs forward at 01:00 UTC
            w.minuteTick()
            return 900
        } },
        { name: "world clock: London spring forward (Europe/London)", run: function() {
            const w = root.liveCore
            let lon = w.worldLines[1]
            check("00:30 UTC: London GMT 00:30, next change 01:00 UTC", lon.time === "00:30" && lon.abbr === "GMT" && w.world["Europe/London"].next === Date.UTC(2026, 2, 29, 1, 0) / 1000, JSON.stringify(lon) + w.world["Europe/London"].next)
            root.fake = Date.UTC(2026, 2, 29, 1, 30)
            w.minuteTick()
            return 900
        } },
        { name: "world clock: London after the switch, and day shifts", run: function() {
            const w = root.liveCore
            const lon = w.worldLines[1]
            check("01:30 UTC: London BST 02:30, +1 h from UTC", lon.time === "02:30" && lon.abbr === "BST", JSON.stringify(lon))
            check("London BST to here (EDT, UTC-4) is +5 h", lon.diff === "+5 h", lon.diff)
            const t = C.worldTime(Date.UTC(2026, 3, 1, 23, 30), 32400, -14400)
            check("Tokyo at 23:30 UTC is 08:30 tomorrow, +13 h from New York", t.time === "08:30" && t.dayShift === 1 && t.diffHours === 13 && C.diffText(13) === "+13 h", JSON.stringify(t))
            const y = C.worldTime(Date.UTC(2026, 3, 1, 3, 0), -18000, 0)
            check("a zone behind UTC at 03:00 is on yesterday", y.time === "22:00" && y.dayShift === -1, JSON.stringify(y))
            check("half-hour zones", C.diffText(5.5) === "+5.5 h" && C.diffText(-3.5) === "−3.5 h" && C.diffText(0) === "same time")
            root.liveCore.worldWatch("t", false)
            check("when nothing shows the world clock nothing asks again", root.liveCore.worldWatchers === 0)
            return 100
        } },
        { name: "tz-now and the zone check", run: function() {
            const c = fresh()
            c.loadZones()
            return 800
        } },
        { name: "tz-now: zone names for the settings check", run: function() {
            const c = Clocks.core
            Clocks.core.loadZones()
            return 700
        } },

        { name: "launcher rows: timer", run: function() {
            wipe(); fake = sat10
            const c = fresh()
            const rows = q => c.launcherRows(q, viewStub)
            let r = rows("timer 10m tea")
            check("\"timer 10m tea\": one row that starts it", r.length === 1 && r[0].label === "Timer 10 min: tea" && r[0].sub.indexOf("10:10") >= 0, JSON.stringify(r.map(x => x.label + "|" + x.sub)))
            r[0].run()
            check("Enter starts it and closes the launcher", c.timers.length === 1 && c.timers[0].total === 600000 && c.timers[0].label === "tea" && viewStub.closed === 1)
            rows("timer 1h30")[0].run()
            check("\"timer 1h30\" is 90 minutes", c.timers[1].total === 5400000)
            rows("timer 25")[0].run()
            check("\"timer 25\" is 25 minutes", c.timers[2].total === 1500000)
            r = rows("timer banana")
            check("a bad timer spec: one row, says why, does nothing", r.length === 1 && r[0].sub.indexOf("not understood") >= 0 && (r[0].run(), c.timers.length === 3))
            check("\"timer\" alone: a hint row", rows("timer").length === 1 && rows("timer")[0].sub.indexOf("10m tea") >= 0)
            r = rows("timers")
            check("\"timers\": a pause row and a cancel row per timer", r.length === 6 && r[0].label === "Pause tea" && r[1].label === "Cancel tea", r.map(x => x.label).join(" / "))
            r[0].run()
            check("Enter on Pause pauses it", c.timers[0].pausedLeft > 0)
            check("and the row now says Resume", rows("timers")[0].label === "Resume tea" && rows("timers")[0].sub.indexOf("paused") >= 0)
            rows("timers")[1].run()
            check("Enter on Cancel removes it", c.timers.length === 2 && c.timers.every(t => t.label !== "tea"))
            check("\"timers\" with none says so", (c.cancelTimers(), rows("timers")[0].label === "No timers running"))
            return 100
        } },
        { name: "launcher rows: alarm, stopwatch, and silence for other queries", run: function() {
            wipe(); fake = sat10
            const c = fresh()
            const rows = q => c.launcherRows(q, viewStub)
            let r = rows("alarm 7:30")
            check("\"alarm 7:30\": tomorrow at 07:30", r.length === 1 && r[0].label === "Alarm 07:30" && r[0].sub.indexOf("tomorrow") >= 0, JSON.stringify(r.map(x => x.label + "|" + x.sub)))
            r[0].run()
            check("Enter sets it", c.alarms.length === 1 && c.alarms[0].date === "2026-11-15" && c.alarms[0].time === "07:30")
            rows("alarm 6:45am weekdays stand-up")[0].run()
            check("\"alarm 6:45am weekdays stand-up\"", c.alarms[1].time === "06:45" && c.alarms[1].days.length === 5 && c.alarms[1].label === "stand-up" && rows("alarm 6:45am weekdays stand-up")[0].sub.indexOf("weekdays") >= 0)
            rows("alarm tomorrow 9")[0].run()
            check("\"alarm tomorrow 9\"", c.alarms[2].time === "09:00" && c.alarms[2].date === "2026-11-15")
            check("a bad alarm: a row with the reason, no new alarm", rows("alarm 25:99")[0].sub.indexOf("say a time") >= 0 && (rows("alarm 25:99")[0].run(), c.alarms.length === 3))
            r = rows("alarms")
            check("\"alarms\" lists them, Enter turns one off", r.length === 3 && (r[0].run(), !c.alarms[0].enabled) && rows("alarms")[0].label.indexOf("(off)") > 0)
            r = rows("stopwatch")
            check("\"stopwatch\": Start", r.length === 1 && r[0].label === "Start stopwatch")
            r[0].run()
            check("Enter starts it", c.stopwatch.running)
            r = rows("stopwatch")
            check("running: Stop, Lap, Reset", r.map(x => x.label).join() === "Stop stopwatch,Lap,Reset stopwatch", r.map(x => x.label).join())
            r[1].run(); fake += 5000; rows("stopwatch")[0].run()
            check("Lap and Stop work", c.stopwatch.laps.length === 1 && !c.stopwatch.running && rows("stopwatch")[0].label === "Resume stopwatch")
            check("queries that are not ours give no rows", ["", "firefox", "tim", "alarmist", "timer10m", "stop"].every(q => rows(q).length === 0), ["", "firefox", "tim", "alarmist", "timer10m", "stop"].map(q => rows(q).length).join())
            check("the provider never throws on junk", ["timer " + "9".repeat(400), "alarm \u0000", "timer  ", "ALARM 7"].every(q => { try { rows(q); return true } catch (e) { return false } }))
            return 100
        } },
        { name: "IPC-level helpers: timer, alarm, list, cancel", run: function() {
            wipe(); fake = sat10
            const c = fresh()
            const r1 = c.timerSpec("10m tea"), r2 = c.alarmSpec("6:45am weekdays stand-up"), r3 = c.timerSpec("nonsense")
            check("timer(spec) says what it understood", r1.indexOf("timer 10 min: tea started") === 0, r1)
            check("alarm(spec) says what it understood", r2.indexOf("alarm 06:45 stand-up set for weekdays") === 0, r2)
            check("a bad spec starts with error:", r3.indexOf("error: ") === 0, r3)
            const l = c.list().split("\n")
            check("list(): a timer, an alarm and the stopwatch", l.length === 3 && l[0].indexOf("timer ") === 0 && l[1].indexOf("alarm ") === 0 && l[2].indexOf("stopwatch") === 0, c.list())
            const id = l[0].split(/\s+/)[1], aid = l[1].split(/\s+/)[1]
            check("cancel(id) removes a timer", c.cancel(id).indexOf("cancelled") > 0 && c.timers.length === 0)
            check("cancel(id) removes an alarm", c.cancel(aid).indexOf("removed") > 0 && c.alarms.length === 0)
            check("cancel of something unknown says so", c.cancel("zzz").indexOf("error") === 0)
            c.timerSpec("5m"); c.timerSpec("6m")
            check("cancel all", c.cancel("all") === "cancelled 2 timers" && c.timers.length === 0)
            check("too many timers is refused", (() => { for (let i = 0; i < 31; i++) c.timerSpec("1h"); return c.timerSpec("1h").indexOf("error") === 0 })())
            c.cancel("all")
            check("tip text and summary", c.tip === "" && (c.timerSpec("12m tea"), c.tipFor("x") === "Timer: tea 12 min left"), c.tipFor("x"))
            check("two timers: tip names the soonest and counts the rest", (c.timerSpec("5m eggs"), c.tipFor("x") === "Timer: eggs 5 min left (+1 more)"), c.tipFor("x"))
            c.cancel("all")
            return 100
        } },

        { name: "ClockPanel: collapsed is one line", run: function() {
            wipe(); fake = sat10
            const k = Clocks.core
            k.clockFn = () => root.fake; k.lockCmd = ["echo", "false"]
            k.cancelTimers(); for (const a of k.alarms.slice()) k.removeAlarm(a.id); k.stopwatchAction("reset")
            Clocks.island = islandComp.createObject(root)
            k.addTimer(600, "tea"); k.addTimer(60, "")
            k.addAlarm({ time: "07:30", days: ["mon", "tue", "wed", "thu", "fri"], date: "", label: "stand-up" })
            return 300
        } },
        { name: "ClockPanel: summary, then open", run: function() {
            const p = panel
            check("the panel is in the calendar", !!p)
            const sum = byName(p, "clockSummary")[0]
            check("collapsed summary", sum && sum.text === "2 timers · next alarm Mon 07:30", sum ? sum.text : "none")
            check("nothing else is shown", byName(p, "timerInput").length === 0 && byName(p, "alarmInput").length === 0)
            check("collapsed: no ticker, no world lookups", !Clocks.core.tickerRunning && Clocks.core.worldWatchers === 0)
            click(byName(p, "clockHeader")[0])
            return 300
        } },
        { name: "ClockPanel: open shows timers, alarms, stopwatch, world clock", run: function() {
            const p = panel
            check("open", p.open)
            check("two timers with pause, reset and cancel buttons", byName(p, "pauseBtn").length === 2 && byName(p, "resetBtn").length === 2 && byName(p, "cancelBtn").length === 2)
            check("timer left shown as m:ss", byName(p, "timerLeft").map(x => x.text).join() === "10:00,1:00", byName(p, "timerLeft").map(x => x.text).join())
            check("one alarm with a switch", byName(p, "alarmSwitch").length === 1)
            check("world clock asked for while open, ticker running (timers count)", Clocks.core.worldWatchers === 1 && Clocks.core.tickerRunning)
            root.fake += 5000
            return 1300
        } },
        { name: "ClockPanel: the display moves with the ticker; pause and resume", run: function() {
            const p = panel
            check("after 5 s the left time shows 9:55 and 0:55", byName(p, "timerLeft").map(x => x.text).join() === "9:55,0:55", byName(p, "timerLeft").map(x => x.text).join())
            click(byName(p, "pauseBtn")[0])
            check("Pause pauses the first timer", Clocks.timers[0].pausedLeft > 0)
            return 500
        } },
        { name: "ClockPanel: resume, reset, cancel", run: function() {
            const p = panel
            check("the button says Resume", textsOf(byName(p, "pauseBtn")[0]).join() === "Resume", textsOf(byName(p, "pauseBtn")[0]).join())
            check("the time is shown paused", byName(p, "timerLeft")[0].text.indexOf("‖") > 0, byName(p, "timerLeft")[0].text)
            click(byName(p, "pauseBtn")[0])
            check("Resume runs it again", Clocks.timers[0].pausedLeft === 0)
            return 500
        } },
        { name: "ClockPanel: reset, cancel", run: function() {
            const p = panel
            click(byName(p, "resetBtn")[0])
            check("Reset restores the full time", Clocks.timers[0].endsAt === root.fake + 600000, Clocks.timers[0].endsAt - root.fake)
            click(byName(p, "cancelBtn")[1])
            check("× cancels the second", Clocks.timers.length === 1 && Clocks.timers[0].label === "tea")
            return 500
        } },
        { name: "ClockPanel: add a timer and an alarm", run: function() {
            const p = panel
            const ti = byName(p, "timerInput")[0]
            ti.text = "banana"; click(byName(p, "timerAdd")[0])
            check("a bad timer spec keeps the text and shows why", Clocks.timers.length === 1 && ti.text === "banana" && textsOf(p).some(t => t.indexOf("not understood") >= 0))
            ti.text = "25 laundry"; click(byName(p, "timerAdd")[0])
            check("a good one is started and the field cleared", Clocks.timers.length === 2 && ti.text === "" && Clocks.timers[1].label === "laundry" && Clocks.timers[1].total === 1500000)
            ti.input.forceActiveFocus(); ti.text = "3m"
            ev.keyClick(Qt.Key_Return, Qt.NoModifier, -1)
            check("Enter in the field adds it", Clocks.timers.length === 3 && Clocks.timers[2].total === 180000, Clocks.timers.length)
            const alarmIn = byName(p, "alarmInput")[0]
            alarmIn.text = "99:00"; click(byName(p, "alarmAdd")[0])
            check("a bad alarm is refused with the reason", Clocks.alarms.length === 1 && textsOf(p).some(t => t.indexOf("say a time") >= 0))
            alarmIn.text = "6:45am weekdays gym"; click(byName(p, "alarmAdd")[0])
            check("a good alarm is added", Clocks.alarms.length === 2 && Clocks.alarms[1].label === "gym" && Clocks.alarms[1].time === "06:45")
            click(byName(p, "alarmSwitch")[1])
            check("its switch turns it off", !Clocks.alarms[1].enabled)
            click(byName(p, "alarmSwitch")[1])
            check("and on", Clocks.alarms[1].enabled)
            click(byName(p, "alarmDelete")[1])
            check("× deletes it", Clocks.alarms.length === 1)
            return 100
        } },
        { name: "ClockPanel: stopwatch", run: function() {
            const p = panel
            click(byName(p, "swToggle")[0])
            check("Start runs it", Clocks.stopwatch.running)
            root.fake += 7000
            return 1300
        } },
        { name: "ClockPanel: stopwatch shows seconds, laps", run: function() {
            const p = panel
            check("elapsed shows 0:07", byName(p, "swElapsed")[0].text === "0:07", byName(p, "swElapsed")[0].text)
            click(byName(p, "swLap")[0])
            check("Lap records one", Clocks.stopwatch.laps.length === 1 && textsOf(p).some(t => t.indexOf("Lap 1") === 0))
            click(byName(p, "swToggle")[0])
            check("Stop stops it", !Clocks.stopwatch.running)
            return 100
        } },
        { name: "ClockPanel: a ringing alarm offers Snooze and Dismiss; closing stops the ticker", run: function() {
            const p = panel
            const k = Clocks.core
            k.addAlarm({ time: "10:03", days: [], date: "2026-11-14", label: "ring ring" })
            root.fake = tm(2026, 11, 14, 10, 3, 2); k.check()
            return 300
        } },
        { name: "ClockPanel: ringing row", run: function() {
            const p = panel
            const k = Clocks.core
            check("the collapsed line would be orange: it is ringing", Clocks.ringing.length === 1 && textsOf(p).some(t => t === "ring ring"), textsOf(p).join("|"))
            const snooze = findAll(p, x => x.text !== undefined && String(x.text).indexOf("Snooze") === 0)[0]
            click(snooze.parent)
            check("Snooze starts the 5 min timer", Clocks.ringing.length === 0 && k.timers.some(t => t.alarm && t.total === 300000))
            click(byName(p, "clockHeader")[0])
            check("collapsing: no ticker (only the timers' end is armed)", !p.open && !Clocks.core.tickerRunning && Clocks.core.worldWatchers === 0 && Clocks.core.dueRunning)
            check("collapsed line again", byName(p, "clockSummary")[0].text.indexOf("timers") > 0, byName(p, "clockSummary")[0].text)
            return 100
        } },

        { name: "settings page: alarms, snooze, sound, cities", run: function() {
            const k = Clocks.core
            wipe(); k.cancelTimers(); for (const a of k.alarms.slice()) k.removeAlarm(a.id)
            k.addAlarm({ time: "07:30", days: ["mon", "tue", "wed", "thu", "fri"], date: "", label: "stand-up" })
            k.addAlarm({ time: "22:15", days: [], date: "2026-11-20", label: "" })
            k.setCities([{ name: "UTC", tz: "UTC" }, { name: "London", tz: "Europe/London" }, { name: "Tokyo", tz: "Asia/Tokyo" }])
            setWin.visible = true
            return 700
        } },
        { name: "settings page: rows", run: function() {
            const k = Clocks.core
            const sw = findAll(setPage, x => x.settingRow === true && x.checked !== undefined && x.label.indexOf(":") === 2)
            check("a switch row per alarm", sw.length === 2 && sw[0].label === "07:30  stand-up" && sw[0].sub === "weekdays", sw.map(x => x.label + "|" + x.sub).join(";"))
            click(findAll(sw[1], x => x.width === 46)[0])
            check("its switch turns the alarm off", !k.alarms[1].enabled)
            const rm = findAll(setPage, x => x.settingRow === true && x.label.indexOf("Remove ") === 0)
            check("a Remove button per alarm", rm.length === 2)
            const st = findAll(setPage, x => x.settingRow === true && x.label === "Snooze for")[0]
            st.edited(10)
            check("snooze minutes are written to clocks.json and used", Clocks.core.snoozeMinutes === 10 && Clocks.config.values.snoozeMinutes === 10)
            const snd = findAll(setPage, x => x.settingRow === true && x.label === "Play a sound")[0]
            snd.edited(false); wipe()
            k.addAlarm({ time: "10:04", days: [], date: "2026-11-14", label: "" }); root.fake = tm(2026, 11, 14, 10, 4, 2); k.check()
            check("sound off: the alarm still goes to the list but is silent", Sys.played.length === 0 && notifies().length === 1, JSON.stringify(Sys.runs))
            snd.edited(true)
            const nw = findAll(setPage, x => x.settingRow === true && x.label === "New alarm")[0]
            check("a bad alarm spec is refused by the field", nw.valid("nonsense") === false && nw.valid("8:15 mon") === true)
            nw.edited("8:15 mon yoga")
            check("a new alarm from the page", k.alarms.some(a => a.label === "yoga"))
            const ch = findAll(setPage, x => x.settingRow === true && x.label === "Cities")[0]
            check("the cities are listed", same(ch.items, ["UTC", "Europe/London", "Asia/Tokyo"]), JSON.stringify(ch.items))
            ch.addOne("Mars/Base")
            check("a made-up zone is refused with a reason", k.cities.length === 3 && setPage.cityError === "not a time zone: Mars/Base", setPage.cityError)
            check("a name that is not even shaped like a zone is refused", !ch.addOne("../etc/passwd") && k.cities.length === 3)
            check("zone check knows the real ones", k.validZone("Europe/Berlin") && k.validZone("America/New_York") && !k.validZone("Europe/Berlinn"), k.zoneNames.length)
            check("a good one with a label is added", ch.addOne("Berlin=Europe/Berlin") && k.cities.length === 4 && k.cities[3].name === "Berlin" && k.cities[3].tz === "Europe/Berlin", JSON.stringify(k.cities))
            check("a good one without a label is named from the zone", ch.addOne("America/Los_Angeles") && k.cities[4].name === "Los Angeles", JSON.stringify(k.cities))
            ch.removeAt(0)
            check("a city can be removed; the file keeps the other keys", k.cities.length === 4 && Clocks.config.values.sound === true && Clocks.config.values.snoozeMinutes === 10)
            return 100
        } }
    ]
    property var liveCore: null
    // pictures: the same scene in dark and light (ClockPanel collapsed and open inside the calendar, the settings page)
    function scene(dark) {
        const name = dark ? "dark" : "light"
        return [
            { name: "pictures (" + name + "): set the scene", run: function() {
                const k = Clocks.core
                setDark(dark)
                root.fake = sat10
                k.dismissAll(); k.cancelTimers(); for (const a of k.alarms.slice()) k.removeAlarm(a.id)
                k.setCities([{ name: "UTC", tz: "UTC" }, { name: "London", tz: "Europe/London" }, { name: "Tokyo", tz: "Asia/Tokyo" }])
                k.addTimer(600, "tea"); k.addTimer(1500, "laundry")
                k.addAlarm({ time: "07:30", days: ["mon", "tue", "wed", "thu", "fri"], date: "", label: "stand-up" })
                k.addAlarm({ time: "22:15", days: [], date: "2026-11-20", label: "flight" })
                k.stopwatchAction("reset")
                panel.open = false
                root.fake += 4000
                return 500
            } },
            { name: "pictures (" + name + "): collapsed", run: function() { picture(calCard, "panel-collapsed-" + name); return 400 } },
            { name: "pictures (" + name + "): open", run: function() {
                click(byName(panel, "clockHeader")[0])
                const k = Clocks.core
                k.stopwatchAction("start"); root.fake += 83000; k.stopwatchAction("lap"); root.fake += 20000; k.stopwatchAction("stop")
                return 1300
            } },
            { name: "pictures (" + name + "): open, taken", run: function() { picture(calCard, "panel-open-" + name); return 400 } },
            { name: "pictures (" + name + "): settings page", run: function() { click(byName(panel, "clockHeader")[0]); setWin.visible = true; return 900 } },
            { name: "pictures (" + name + "): settings page, taken", run: function() { picture(setCard, "settings-clock-" + name); return 400 } }
        ]
    }
    Component.onCompleted: {
        cases = cases.concat(scene(true)).concat(scene(false))
        const a = Clocks.core
        a.clockFn = () => root.fake
    }

    property int at: 0
    Timer {
        interval: 600; running: true
        onTriggered: {
            if (root.grabbing > 0 || Date.now() < root.holdUntil) { interval = 50; restart(); return }
            if (root.at >= root.cases.length) { console.log("CTEST RESULT pass " + root.passed + " fail " + root.failed); done.start(); return }
            const c = root.cases[root.at++]
            console.log("CTEST case: " + c.name)
            let wait = 100
            try { wait = c.run() } catch (e) { root.failed++; console.log("CTEST FAIL " + c.name + " threw: " + e + " " + e.stack) }
            interval = Math.max(20, wait || 100)
            restart()
        }
    }
    Timer { id: done; interval: 400; onTriggered: Qt.quit() }
}
