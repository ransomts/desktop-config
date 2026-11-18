//@ pragma IconTheme Papirus-Dark
// Tests for the launcher's "event ..." row (EventQuick.qml), Launcher.openWith and the calendar popup's
// "+ Add event" line (Calendar.qml). NOT part of the shell: ~/.local/bin/events-test copies the real
// files next to this one (Launcher.qml as a plain window), with the stub Sys, and runs it offscreen.
// `quick-event parse` is faked with canned answers (EventQuick.fake) except in the "real script" cases, which
// run bin/quick-event for real with QUICK_EVENT_NOW fixed. Nothing is launched (Sys records it).
// Output lines: "ETEST PASS|FAIL ..." and "ETEST RESULT pass N fail M". Pictures go to $EVENTS_TEST_OUT.
import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property int passed: 0
    property int failed: 0
    function check(what, ok, detail) {
        if (ok) passed++; else failed++
        console.log("ETEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
    }
    function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
    readonly property string picDir: Quickshell.env("EVENTS_TEST_OUT")
    readonly property string home: Quickshell.env("HOME")
    readonly property string binDir: Quickshell.env("EVENTS_TEST_BIN")
    readonly property var v: launcher.view
    function labels() { return v.results.map(r => r.label) }
    function focusLauncher() { const w = v.Window.window; if (w && !w.active) w.requestActivate() }
    function key(k) { focusLauncher(); ev.keyClick(k, Qt.NoModifier, -1) }
    TestEvent { id: ev }
    Launcher { id: launcher }
    FileView { id: modeFile; path: root.home + "/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark"; printErrors: false }
    function setDark(d) { modeFile.setText(d ? "true\n" : "false\n"); Theme.reload() }
    property int grabbing: 0
    property double holdUntil: 0
    function picture(item, name, dark) {
        if (!picDir) { if (dark !== undefined) setDark(dark); return }
        grabbing++
        item.grabToImage(r => {
            r.saveToFile(picDir + "/" + name + ".png"); console.log("ETEST picture " + name)
            if (dark !== undefined) { setDark(dark); holdUntil = Date.now() + 300 }
            grabbing--
        })
    }

    // canned `quick-event parse` answers, keyed by the line
    property var parseCalls: []
    readonly property var canned: ({
        "Lunch with Sam tomorrow 12-1 at Esso Club": { subject: "Lunch with Sam", start: "2026-11-15T12:00", end: "2026-11-15T13:00", location: "Esso Club",
                                                      human: "Sun Nov 15, 12:00 to 1:00 pm, Esso Club", problems: [] },
        "Lunch tomorrow": { subject: "Lunch", start: null, end: null, location: "", human: "", problems: ["What time?"] },
        "Faculty meeting Fri 2:30pm 90m": { subject: "Faculty meeting", start: "2026-11-20T14:30", end: "2026-11-20T16:00", location: "",
                                           human: "Fri Nov 20, 2:30 to 4:00 pm", problems: [] },
        "Dentist 9am": { subject: "Dentist", start: null, end: null, location: "", human: "", problems: ["Which day?"] }
    })
    function fakeParse(argv) {
        parseCalls = parseCalls.concat([argv])
        if (argv[0].endsWith("/quick-event") && argv[1] === "parse") {
            const r = canned[argv[2]]
            return r ? JSON.stringify(r) : null
        }
        return null
    }

    // the calendar popup, in a window of its own
    FloatingWindow {
        id: calWin
        visible: true
        implicitWidth: 300; implicitHeight: 420
        Rectangle {
            id: calBg
            anchors.fill: parent
            color: Theme.panelBg
            Calendar { id: cal; x: 12; y: 12; width: 276 }
        }
    }
    function addRow() {
        const kids = cal.children
        for (let i = 0; i < kids.length; i++) if (kids[i].objectName === "addEvent") return kids[i]
        return null
    }

    property var cases: [
        { name: "setup", run: function() {
            v.fakeApps = []
            v.fakeWindows = []
            v.fakeRun = () => null
            v.providers = [q => EventQuick.rows(q, v)]
            EventQuick.fake = root.fakeParse
            EventQuick.debounceMs = 60
            setDark(true)
            launcher.open("")
            return 100
        } },
        { name: "provider: plain queries give no row", run: function() {
            const none = ["", "ev", "e", "every day", "eventually", "events", "evening plans", "event"]
            const got = none.map(q => EventQuick.rows(q, v).length)
            check("only 'event' alone gives a hint row", same(got, [0, 0, 0, 0, 0, 0, 0, 1]), JSON.stringify(got))
            check("the hint row does nothing", EventQuick.rows("event", v)[0].run() === undefined && Sys.launched.length === 0)
            check("a query that is not an event never starts the parser", root.parseCalls.length === 0)
            return 50
        } },
        { name: "good line: reading row, then the parsed row", run: function() {
            v.queryText = "event Lunch with Sam tomorrow 12-1 at Esso Club"
            const r0 = v.results[v.results.length - 1]
            check("at once: a reading row that cannot run anything", r0.label === "Add event" && r0.sub === "reading..." && r0.run() === undefined && Sys.launched.length === 0, JSON.stringify(r0))
            return 300
        } },
        { name: "good line: row", run: function() {
            const r = v.results[0]
            check("one row", v.results.length === 1, JSON.stringify(labels()))
            check("label is the summary", r.label === "Add event: Lunch with Sam", r.label)
            check("second line is the time and place", r.sub === "Sun Nov 15, 12:00 to 1:00 pm, Esso Club", r.sub)
            check("two-line row, calendar glyph, no warning", r.two === true && r.glyph === EventQuick.glyph && r.warn === false)
            check("the parser was asked once, for the line without 'event '",
                  same(root.parseCalls, [[Sys.bin + "quick-event", "parse", "Lunch with Sam tomorrow 12-1 at Esso Club"]]), JSON.stringify(root.parseCalls))
            picture(launcher.view.parent, "events-good", false)
            return 100
        } },
        { name: "good line: light picture", run: function() {
            picture(launcher.view.parent, "events-good-light", true)
            return 100
        } },
        { name: "good line: Enter adds it", run: function() {
            Sys.reset()
            key(Qt.Key_Return)
            check("Enter starts quick-event add with the line", same(Sys.launched, [[Sys.bin + "quick-event", "add", "Lunch with Sam tomorrow 12-1 at Esso Club"]]), JSON.stringify(Sys.launched))
            check("and closes the launcher", launcher.visible === false)
            return 100
        } },
        { name: "problem line: shown, Enter does nothing", run: function() {
            launcher.open("")
            v.queryText = "ev Lunch tomorrow"            // the "ev " spelling
            return 300
        } },
        { name: "problem line: row", run: function() {
            const r = v.results[0]
            check("label still names the event", r.label === "Add event: Lunch", r.label)
            check("second line is the problem, flagged as a warning", r.sub === "What time?" && r.warn === true && r.glyph === EventQuick.glyphWarn, JSON.stringify(r))
            picture(launcher.view.parent, "events-problem", true)
            Sys.reset()
            key(Qt.Key_Return)
            check("Enter starts nothing and the launcher stays", Sys.launched.length === 0 && launcher.visible === true, JSON.stringify(Sys.launched))
            return 150
        } },
        { name: "problem with no subject, and a line the parser fails on", run: function() {
            v.queryText = "event Dentist 9am"
            return 250
        } },
        { name: "which day", run: function() {
            check("'Which day?' as the second line", v.results[0].sub === "Which day?" && v.results[0].warn === true, JSON.stringify(v.results[0]))
            v.queryText = "event something the fake does not know"
            return 250
        } },
        { name: "parser failure", run: function() {
            const r = v.results[0]
            check("a failed parse is a problem row, not a hang", r.sub === "Could not read that" && r.warn === true && r.label === "Add event", JSON.stringify(r))
            return 50
        } },
        { name: "typing fast asks once", run: function() {
            root.parseCalls = []
            for (const q of ["event Fa", "event Facu", "event Faculty meeting Fri", "event Faculty meeting Fri 2:30pm 90m"]) v.queryText = q
            return 350
        } },
        { name: "typing fast: result", run: function() {
            check("one parse, for the last text", same(root.parseCalls.map(a => a[2]), ["Faculty meeting Fri 2:30pm 90m"]), JSON.stringify(root.parseCalls))
            check("row for the last text", v.results[0].label === "Add event: Faculty meeting" && v.results[0].sub === "Fri Nov 20, 2:30 to 4:00 pm", JSON.stringify(v.results[0]))
            check("the list is not rebuilt in a loop (parse count stays at one a while later)", root.parseCalls.length === 1)
            v.queryText = "event Lunch tomorrow"
            return 250
        } },
        { name: "an old answer is shown again without a new parse", run: function() {
            root.parseCalls = []
            v.queryText = "event Lunch tomorrow "         // trailing space: same trimmed line
            return 150
        } },
        { name: "same trimmed line", run: function() {
            check("no second parse for the same line", root.parseCalls.length === 0, JSON.stringify(root.parseCalls))
            launcher.visible = false
            return 50
        } },
        { name: "openWith: the query comes prefilled", run: function() {
            EventQuick.fake = null                          // from here the real quick-event runs
            launcher.openWith("event 2026-11-20 ")
            check("launcher open on apps", launcher.visible === true && v.mode === "apps")
            check("query is the text given", v.queryText === "event 2026-11-20 ", JSON.stringify(v.queryText))
            check("and again while open replaces the query", (launcher.openWith("event 2026-11-21 "), v.queryText === "event 2026-11-21 "))
            launcher.openWith("event 2026-11-20 ")
            return 900
        } },
        { name: "real script on the prefilled day", run: function() {
            const r = v.results[0]
            check("only a day: asks what time (the date itself was understood)", r && r.sub === "What time?" && r.warn === true, JSON.stringify(r))
            v.queryText = "event 2026-11-20 Faculty meeting 2:30pm 90m at McAdams 114"
            return 900
        } },
        { name: "real script: good row", run: function() {
            const r = v.results[0]
            check("real parse of a full line", r && r.label === "Add event: Faculty meeting" && r.sub === "Fri Nov 20, 2:30 to 4:00 pm, McAdams 114" && r.warn === false, JSON.stringify(r))
            launcher.visible = false
            return 50
        } },
        { name: "calendar: + Add event", run: function() {
            const row = addRow()
            check("the line exists", row !== null)
            if (!row) return 50
            const today = Qt.formatDate(new Date(), "yyyy-MM-dd")
            check("command for the picked day (today)", cal.addEventCommand() === "qs ipc call launcher openWith 'event " + today + " '", cal.addEventCommand())
            Sys.reset()
            ev.mouseClick(row, row.width / 2, row.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
            check("a click runs it through Sys.run", same(Sys.ran, ["qs ipc call launcher openWith 'event " + today + " '"]), JSON.stringify(Sys.ran))
            cal.picked = new Date(2026, 10, 20)
            check("another picked day: that day's date", cal.addEventCommand() === "qs ipc call launcher openWith 'event 2026-11-20 '", cal.addEventCommand())
            check("quoting survives an apostrophe", cal.shq("a'b") === "'a'\\''b'", cal.shq("a'b"))
            Sys.reset()
            ev.mouseClick(row, 20, 10, Qt.LeftButton, Qt.NoModifier, 0)
            check("click after picking another day", same(Sys.ran, ["qs ipc call launcher openWith 'event 2026-11-20 '"]), JSON.stringify(Sys.ran))
            // the one-line ClockPanel sits under it since 2026-11-14, so "near the bottom" allows for that line
            check("the line sits below the agenda", row.y > cal.height - 110 && row.visible === true, row.y + " of " + cal.height)
            picture(calBg, "events-calendar", false)
            return 100
        } },
        { name: "calendar: other clicks do not add", run: function() {
            Sys.reset()
            ev.mouseClick(calBg, 150, 5, Qt.LeftButton, Qt.NoModifier, 0)
            check("a click elsewhere runs nothing", Sys.ran.length === 0, JSON.stringify(Sys.ran))
            return 50
        } }
    ]

    property int at: 0
    Timer {
        interval: 800; running: true
        onTriggered: {
            if (root.grabbing > 0 || Date.now() < root.holdUntil) { interval = 50; restart(); return }
            if (root.at >= root.cases.length) {
                console.log("ETEST RESULT pass " + root.passed + " fail " + root.failed)
                done.start()
                return
            }
            const c = root.cases[root.at++]
            console.log("ETEST case: " + c.name)
            let wait = 100
            try { wait = c.run() } catch (e) { root.failed++; console.log("ETEST FAIL " + c.name + " threw: " + e + " " + e.stack) }
            interval = Math.max(20, wait || 100)
            restart()
        }
    }
    Timer { id: done; interval: 400; onTriggered: Qt.quit() }
}
