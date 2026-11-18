// Tests for the lecture tools (Lecture.qml, Ink.qml, Lecture*View.qml, LecturePanel.qml).
// NOT part of the shell: ~/.local/bin/lecture-test copies the real files next to this one
// and the stub Sys, then runs it in Quickshell's offscreen mode: no window appears, the
// real cursor never moves, nothing is run (Sys.run only records), no sound plays, and no
// keyboard is read (the key display is fed made-up lines).
//
// A mock slide fills a 1280x800 window; the draw view, the timer, the key display and a
// mock control panel sit on it, driven with synthetic mouse and key events (QtTest's
// TestEvent) and a fast fake clock. Each case logs PASS or FAIL; the last line is
// "LECTURETEST RESULT pass N fail M". With $LECTURE_TEST_OUT set (a path ending .png),
// pictures are saved as <path>-draw.png (ink, timer, keys, panel) and <path>-spot.png.
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
        implicitWidth: 1280; implicitHeight: 800
        color: "black"

        property int passed: 0
        property int failed: 0
        function check(what, ok, detail) {
            if (ok) passed++; else failed++
            console.log("LECTURETEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
        }
        property double fake: 1.8e12             // the fake clock, ms
        function near(a, b) { return Math.abs(a - b) < 0.6 }
        function find(item, pred) {
            if (!item) return null
            if (pred(item)) return item
            const kids = item.children || []
            for (let i = 0; i < kids.length; i++) { const r = find(kids[i], pred); if (r) return r }
            return null
        }
        function byName(item, n) { return find(item, it => it.objectName === n) }
        function chip(t) { return find(draw, it => it.text === t && it.clicked !== undefined) }
        function click(item) { ev.mouseClick(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0) }
        // drag the mouse through pts on the ink (its coordinates), with the given modifiers
        function drag(pts, mods) {
            const m = mods || Qt.NoModifier, ink = draw.ink
            ev.mousePress(ink, pts[0].x, pts[0].y, Qt.LeftButton, m, 0)
            for (let i = 1; i < pts.length; i++) ev.mouseMove(ink, pts[i].x, pts[i].y, 0, Qt.LeftButton, m)
            const l = pts[pts.length - 1]
            ev.mouseRelease(ink, l.x, l.y, Qt.LeftButton, m, 0)
        }
        function wave(x0, y0, w, amp, n) {
            const a = []
            for (let i = 0; i <= n; i++) a.push({ x: x0 + w * i / n, y: y0 + amp * Math.sin(i / n * Math.PI * 3) })
            return a
        }
        function last() { return draw.ink.strokes[draw.ink.count - 1] }
        function endOf(s) { return s.points[s.points.length - 1] }
        function key(k, mods) { ev.keyClick(k, mods || Qt.NoModifier, 0) }

        TestEvent { id: ev }

        Item {
            id: stage
            anchors.fill: parent

            // ---- a mock slide, so the pictures show ink over something ----
            Rectangle {
                anchors.fill: parent
                color: Theme.dark ? "#22252e" : "#e9edf2"
                Column {
                    x: 80; y: 70; spacing: 18
                    Text { text: "Lecture 7: Linked lists"; color: Theme.fg; font { family: Theme.font; pixelSize: 44; bold: true } }
                    Text { text: "Insert at the head in O(1); find is O(n)."; color: Theme.fg; font { family: Theme.font; pixelSize: 26 } }
                    Rectangle {
                        width: 640; height: 230; radius: 10
                        color: Theme.dark ? "#16181f" : "#ffffff"
                        Text {
                            x: 20; y: 16; color: Theme.fg; font { family: Theme.font; pixelSize: 20 }
                            text: "struct node {\n    int value;\n    struct node *next;\n};\n\nhead = push(head, 42);"
                        }
                    }
                }
            }
            LectureDrawView { id: draw; anchors.fill: parent }
            LectureTimerView { id: timerView; anchors { right: parent.right; top: parent.top; rightMargin: 24; topMargin: 150 } }   // below the mock panel
            LectureKeysView { id: keysView; anchors.fill: parent }
            Rectangle {                         // the panel block, as Panel.qml would show it
                id: mockPanel
                x: 880; y: 20; width: 380; height: blk.implicitHeight + 36
                radius: 14; color: Theme.panelBg; border.width: 2; border.color: Theme.accentBg
                LecturePanel { id: blk; x: 18; y: 18; width: parent.width - 36; onUsed: win.panelUsed++ }
            }
            LectureSpotView { id: spotView; anchors.fill: parent; visible: false }
        }
        property int panelUsed: 0
        property var wrap: ({})
        // an object of a given type under a window stub or Variants, by its toString() name
        function find0(o, type) {
            if (!o) return null
            if (String(o).indexOf(type) === 0) return o
            const kids = [].concat(o.data ? Array.from(o.data) : [], o.instances ? Array.from(o.instances) : [], o.children ? Array.from(o.children) : [])
            for (const k of kids) { const r = find0(k, type); if (r) return r }
            return null
        }
        property int flips: 0
        Connections { target: timerView; function onFlashChanged() { win.flips++ } }
        Ink { id: copy; visible: false; interactive: false; anchors.fill: undefined; width: 10; height: 10 }

        property int n0: 0
        property var cases: [
            { name: "every lecture file loads", run: function() {
                for (const f of ["LecturePanel.qml", "Ink.qml"]) {
                    const c = Qt.createComponent(f)
                    check(f + " compiles", c.status === Component.Ready, c.errorString())
                }
                // the windows, with PanelWindow swapped for StubPanel by lecture-test
                for (const f of ["LectureDraw", "LectureSpot", "LectureKeys", "LectureTimer"]) {
                    const c = Qt.createComponent(f + ".qml")
                    const o = c.status === Component.Ready ? c.createObject(win) : null
                    check(f + ".qml loads", o !== null, c.errorString())
                    wrap[f] = o
                }
                const d = wrap.LectureDraw
                check("draw window hidden at first", d && !d.visible)
                Lecture.drawOn = true
                check("draw window opens", d && d.visible)
                check("drawing: the whole window takes input", d && d.mask.item !== null)
                Lecture.hold = true
                check("held: no input region", d && d.mask.item === null)
                Lecture.toggleDraw()
                check("draw toggled while held: drawing again", d && Lecture.drawOn && !Lecture.hold && d.mask.item !== null)
                Lecture.toggleDraw()
                check("draw toggled while drawing: leaves", d && !Lecture.drawOn && !d.visible)
                Lecture.startTimer(1, "")
                check("timer window shows", wrap.LectureTimer && wrap.LectureTimer.visible)
                Lecture.stopTimer()
                check("timer window hides", wrap.LectureTimer && !wrap.LectureTimer.visible)
                Lecture.spotOn = true
                Lecture.keysOn = true
                return 700
            } },
            { name: "spot and keys windows run their scripts", run: function() {
                const sv = wrap.LectureSpot && wrap.LectureSpot.windows.length ? find0(wrap.LectureSpot.windows[0], "LectureSpotView") : null
                check("spot window follows cursor-track", sv !== null && sv.px === 400 && sv.py === 300, sv ? sv.px + "," + sv.py : "no view")
                const kv = find0(wrap.LectureKeys, "LectureKeysView")
                check("key window shows lecture-keys lines", kv !== null && kv.shown() === "Ctrl + C | ok", kv ? kv.shown() : "no view")
                Lecture.allOff()
                return 300
            } },
            { name: "scripts stop with their tool", run: function() {
                check("spot reset when off", wrap.LectureSpot.px < -1000)
                const kv = find0(wrap.LectureKeys, "LectureKeysView")
                check("key pills cleared when off", kv && kv.pills.count === 0)
                Lecture.nowFn = () => win.fake
                Lecture.drawOn = true
                draw.focusKeys()
                return 100
            } },
            { name: "pen", run: function() {
                check("no ink at first", draw.ink.count === 0, draw.ink.count)
                drag(wave(120, 520, 300, 30, 40))
                const s = last()
                check("one pen stroke", draw.ink.count === 1 && s.tool === "pen", JSON.stringify(s && s.tool))
                check("points follow the mouse", s.points.length >= 30, s.points.length)
                check("colour is the accent", Qt.colorEqual(s.ink, Theme.accentBg), s.ink)
                check("weight is the default 4", s.weight === 4, s.weight)
                return 50
            } },
            { name: "marker", run: function() {
                Lecture.tool = "marker"
                drag([{ x: 80, y: 160 }, { x: 300, y: 162 }, { x: 600, y: 160 }])
                check("marker stroke", draw.ink.count === 2 && last().tool === "marker", last().tool)
                return 50
            } },
            { name: "line, Shift snaps to 45 degrees", run: function() {
                Lecture.tool = "line"
                drag([{ x: 100, y: 600 }, { x: 200, y: 615 }, { x: 300, y: 640 }], Qt.ShiftModifier)
                const s = last(), e = endOf(s)
                check("two points", s.points.length === 2, s.points.length)
                check("snapped flat", near(e.y, 600), JSON.stringify(e))
                check("length kept", near(e.x, 100 + Math.hypot(200, 40)), JSON.stringify(e))
                drag([{ x: 100, y: 600 }, { x: 260, y: 740 }], Qt.ShiftModifier)
                const d = endOf(last())
                check("near-diagonal snaps to 45", near(d.x - 100, d.y - 600), JSON.stringify(d))
                return 50
            } },
            { name: "arrow, unconstrained", run: function() {
                Lecture.tool = "arrow"
                drag([{ x: 760, y: 420 }, { x: 700, y: 380 }, { x: 620, y: 330 }])
                const s = last(), e = endOf(s)
                check("arrow ends where the mouse let go", s.tool === "arrow" && e.x === 620 && e.y === 330, JSON.stringify(s))
                return 50
            } },
            { name: "box, Shift makes a square", run: function() {
                Lecture.tool = "box"
                drag([{ x: 900, y: 450 }, { x: 1020, y: 510 }], Qt.ShiftModifier)
                const s = last(), a = s.points[0], e = endOf(s)
                check("square", s.tool === "box" && e.x - a.x === 120 && e.y - a.y === 120, JSON.stringify(s.points))
                drag([{ x: 900, y: 450 }, { x: 880, y: 300 }], Qt.ShiftModifier)
                const b = last(), f = endOf(b)
                check("square keeps the drag's direction", f.x === 750 && f.y === 300, JSON.stringify(f))
                return 50
            } },
            { name: "ellipse, and a click is not a shape", run: function() {
                Lecture.tool = "ellipse"
                drag([{ x: 1050, y: 560 }, { x: 1200, y: 640 }])
                const s = last(), e = endOf(s)
                check("ellipse box as dragged", s.tool === "ellipse" && e.x === 1200 && e.y === 640, JSON.stringify(s.points))
                const n = draw.ink.count
                drag([{ x: 700, y: 700 }, { x: 701, y: 700 }])
                check("a 1 px drag adds no shape", draw.ink.count === n, draw.ink.count)
                return 50
            } },
            { name: "undo, redo, clear", run: function() {
                const ink = draw.ink, n = ink.count
                n0 = n
                ink.undo()
                check("undo removes the last", ink.count === n - 1 && ink.canRedo, ink.count)
                ink.redo()
                check("redo puts it back", ink.count === n && !ink.canRedo, ink.count)
                ink.clear()
                check("clear empties", ink.count === 0)
                ink.undo()
                check("clear can be undone", ink.count === n, ink.count)
                let edits = 0
                const f = () => edits++
                ink.edited.connect(f)
                ink.undo(); ink.redo()
                ink.edited.disconnect(f)
                check("edited() fires on each change", edits === 2, edits)
                return 50
            } },
            { name: "strokes round-trip", run: function() {
                const json = JSON.stringify(draw.ink.strokes)
                copy.strokes = JSON.parse(json)
                check("same strokes after JSON and back", JSON.stringify(copy.strokes) === json)
                check("count follows", copy.count === draw.ink.count, copy.count)
                copy.add({ tool: "box", ink: "#e5484d", weight: 6, points: [{ x: 1, y: 2 }, { x: 3, y: 4 }] })
                check("add() appends a stroke", copy.count === draw.ink.count + 1 && copy.strokes[copy.count - 1].weight === 6)
                copy.undo(); copy.undo()
                check("an outside reassignment is one undo step", copy.count === 0, copy.count)
                return 50
            } },
            { name: "keys: tools, colour, weight, board", run: function() {
                const want = ["pen", "marker", "arrow", "box", "ellipse", "line"]
                for (let i = 0; i < 6; i++) {
                    key(Qt.Key_1 + i)
                    check("key " + (i + 1) + " picks " + want[i], Lecture.tool === want[i], Lecture.tool)
                }
                const c = Lecture.colorIndex
                key(Qt.Key_C)
                check("c: next colour", Lecture.colorIndex === (c + 1) % 5, Lecture.colorIndex)
                for (let i = 0; i < 4; i++) key(Qt.Key_C)
                check("c five times: back to orange", Lecture.colorIndex === c && Qt.colorEqual(Lecture.ink, Theme.accentBg))
                const w = Lecture.weight
                key(Qt.Key_BracketRight)
                check("]: heavier", Lecture.weight > w, Lecture.weight)
                key(Qt.Key_BracketLeft); key(Qt.Key_BracketLeft)
                check("[: lighter", Lecture.weight < w, Lecture.weight)
                key(Qt.Key_BracketRight)
                key(Qt.Key_B)
                check("b: solid board", Lecture.board === 1 && Qt.colorEqual(Lecture.boardColor, Theme.solidBg))
                key(Qt.Key_B)
                check("b: the other theme's board", Lecture.board === 2 && Qt.colorEqual(Lecture.boardColor, Theme.fg))
                check("contrast ink flips on the other board", Qt.colorEqual(Lecture.colors[4], Theme.solidBg))
                key(Qt.Key_B)
                check("b: no board", Lecture.board === 0)
                return 50
            } },
            { name: "keys: undo, redo, clear", run: function() {
                const ink = draw.ink, n = ink.count
                key(Qt.Key_U)
                check("u undoes", ink.count === n - 1, ink.count)
                key(Qt.Key_Z, Qt.ControlModifier)
                check("Ctrl+Z undoes", ink.count === n - 2, ink.count)
                key(Qt.Key_Z, Qt.ControlModifier | Qt.ShiftModifier)
                key(Qt.Key_Z, Qt.ControlModifier | Qt.ShiftModifier)
                check("Ctrl+Shift+Z redoes", ink.count === n, ink.count)
                key(Qt.Key_X)
                check("x clears", ink.count === 0)
                key(Qt.Key_U)
                check("u after x brings it back", ink.count === n, ink.count)
                return 50
            } },
            { name: "Tab holds: ink stays, mouse passes", run: function() {
                const n = draw.ink.count
                key(Qt.Key_Tab)
                check("Tab: hold", Lecture.hold && Lecture.drawOn)
                check("ink stops taking the mouse", !draw.ink.interactive)
                Lecture.tool = "pen"
                drag(wave(200, 700, 200, 10, 10))
                check("no stroke while held", draw.ink.count === n, draw.ink.count)
                check("toolbar hidden, badge shown", !byName(draw, "toolbar").visible && byName(draw, "holdBadge").visible)
                check("ink survives the hold", draw.ink.count === n)
                Lecture.toggleDraw()
                check("draw again after hold: drawing, not left", Lecture.drawOn && !Lecture.hold && draw.ink.interactive)
                draw.focusKeys()
                return 50
            } },
            { name: "Esc leaves and clears", run: function() {
                const n = draw.ink.count
                key(Qt.Key_Escape)
                check("Esc: draw off", !Lecture.drawOn && !Lecture.hold)
                check("ink cleared", draw.ink.count === 0)
                Lecture.toggleDraw()
                draw.focusKeys()
                key(Qt.Key_U)
                check("u on coming back restores the last ink", draw.ink.count === n, draw.ink.count)
                return 50
            } },
            { name: "toolbar is clickable", run: function() {
                const c = chip("4 box")
                check("chip found", c !== null)
                if (c) { click(c); check("click picks box", Lecture.tool === "box", Lecture.tool) }
                const sw = byName(draw, "swatch"), ci = Lecture.colorIndex
                click(sw)
                check("swatch click: next colour", Lecture.colorIndex === (ci + 1) % 5)
                Lecture.colorIndex = ci
                return 50
            } },
            { name: "timer counts down", run: function() {
                check("no tick while no timer", !timerView.ticking)
                timerView.tickMs = 20
                Lecture.startTimer(2, "Quiz")
                check("shows 02:00", byName(timerView, "clock").text === "02:00", byName(timerView, "clock").text)
                check("ticks while running", timerView.ticking)
                fake += 61000
                return 80
            } },
            { name: "timer: last minute", run: function() {
                const t = byName(timerView, "clock")
                check("00:59 after 61 s", t.text === "00:59", t.text)
                check("warn colour in the last minute", timerView.lastMinute && Qt.colorEqual(t.color, Theme.warn), t.color)
                check("no sound yet", Sys.sounds.length === 0)
                fake += 59000
                return 120
            } },
            { name: "timer: zero", run: function() {
                check("done at zero", timerView.done, timerView.remain)
                check("the complete sound, once", JSON.stringify(Sys.sounds) === JSON.stringify(["complete"]), JSON.stringify(Sys.sounds))
                check("still shown after zero", Lecture.timerEnd > 0)
                win.flashSeen = win.flips
                return 80
            } },
            { name: "timer: flashes, then goes", run: function() {
                check("flashes", win.flips > win.flashSeen, win.flips)
                check("sound not repeated", Sys.sounds.length === 1, Sys.sounds.length)
                fake += 20500
                return 80
            } },
            { name: "timer: gone after 20 s", run: function() {
                check("timer cleared", Lecture.timerEnd === 0)
                check("stops ticking", !timerView.ticking)
                check("clock()", Lecture.clock(3725) === "1:02:05" && Lecture.clock(59.2) === "01:00" && Lecture.clock(0) === "00:00",
                      Lecture.clock(3725) + " " + Lecture.clock(59.2))
                Lecture.startTimer(0, "")
                check("timer 0 stops", Lecture.timerEnd === 0)
                return 50
            } },
            { name: "key display lines", run: function() {
                const p = Lecture.parseKeyLine("Super+Shift\tD")
                check("parse a chord", p && JSON.stringify(p.mods) === '["Super","Shift"]' && p.key === "D", JSON.stringify(p))
                check("parse plain typing", JSON.stringify(Lecture.parseKeyLine("\ta")) === '{"mods":[],"key":"a"}')
                check("reject junk", Lecture.parseKeyLine("junk") === null && Lecture.parseKeyLine("Ctrl\t") === null)
                keysView.reset()
                for (const l of ["\th", "\ti", "\tSpace", "\tA", "Ctrl\tC", "Ctrl\tZ", "Ctrl\tZ", "Ctrl\tZ", "Super+Shift\tD", "\tEnter"])
                    keysView.push(l)
                check("typing gathers, chords count up", keysView.shown() === "hi A | Ctrl + C | Ctrl + Z ×3 | Super + Shift + D | Enter", keysView.shown())
                for (const l of ["\tx", "Alt\tTab", "\ty", "Ctrl\tS"]) keysView.push(l)
                check("at most 5 pills", keysView.pills.count === 5, keysView.shown())
                fake += 2600
                keysView.expire()
                check("gone after 2.5 s", keysView.pills.count === 0, keysView.shown())
                for (let i = 0; i < 40; i++) keysView.push("\t" + String.fromCharCode(97 + i % 26))
                check("long typing keeps the newest characters", keysView.pills.count === 1 && keysView.shown().length === 24 && keysView.shown().endsWith("n"), keysView.shown())
                keysView.push("#nokbd")
                check("no keyboard: says so", keysView.problem !== "")
                keysView.reset()
                return 50
            } },
            { name: "spotlight geometry", run: function() {
                Lecture.setSpotSize(150)
                spotView.px = 400; spotView.py = 300
                const hole = byName(spotView, "hole")
                check("pointer on this screen", spotView.here)
                check("clear inside the radius", spotView.holeRadius === 150 && spotView.radius === 150)
                check("hole square centred on the pointer", hole.x + hole.width / 2 === 400 && hole.y + hole.height / 2 === 300, hole.x + "," + hole.y + " " + hole.width)
                check("hole square holds the soft edge", hole.width / 2 >= 150 + spotView.feather, hole.width)
                // the four dim rectangles and the square tile the screen exactly (on-screen parts)
                const clip = r => Math.max(0, Math.min(r.x + r.width, 1280) - Math.max(r.x, 0)) * Math.max(0, Math.min(r.y + r.height, 800) - Math.max(r.y, 0))
                const tiled = () => Array.from(hole.parent.children).reduce((a, r) => a + clip(r), 0)
                check("dim tiles the screen, no overlap", tiled() === 1280 * 800, tiled() + " vs " + 1280 * 800)
                spotView.px = 30; spotView.py = 20
                check("near a corner too", tiled() === 1280 * 800, tiled())
                spotView.px = 1279.6; spotView.py = 799.2
                check("and at the far corner", tiled() === 1280 * 800, tiled())
                spotView.px = -50
                check("pointer elsewhere: whole screen dimmed", !spotView.here)
                Lecture.setSpotSize(5); const lo = Lecture.spotRadius
                Lecture.setSpotSize(5000)
                check("radius kept between 40 and 800", lo === 40 && Lecture.spotRadius === 800, lo + " " + Lecture.spotRadius)
                Lecture.setSpotSize(150)
                return 50
            } },
            { name: "zoom", run: function() {
                Sys.ran = []
                Lecture.zoom(1)
                check("zoom in: 1.5", Lecture.zoomFactor === 1.5 && Sys.ran.length === 1
                      && Sys.ran[0] === "hyprctl eval 'hl.config({ cursor = { zoom_factor = 1.5 } })' >/dev/null", JSON.stringify(Sys.ran))
                for (let i = 0; i < 6; i++) Lecture.zoom(1)
                check("stops at 4", Lecture.zoomFactor === 4 && Sys.ran.length === 4, Sys.ran.length)
                Lecture.zoom(-1)
                check("zoom out: 3", Lecture.zoomFactor === 3)
                Lecture.zoomReset()
                check("reset: 1", Lecture.zoomFactor === 1 && Sys.ran[Sys.ran.length - 1].indexOf("zoom_factor = 1 ") > 0, Sys.ran[Sys.ran.length - 1])
                return 50
            } },
            { name: "panel block", run: function() {
                const spot = find(blk, it => it.label === "Spot")
                click(spot)
                check("Spot button turns it on", Lecture.spotOn)
                check("and lights up", Qt.colorEqual(spot.color, Theme.accentBg))
                check("Spot keeps the panel open", panelUsed === 0, panelUsed)
                click(find(blk, it => it.label === "Off"))
                check("Off button: everything off", !Lecture.spotOn && !Lecture.drawOn)
                Lecture.drawOn = true
                return 50
            } },
            { name: "allOff and status", run: function() {
                Lecture.drawOn = true; Lecture.hold = true; Lecture.spotOn = true; Lecture.keysOn = true
                Lecture.startTimer(5, "Break"); Lecture.zoom(1)
                check("status line", Lecture.status().indexOf("draw=hold") === 0 && Lecture.status().indexOf("label=Break") > 0
                      && Lecture.status().indexOf("zoom=1.5") > 0 && Lecture.status().indexOf("timer=05:00") > 0, Lecture.status())
                Sys.ran = []
                Lecture.allOff()
                check("all off", !Lecture.drawOn && !Lecture.hold && !Lecture.spotOn && !Lecture.keysOn && Lecture.timerEnd === 0 && Lecture.zoomFactor === 1 && !Lecture.anyOn)
                check("zoom put back", Sys.ran.length === 1, JSON.stringify(Sys.ran))
                return 50
            } },
            { name: "presenting ends: all off", run: function() {
                Lecture.spotOn = true
                return 400
            } },
            { name: "presenting seen", run: function() {
                check("presenting file seen", Lecture.presenting, Lecture.status())
                Quickshell.execDetached(["rm", "-f", Quickshell.env("XDG_RUNTIME_DIR") + "/presenting"])
                return 3600
            } },
            { name: "presenting gone", run: function() {
                check("file gone: every tool off", !Lecture.spotOn && !Lecture.presenting, Lecture.status())
                return 50
            } },
            { name: "picture", run: function() {
                // a lecture moment: ink, the key display and a timer, over the slide
                Lecture.drawOn = true
                draw.ink.strokes = []
                Lecture.weightIndex = 3
                Lecture.colorIndex = 0; Lecture.tool = "marker"
                drag([{ x: 80, y: 170 }, { x: 400, y: 171 }, { x: 690, y: 170 }])
                Lecture.colorIndex = 4; Lecture.tool = "pen"
                drag(wave(84, 128, 520, 5, 60))
                Lecture.colorIndex = 2; Lecture.tool = "box"
                drag([{ x: 92, y: 288 }, { x: 420, y: 330 }])
                Lecture.colorIndex = 3; Lecture.tool = "arrow"
                drag([{ x: 860, y: 420 }, { x: 760, y: 360 }, { x: 440, y: 310 }])
                Lecture.colorIndex = 1; Lecture.tool = "ellipse"
                drag([{ x: 90, y: 390 }, { x: 400, y: 450 }])
                Lecture.colorIndex = 0; Lecture.tool = "line"
                drag([{ x: 880, y: 520 }, { x: 1180, y: 525 }], Qt.ShiftModifier)
                Lecture.tool = "arrow"
                timerView.tickMs = 1000
                Lecture.startTimer(10, "Quiz")
                fake += 138000
                timerView.tick()
                for (const l of ["Ctrl\tC", "\tp", "\tu", "\ts", "\th", "Super+Shift\tD"]) keysView.push(l)
                return 300
            } }
        ]
        property int flashSeen: 0

        property int at: 0
        Timer {
            interval: 500; running: true
            onTriggered: {
                if (win.at >= win.cases.length) {
                    console.log("LECTURETEST RESULT pass " + win.passed + " fail " + win.failed)
                    const out = Quickshell.env("LECTURE_TEST_OUT")
                    if (!out) { Qt.quit(); return }
                    const base = out.replace(/\.png$/, "")
                    stage.grabToImage(function(res) {
                        res.saveToFile(base + "-draw.png")
                        spotView.visible = true
                        spotView.px = 260; spotView.py = 330
                        mockPanel.visible = false
                        stage.grabToImage(function(res2) { res2.saveToFile(base + "-spot.png"); Qt.quit() })
                    })
                    giveUp.start()
                    return
                }
                const c = win.cases[win.at++]
                console.log("LECTURETEST case: " + c.name)
                let wait = 100
                try { wait = c.run() } catch (e) { win.failed++; console.log("LECTURETEST FAIL " + c.name + " threw: " + e + " " + (e.stack || "")) }
                interval = Math.max(20, wait || 100)
                restart()
            }
        }
        Timer { id: giveUp; interval: 4000; onTriggered: Qt.quit() }
    }
}
