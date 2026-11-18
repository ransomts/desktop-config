// Pointer tests for the wallpaper's agenda band (WallAgenda.qml). NOT part of the shell:
// ~/.local/bin/agenda-test copies the real WallAgenda.qml and Theme.qml next to this file
// and the stub Sys, then runs it in Quickshell's offscreen mode: no window, the real cursor
// never moves, and nothing is launched (Sys.launch only records the argv).
//
// A made-up day is laid out on a band the size of a 1920 px screen's (1892 px wide) and
// driven with synthetic mouse events (QtTest's TestEvent). Each case logs PASS or FAIL;
// the last line is "AGENDATEST RESULT pass N fail M". A picture is saved to $AGENDA_TEST_OUT.
//
// Adding a case: append { name, run } to `cases`; `run` does its events and checks and
// returns how many milliseconds to wait before the next case.
import QtQuick
import QtTest
import Quickshell

ShellRoot {
    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 1920; implicitHeight: 160
        color: "#16161a"

        property int passed: 0
        property int failed: 0
        function check(what, ok, detail) {
            if (ok) passed++; else failed++
            console.log("AGENDATEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
        }
        // the band's event delegates, found by title
        function evOf(title) {
            const kids = band.children
            for (let i = 0; i < kids.length; i++)
                if (kids[i].modelData && kids[i].modelData.title === title) return kids[i]
            return null
        }
        function tipOf(e) {
            const kids = e.children
            for (let i = 0; i < kids.length; i++) if (kids[i].objectName === "tip") return kids[i]
            return null
        }
        // click at (x, y) in the event's own coordinates; returns what was launched
        function click(e, x, y, button) {
            Sys.launched = []
            ev.mouseClick(e, x, y, button, Qt.NoModifier, 0)
            return Sys.launched
        }
        function clickBand(x, y, button) {          // same, in band coordinates
            Sys.launched = []
            ev.mouseClick(band, x, y, button, Qt.NoModifier, 0)
            return Sys.launched
        }
        function away() { ev.mouseMove(win.contentItem, 5, 5, 0, Qt.NoButton, Qt.NoModifier) }
        function openArgs(d, start, title, id) { return JSON.stringify(["/bin-test/agenda-open", d, start, title, id]) }

        TestEvent { id: ev }

        readonly property string day: "2026-11-13"
        readonly property string zoom: "https://clemson.zoom.us/j/123?pwd=abc"
        readonly property string longEarly: "Early lab, with a title long enough that a centred tip would run off the left edge"
        readonly property string longLate: "Late review, with a title long enough that a centred tip would run off the right edge"
        Component.onCompleted: Sys.today = [
            { start: "", end: "", title: "All day thing", allday: true, location: "", url: "", date: day, id: "" },
            { start: "08:00", end: "08:50", title: longEarly, allday: false, location: "McAdams 107", url: "", date: day, id: "ID-EARLY" },
            { start: "09:05", end: "09:55", title: "Class A", allday: false, location: "McAdams 107", url: "", date: day, id: "ID-A" },
            { start: "09:30", end: "11:00", title: "Group meeting", allday: false, location: "Zoom: " + zoom, url: zoom, date: day, id: "ID-G" },
            { start: "11:00", end: "11:30", title: "Back to back 1", allday: false, location: "", url: "", date: day, id: "" },
            { start: "11:30", end: "12:00", title: "Back to back 2", allday: false, location: "", url: "", date: day, id: "" },
            { start: "13:00", end: "13:01", title: "Sliver", allday: false, location: "", url: "", date: day, id: "" },
            { start: "13:02", end: "13:30", title: "After sliver", allday: false, location: "", url: "", date: day, id: "" },
            { start: "17:00", end: "18:00", title: longLate, allday: false, location: "Online", url: "https://teams.microsoft.com/l/x", date: day, id: "ID-LATE" }
        ]

        Item {
            id: stage
            anchors.fill: parent
            Rectangle { anchors.fill: parent; z: -10; color: win.color }
            WallAgenda {
                id: band
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
            }
        }

        property var cases: [
            { name: "lanes", run: function() {
                const want = { "Class A": 0, "Group meeting": 1, "Back to back 1": 0, "Back to back 2": 0, "Sliver": 0, "After sliver": 1 }
                for (const t in want) {
                    const e = evOf(t)
                    check("lane of " + t, e && e.lane === want[t], e ? "lane " + e.lane : "missing")
                }
                check("all-day events are not drawn", evOf("All day thing") === null)
                check("band grows one lane", band.implicitHeight === 36, band.implicitHeight)
                return 50
            } },
            { name: "lanes tile with no dead gap", run: function() {
                const a = evOf("Class A"), g = evOf("Group meeting")
                const aTop = a.mapToItem(band, 0, 0).y, gBottom = g.mapToItem(band, 0, g.height).y
                check("lane 1 ends where lane 0 starts", Math.abs(gBottom - aTop) < 0.5, "lane1 bottom " + gBottom + ", lane0 top " + aTop)
                check("hit area is a whole lane tall", a.height === 10 && g.height === 10, a.height + "/" + g.height)
                // where they overlap in time: 09:40, on the last pixel row of each lane (TestEvent rounds to whole pixels)
                const x = band.xOf(band.mins("09:40"))
                check("top pixel of lane 0 is Class A", JSON.stringify(clickBand(x, aTop, Qt.RightButton)[0]) === openArgs(day, "09:05", "Class A", "ID-A"),
                      JSON.stringify(Sys.launched))
                check("bottom pixel of lane 1 is Group meeting", JSON.stringify(clickBand(x, gBottom - 1, Qt.RightButton)[0]) === openArgs(day, "09:30", "Group meeting", "ID-G"),
                      JSON.stringify(Sys.launched))
                return 50
            } },
            { name: "gap between neighbours belongs to one of them", run: function() {
                const b2 = evOf("Back to back 2")
                const got = clickBand(b2.x + 0.5, b2.mapToItem(band, 0, 5).y, Qt.RightButton)
                check("1 px left of the block still hits it", got.length === 1 && got[0][3] === "Back to back 2", JSON.stringify(got))
                return 50
            } },
            { name: "left-click with a link joins", run: function() {
                const got = click(evOf("Group meeting"), 20, 5, Qt.LeftButton)
                check("xdg-open the link", JSON.stringify(got) === JSON.stringify([["xdg-open", zoom]]), JSON.stringify(got))
                return 50
            } },
            { name: "left-click without a link opens the entry", run: function() {
                const got = click(evOf("Class A"), 20, 5, Qt.LeftButton)
                check("agenda-open with date, start, title, id", got.length === 1 && JSON.stringify(got[0]) === openArgs(day, "09:05", "Class A", "ID-A"), JSON.stringify(got))
                const b1 = click(evOf("Back to back 1"), 10, 5, Qt.LeftButton)
                check("no id: agenda-open gets an empty id (it falls back to the title)", b1.length === 1 && JSON.stringify(b1[0]) === openArgs(day, "11:00", "Back to back 1", ""), JSON.stringify(b1))
                return 50
            } },
            { name: "right-click always opens the entry", run: function() {
                const got = click(evOf("Group meeting"), 20, 5, Qt.RightButton)
                check("right-click on a linked event", got.length === 1 && JSON.stringify(got[0]) === openArgs(day, "09:30", "Group meeting", "ID-G"), JSON.stringify(got))
                return 50
            } },
            { name: "hover shows the tip", run: function() {
                const g = evOf("Group meeting")
                ev.mouseMove(g, 20, 5, 0, Qt.NoButton, Qt.NoModifier)
                return 100
            } },
            { name: "tip text", run: function() {
                const g = evOf("Group meeting"), t = tipOf(g)
                check("visible while hovered", t && t.visible)
                check("place without the URL, and the join mark", g.tipText === "09:30–11:00  Group meeting  · Zoom  ↗ join", g.tipText)
                check("hovered event is lifted", g.z > 0, g.z)
                away()
                return 100
            } },
            { name: "tip hides", run: function() {
                check("hidden after the pointer leaves", !tipOf(evOf("Group meeting")).visible)
                ev.mouseMove(evOf(longEarly), 3, 5, 0, Qt.NoButton, Qt.NoModifier)
                return 100
            } },
            { name: "tip stays on screen at the left edge", run: function() {
                const t = tipOf(evOf(longEarly)), l = t.mapToItem(band, 0, 0).x
                check("left edge inside the band", t.visible && l >= -0.5, "x " + l)
                ev.mouseMove(evOf(longLate), 3, 5, 0, Qt.NoButton, Qt.NoModifier)
                return 100
            } },
            { name: "tip stays on screen at the right edge", run: function() {
                const t = tipOf(evOf(longLate)), r = t.mapToItem(band, t.width, 0).x
                check("right edge inside the band", t.visible && r <= band.width + 0.5, "right " + r + " of " + band.width)
                return 100
            } }
        ]

        property int at: 0
        Timer {
            interval: 500; running: true            // let the band lay out first
            onTriggered: {
                if (win.at >= win.cases.length) {
                    console.log("AGENDATEST RESULT pass " + win.passed + " fail " + win.failed)
                    const out = Quickshell.env("AGENDA_TEST_OUT")
                    if (!out) { Qt.quit(); return }
                    stage.grabToImage(function(res) { res.saveToFile(out); Qt.quit() })
                    giveUp.start()
                    return
                }
                const c = win.cases[win.at++]
                console.log("AGENDATEST case: " + c.name)
                let wait = 100
                try { wait = c.run() } catch (e) { win.failed++; console.log("AGENDATEST FAIL " + c.name + " threw: " + e) }
                interval = Math.max(20, wait || 100)
                restart()
            }
        }
        Timer { id: giveUp; interval: 3000; onTriggered: Qt.quit() }
    }
}
