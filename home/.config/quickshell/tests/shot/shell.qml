// Tests for the screenshot editor (ShotEditor/ShotSelect/ShotMarks, shot.js) and the share
// picker's card (SharePickView). NOT part of the shell: ~/.local/bin/shot-test copies the real
// files next to this one, with the stub Sys and a stand-in Ink.qml (the interface in the round's
// RULES.md), and runs it offscreen: no window appears, the real cursor never moves, nothing runs.
//
// The editor's frame is a test picture (SHOT_TEST_FRAME, 2x the window: 2560x1600) instead of a
// ScreencopyView, which cannot capture offscreen. Each case logs PASS or FAIL; the last line is
// "SHOTTEST RESULT pass N fail M". Pictures go to $SHOT_TEST_OUT (a prefix).
import QtQuick
import QtTest
import Quickshell
import "shot.js" as S

ShellRoot {
    id: root
    property int passed: 0
    property int failed: 0
    function check(what, ok, detail) {
        if (ok) passed++; else failed++
        console.log("SHOTTEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
    }
    readonly property string out: Quickshell.env("SHOT_TEST_OUT")
    readonly property string tmp: Quickshell.env("SHOT_TEST_TMP")
    function near(a, b) { return Math.abs(a - b) < 1.01 }
    function boxIs(x, y, w, h) { const b = ed.box; return near(b.sx, x) && near(b.sy, y) && near(b.sw, w) && near(b.sh, h) }
    function boxStr() { const b = ed.box; return [b.sx, b.sy, b.sw, b.sh].map(Math.round).join(",") }
    function drag(item, x0, y0, x1, y1) {
        ev.mousePress(item, x0, y0, Qt.LeftButton, Qt.NoModifier, 0)
        for (let i = 1; i <= 6; i++) ev.mouseMove(item, x0 + (x1 - x0) * i / 6, y0 + (y1 - y0) * i / 6, 0, Qt.LeftButton, Qt.NoModifier)
        ev.mouseRelease(item, x1, y1, Qt.LeftButton, Qt.NoModifier, 0)
    }
    property var finishes: []
    property int claims: 0

    TestEvent { id: ev }

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 1280; implicitHeight: 800
        color: "black"
        Item {
            id: stage
            anchors.fill: parent
            ShotEditor {
                id: ed
                anchors.fill: parent
                onRequestFinish: how => root.finishes = root.finishes.concat([how])
                onClaimed: root.claims++
                Image {
                    id: frameImg
                    anchors.fill: parent
                    source: "file://" + Quickshell.env("SHOT_TEST_FRAME")
                    smooth: true
                }
            }
        }
    }
    FloatingWindow {
        id: win2
        visible: false          // shown for the share cases (a second window would take the keys)
        implicitWidth: 1000; implicitHeight: 660
        color: Theme.solidBg
        Item {
          id: stage2
          anchors.fill: parent
          Rectangle { anchors.fill: parent; color: Theme.solidBg }
          SharePickView {
            id: sp
            anchors { fill: parent; margins: 20 }
            live: false
            screens: []
            onChosen: line => root.chosen = root.chosen.concat([line])
            onCancelled: root.chosen = root.chosen.concat(["cancel"])
          }
        }
    }
    property var chosen: []
    readonly property var lists: ({
        allowToken: false,
        outputs: [ { name: "eDP-1", x: 0, y: 0, w: 1440, h: 900 }, { name: "DP-9", x: 1440, y: -500, w: 1080, h: 1920 } ],
        windows: [ { id: 2216345678, cls: "firefox", title: "Mozilla Firefox", address: "0x563b382f3c40" },
                   { id: 77, cls: "com.mitchellh.ghostty", title: "~/Scratch", address: "" },
                   { id: 78, cls: "org.gnome.Nautilus", title: "Files", address: "0x5600" } ],
        workspaces: []
    })
    Image { id: probe; visible: false; cache: false }

    property var cases: [
        { name: "shot.js helpers", run: function() {
            const tl = [
                { title: "tiled", workspace: { active: true }, monitor: { name: "eDP-1" }, lastIpcObject: { at: [10, 40], size: [700, 800], floating: false } },
                { title: "float", workspace: { active: true }, monitor: { name: "eDP-1" }, lastIpcObject: { at: [100, 100], size: [900, 600], floating: true } },
                { title: "hidden ws", workspace: { active: false }, monitor: { name: "eDP-1" }, lastIpcObject: { at: [0, 0], size: [50, 50] } },
                { title: "other screen", workspace: { active: true }, monitor: { name: "DP-9" }, lastIpcObject: { at: [1500, 0], size: [500, 500] } }
            ]
            const r = S.windowRects(tl, "DP-9", 1440, -500)
            check("windowRects keeps the screen's visible windows", r.length === 1 && r[0].title === "other screen", JSON.stringify(r))
            check("windowRects is in screen coordinates", r[0].x === 60 && r[0].y === 500, JSON.stringify(r[0]))
            const e = S.windowRects(tl, "eDP-1", 0, 0)
            check("windowAt prefers the floating window", S.windowAt(e, 300, 300).title === "float")
            check("windowAt falls back to the tiled one", S.windowAt(e, 20, 700).title === "tiled")
            check("windowAt: nothing there", S.windowAt(e, 1300, 10) === null)
            check("stamp like date +%Y-%m-%d_%H-%M-%S", S.stamp(new Date(2026, 0, 5, 7, 8, 9)) === "2026-01-05_07-08-09", S.stamp(new Date(2026, 0, 5, 7, 8, 9)))
            return 50
        } },
        { name: "reply lines (xdph 1.5.0 grammar)", run: function() {
            check("screen", S.replyFor({ type: "screen", output: "eDP-1" }, false) === "[SELECTION]/screen:eDP-1")
            check("screen, restore token", S.replyFor({ type: "screen", output: "DP-9" }, true) === "[SELECTION]r/screen:DP-9")
            check("window handle", S.replyFor({ type: "window", id: 2216345678 }, false) === "[SELECTION]/window:2216345678")
            check("region", S.replyFor({ type: "region", output: "DP-9", x: 10.4, y: 20.6, w: 300, h: 199.5 }, true) === "[SELECTION]r/region:DP-9@10,21,300,200",
                  S.replyFor({ type: "region", output: "DP-9", x: 10.4, y: 20.6, w: 300, h: 199.5 }, true))
            check("workspace", S.replyFor({ type: "workspace", id: 3 }, false) === "[SELECTION]/workspace-id:3")
            check("nothing", S.replyFor(null, true) === "" && S.replyFor({ type: "region", output: "x", x: 0, y: 0, w: 0, h: 5 }, false) === "")
            return 50
        } },
        { name: "drag a box", run: function() {
            check("starts in select", ed.phase === "select" && !ed.box.has)
            drag(ed, 100, 120, 500, 420)
            check("box from the drag", boxIs(100, 120, 400, 300), boxStr())
            check("released: annotate", ed.phase === "annotate")
            check("the screen was claimed", root.claims === 1, root.claims)
            return 80
        } },
        { name: "handles adjust", run: function() {
            drag(ed, 500, 420, 560, 450)          // the bottom-right handle
            check("bottom-right handle", boxIs(100, 120, 460, 330), boxStr())
            drag(ed, 100, 285, 80, 285)           // the left-middle handle
            check("left handle", boxIs(80, 120, 480, 330), boxStr())
            return 50
        } },
        { name: "right-click goes back", run: function() {
            ev.mouseClick(ed, 300, 300, Qt.RightButton, Qt.NoModifier, 0)
            check("select again, no box", ed.phase === "select" && !ed.box.has, ed.phase + " " + boxStr())
            return 50
        } },
        { name: "double-click with no box = whole screen", run: function() {
            ev.mouseDoubleClickSequence(ed, 640, 400, Qt.LeftButton, Qt.NoModifier, 0)
            check("whole screen", boxIs(0, 0, 1280, 800), boxStr())
            check("annotate", ed.phase === "annotate")
            ed.backToSelect()
            check("Enter with no box = whole screen", ed.handleKey(Qt.Key_Return, 0) && boxIs(0, 0, 1280, 800) && ed.phase === "annotate", boxStr())
            ed.backToSelect()
            return 50
        } },
        { name: "w snaps to the window under the pointer", run: function() {
            ed.windows = [ { x: 40, y: 60, w: 700, h: 500, title: "tiled", floating: false }, { x: 300, y: 200, w: 400, h: 250, title: "float", floating: true } ]
            ev.mouseMove(ed, 100, 100, 0, Qt.NoButton, Qt.NoModifier)
            ed.handleKey(Qt.Key_W, 0)
            check("tiled window", boxIs(40, 60, 700, 500), boxStr())
            ed.backToSelect()
            ev.mouseMove(ed, 350, 300, 0, Qt.NoButton, Qt.NoModifier)
            ed.handleKey(Qt.Key_W, 0)
            check("the floating one over it", boxIs(300, 200, 400, 250), boxStr())
            ed.backToSelect()
            ev.mouseMove(ed, 1200, 780, 0, Qt.NoButton, Qt.NoModifier)
            check("no window: nothing", !ed.handleKey(Qt.Key_W, 0) || !ed.box.has)
            return 50
        } },
        { name: "annotate: arrow (Ink)", run: function() {
            drag(ed, 200, 150, 1000, 650)
            ed.tool = "arrow"
            drag(ed, 300, 500, 520, 330)
            check("one stroke", ed.marks.ink2.count === 1, ed.marks.ink2.count)
            const s = ed.marks.ink2.strokes[0]
            check("stroke is an arrow in frame coordinates", s && s.tool === "arrow" && near(s.points[0].x, 300) && near(s.points[0].y, 500), JSON.stringify(s && s.points[0]))
            ed.tool = "box"
            ed.ink = Theme.red
            drag(ed, 560, 220, 760, 300)
            check("history ink, ink", JSON.stringify(ed.marks.history) === '["ink","ink"]', JSON.stringify(ed.marks.history))
            ed.tool = "pen"
            drag(ed, 100, 100, 150, 120)          // outside the box: ignored
            check("outside the box draws nothing", ed.marks.ink2.count === 2, ed.marks.ink2.count)
            return 50
        } },
        { name: "annotate: steps", run: function() {
            ed.tool = "step"
            ed.ink = Theme.accentBg
            ev.mouseClick(ed, 260, 200, Qt.LeftButton, Qt.NoModifier, 0)
            ev.mouseClick(ed, 820, 260, Qt.LeftButton, Qt.NoModifier, 0)
            const st = ed.marks.steps
            check("two badges numbered 1, 2", st.length === 2 && st[0].n === 1 && st[1].n === 2, JSON.stringify(st))
            return 50
        } },
        { name: "annotate: text", run: function() {
            ed.tool = "text"
            ed.ink = Theme.ok
            ev.mouseClick(ed, 600, 560, Qt.LeftButton, Qt.NoModifier, 0)
            check("label entry open", ed.marks.editing)
            for (const k of [Qt.Key_S, Qt.Key_A, Qt.Key_V, Qt.Key_E]) ev.keyClick(k, Qt.NoModifier, 0)
            ev.keyClick(Qt.Key_Return, Qt.NoModifier, 0)
            const t = ed.marks.texts
            check("typed and Enter: a label", t.length === 1 && t[0].text.toLowerCase() === "save", JSON.stringify(t))
            check("Enter in the label did not finish the shot", root.finishes.length === 0, JSON.stringify(root.finishes))
            return 50
        } },
        { name: "annotate: pixelate", run: function() {
            ed.tool = "pixel"
            drag(ed, 640, 380, 960, 470)
            const p = ed.marks.pixels
            check("one pixelate box", p.length === 1 && near(p[0].x, 640) && near(p[0].w, 320), JSON.stringify(p))
            check("history in order", JSON.stringify(ed.marks.history) === '["ink","ink","step","step","text","pixel"]', JSON.stringify(ed.marks.history))
            ed.tool = "ellipse"
            ed.ink = Theme.alt
            drag(ed, 860, 520, 980, 630)
            return 50
        } },
        { name: "picture: annotate phase, dark", run: function() {
            Theme.dark = true
            ev.mouseMove(ed, 0, 0, 0, Qt.NoButton, Qt.NoModifier)
            if (root.out) stage.grabToImage(r => r.saveToFile(root.out + "-annotate-dark.png"))
            return 300
        } },
        { name: "picture: annotate phase, light", run: function() {
            Theme.dark = false
            if (root.out) stage.grabToImage(r => r.saveToFile(root.out + "-annotate-light.png"))
            return 300
        } },
        { name: "export at scale 1", run: function() {
            Theme.dark = true
            ed.frameScale = 1
            check("output size is the box", ed.outWidth === 800 && ed.outHeight === 500, ed.outWidth + "x" + ed.outHeight)
            ed.exportTo(root.tmp + "/out1.png", ok => { root.exp1 = ok })
            return 400
        } },
        { name: "scale 1 file", run: function() {
            check("saved", root.exp1 === true, root.exp1)
            probe.source = "file://" + root.tmp + "/out1.png"
            return 200
        } },
        { name: "scale 1 size", run: function() {
            check("PNG is 800x500", probe.implicitWidth === 800 && probe.implicitHeight === 500, probe.implicitWidth + "x" + probe.implicitHeight)
            check("toolbar back after the render", ed.toolbar.visible && !ed.rendering)
            ed.frameScale = 2
            ed.exportTo(root.tmp + "/out2.png", ok => { root.exp2 = ok })
            return 400
        } },
        { name: "scale 2 file", run: function() {
            check("saved", root.exp2 === true, root.exp2)
            probe.source = "file://" + root.tmp + "/out2.png"
            return 200
        } },
        { name: "scale 2 size", run: function() {
            check("PNG is 1600x1000 (the frame's own pixels)", probe.implicitWidth === 1600 && probe.implicitHeight === 1000, probe.implicitWidth + "x" + probe.implicitHeight)
            ed.frameScale = 1
            return 50
        } },
        { name: "undo runs back across the layers", run: function() {
            const m = ed.marks
            const order = []
            while (m.count > 0) {
                const before = m.history[m.history.length - 1]
                const counts = [m.ink2.count, m.pixels.length, m.steps.length, m.texts.length].join("/")
                ed.handleKey(Qt.Key_Z, Qt.ControlModifier)
                order.push(before + ":" + counts + ">" + [m.ink2.count, m.pixels.length, m.steps.length, m.texts.length].join("/"))
            }
            check("ellipse, pixel, text, step, step, box, arrow",
                  JSON.stringify(order) === JSON.stringify(["ink:3/1/2/1>2/1/2/1", "pixel:2/1/2/1>2/0/2/1", "text:2/0/2/1>2/0/2/0", "step:2/0/2/0>2/0/1/0",
                                                            "step:2/0/1/0>2/0/0/0", "ink:2/0/0/0>1/0/0/0", "ink:1/0/0/0>0/0/0/0"]), JSON.stringify(order))
            check("nothing left to undo", !ed.undo())
            return 50
        } },
        { name: "crop mode moves the box", run: function() {
            ed.tool = "crop"
            drag(ed, 600, 400, 640, 380)
            check("moved by 40,-20", boxIs(240, 130, 800, 500), boxStr())
            return 50
        } },
        { name: "finish keys", run: function() {
            root.finishes = []
            ed.handleKey(Qt.Key_Return, 0)
            ed.handleKey(Qt.Key_C, Qt.ControlModifier)
            ed.handleKey(Qt.Key_Escape, 0)
            check("Enter save, Ctrl+C copy, Esc cancel", JSON.stringify(root.finishes) === '["save","copy","cancel"]', JSON.stringify(root.finishes))
            ed.reset()
            root.finishes = []
            ed.handleKey(Qt.Key_C, Qt.ControlModifier)
            check("Ctrl+C with no box copies the whole screen", JSON.stringify(root.finishes) === '["copy"]' && boxIs(0, 0, 1280, 800), boxStr())
            ed.reset()
            return 50
        } },
        { name: "the shell's files compile", run: function() {
            for (const f of ["Shot.qml", "SharePick.qml"]) {
                // offscreen there is no layer-shell backend, so creating a PanelWindow is the one error allowed
                const c = Qt.createComponent(f)
                const errs = c.errorString().split("\n").filter(l => l.trim() !== "" && l.indexOf("No PanelWindow backend loaded") === -1)
                check(f + " compiles (all but the PanelWindow backend)", c.status === Component.Ready || errs.length === 0, errs.join(" | "))
            }
            return 50
        } },
        // ---- share picker card ----
        { name: "share: screens", run: function() {
            win2.visible = true
            sp.lists = root.lists
            check("opens on Screens, first card", sp.tab === 0 && sp.sel === 0)
            sp.handleKey(Qt.Key_Right, 0)
            sp.handleKey(Qt.Key_Return, 0)
            check("Right, Enter: DP-9", JSON.stringify(root.chosen) === '["[SELECTION]/screen:DP-9"]', JSON.stringify(root.chosen))
            return 50
        } },
        { name: "share: windows and the token box", run: function() {
            root.chosen = []
            sp.handleKey(Qt.Key_Tab, 0)
            check("Tab: Windows", sp.tab === 1)
            sp.handleKey(Qt.Key_Space, 0)
            sp.handleKey(Qt.Key_Return, 0)
            check("Space ticks the box, Enter shares the first window by handle", JSON.stringify(root.chosen) === '["[SELECTION]r/window:2216345678"]', JSON.stringify(root.chosen))
            sp.handleKey(Qt.Key_Right, 0); sp.handleKey(Qt.Key_Right, 0); sp.handleKey(Qt.Key_Right, 0)
            check("Right stops at the last window", sp.sel === 2, sp.sel)
            if (root.out) stage2.grabToImage(r => r.saveToFile(root.out + "-share-windows.png"))
            return 300
        } },
        { name: "share: --allow-token ticks it to start with", run: function() {
            const l = JSON.parse(JSON.stringify(root.lists)); l.allowToken = true
            sp.lists = l
            check("ticked", sp.allow === true)
            sp.lists = root.lists
            check("not ticked", sp.allow === false)
            return 50
        } },
        { name: "share: region", run: function() {
            root.chosen = []
            sp.handleKey(Qt.Key_3, 0)
            sp.handleKey(Qt.Key_Right, 0)
            sp.handleKey(Qt.Key_Return, 0)
            check("Enter on a screen opens its picture", sp.regionOut === 1, sp.regionOut)
            sp.handleKey(Qt.Key_Return, 0)
            check("no box yet: nothing shared", root.chosen.length === 0, JSON.stringify(root.chosen))
            return 100
        } },
        { name: "share: region box", run: function() {
            const sel = findBox(sp)
            check("found the box", sel !== null)
            const k = 1080 / sel.width                 // output px per picture px
            drag(sel, 30, 50, 150, 220)
            const want = S.replyFor({ type: "region", output: "DP-9", x: 30 * k, y: 50 * k, w: 120 * k, h: 170 * k }, false)
            sp.handleKey(Qt.Key_Return, 0)
            check("region in the output's logical px (" + want + ")", root.chosen.length === 1 && root.chosen[0] === want, JSON.stringify(root.chosen) + " k=" + k)
            if (root.out) stage2.grabToImage(r => r.saveToFile(root.out + "-share-region.png"))
            return 300
        } },
        { name: "share: cancel", run: function() {
            root.chosen = []
            sp.handleKey(Qt.Key_Escape, 0)
            check("Esc cancels", JSON.stringify(root.chosen) === '["cancel"]')
            sp.handleKey(Qt.Key_1, 0)
            Theme.dark = false
            if (root.out) stage2.grabToImage(r => r.saveToFile(root.out + "-share-screens-light.png"))
            return 300
        } }
    ]
    property var exp1: null
    property var exp2: null
    function findBox(item) {
        if (item.drawing !== undefined && item.sw !== undefined && item.visible) return item
        for (let i = 0; i < item.children.length; i++) { const r = findBox(item.children[i]); if (r) return r }
        return null
    }

    property int at: 0
    Timer {
        interval: 600; running: true
        onTriggered: {
            if (root.at >= root.cases.length) {
                console.log("SHOTTEST RESULT pass " + root.passed + " fail " + root.failed)
                Qt.quit()
                return
            }
            const c = root.cases[root.at++]
            console.log("SHOTTEST case: " + c.name)
            let wait = 100
            try { wait = c.run() } catch (e) { root.failed++; console.log("SHOTTEST FAIL " + c.name + " threw: " + e) }
            interval = Math.max(20, wait || 100)
            restart()
        }
    }
}
