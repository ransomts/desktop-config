// Tests for Settings > Displays (SettingsDisplays.qml, DisplaysMap.qml, DisplaysPicker.qml,
// DisplaysConfirm.qml, DisplaysIdentify.qml, displays.js) inside the real settings window. NOT part
// of the shell: ~/.local/bin/displays-test copies the real files next to the settings stubs
// (tests/settings) and runs this offscreen. The page runs the real display-layout, whose hyprctl is
// tests/displays/fake-hyprctl on canned monitors ($FAKE_MONITORS), so every apply/revert lands in
// $FAKE_LOG and nothing reaches Hyprland. DISPLAYS_CASE: desk (four screens) or laptop.
// Lines: DTEST PASS / FAIL, last "DTEST RESULT pass N fail M". Pictures to $DISPLAYS_TEST_OUT.
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "displays.js" as Geo

ShellRoot {
    id: root
    property int passed: 0
    property int failed: 0
    function check(what, ok, detail) {
        if (ok) passed++; else failed++
        console.log("DTEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
    }
    readonly property string home: Quickshell.env("HOME")
    readonly property string picDir: Quickshell.env("DISPLAYS_TEST_OUT")
    readonly property string which: Quickshell.env("DISPLAYS_CASE") || "desk"
    readonly property string fakeLog: Quickshell.env("FAKE_LOG")
    readonly property string fakeMon: Quickshell.env("FAKE_MONITORS")
    readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR")

    Item { id: islandStub; property bool enabled: true; property var said: []
        function say(m) { said = said.concat([m]) }
        function setEnabled(on) { enabled = on }
    }
    QtObject { id: identStub; property var calls: []; function flash(list) { calls = calls.concat([list]); identReal.flash(list) } }
    QtObject { id: cursorStub; property bool enabled: true }
    QtObject { id: dropStub; property bool enabled: true }
    QtObject {
        id: viewStub
        readonly property var modes: [{ id: "apps", prefix: "" }]
        function close() {}
    }

    Settings { id: settings; island: islandStub; launcherView: viewStub; cursorFind: cursorStub; dropPreview: dropStub; identify: identStub }
    DisplaysIdentify { id: identReal; ms: 600 }
    TestEvent { id: ev }

    FileView { id: handFile; printErrors: false; blockLoading: true; blockWrites: true }
    function readText(path) { handFile.path = ""; handFile.path = path; return handFile.text() }
    function exists(path) { handFile.path = ""; handFile.path = path; return handFile.loaded && handFile.text() !== undefined && handFile.text() !== "" }
    function evals() { return readText(fakeLog).split("\n").filter(l => l.startsWith("eval | ")).map(l => l.slice(7)) }
    function liveMon(part) { const a = JSON.parse(readText(fakeMon)); return a.find(m => m.description.indexOf(part) >= 0) }
    FileView { id: modeFile; path: root.home + "/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark"; printErrors: false; blockWrites: true }
    function setDark(d) { modeFile.setText(d ? "true\n" : "false\n"); Theme.reload() }

    readonly property var body: settings.body
    function page() { return body ? body.pageItem("displays") : null }
    function rows() { return body.rowsOf(page().contentItem, []) }
    function row(label) { return rows().find(r => r.label === label) || null }
    function findAll(item, pred, acc) {
        acc = acc || []
        if (!item) return acc
        if (pred(item)) acc.push(item)
        for (let i = 0; i < (item.children || []).length; i++) findAll(item.children[i], pred, acc)
        return acc
    }
    function map() { return findAll(page().contentItem, x => x.snapPx !== undefined && x.nudge !== undefined)[0] }
    function screens() { const m = map(); return findAll(m, x => x.held !== undefined && x.lx !== undefined).sort((a, b) => a.index - b.index) }
    function win() { return body.Window.window }
    function focusWin() { const w = win(); if (w && !w.active) w.requestActivate() }
    function key(k, mods) { focusWin(); ev.keyClick(k, mods || Qt.NoModifier, -1) }
    function click(item, x, y) {
        const w = item.Window.window
        const p = item.mapToItem(null, x === undefined ? item.width / 2 : x, y === undefined ? item.height / 2 : y)
        ev.mouseClick(w, p.x, p.y, Qt.LeftButton, Qt.NoModifier, -1)
    }
    function chipOf(r) { page().reveal(r); return findAll(r.controlItem, x => x.label !== undefined && x.fixedWidth !== undefined)[0] }
    // drag screen i by (dx, dy) logical pixels, in small steps like a hand would
    function drag(i, dx, dy) {
        const m = map(), s = screens()[i], w = win()
        const a = s.mapToItem(null, s.width / 2, s.height / 2)
        const bx = a.x + dx * m.k, by = a.y + dy * m.k
        ev.mousePress(w, a.x, a.y, Qt.LeftButton, Qt.NoModifier, -1)
        for (let t = 1; t <= 8; t++) ev.mouseMove(w, a.x + (bx - a.x) * t / 8, a.y + (by - a.y) * t / 8, -1, Qt.LeftButton, Qt.NoModifier)
        ev.mouseRelease(w, bx, by, Qt.LeftButton, Qt.NoModifier, -1)
    }
    function rects() { return page().rectsOf(page().mons) }
    function layoutOk() { return Geo.valid(rects()) }
    function size(w, h) {
        settings.implicitWidth = w; settings.implicitHeight = h
        const q = Qt.size(w, h)
        settings.maximumSize = Qt.size(9999, 9999); settings.minimumSize = q; settings.maximumSize = q
    }
    property int grabbing: 0
    property double holdUntil: 0
    function picture(name, target) {
        if (!picDir) return
        grabbing++
        const ok = (target || body).grabToImage(r => { r.saveToFile(picDir + "/" + name + ".png"); console.log("DTEST picture " + name); holdUntil = Date.now() + 250; grabbing-- })
        if (!ok) { console.log("DTEST FAIL picture " + name + " not taken"); failed++; grabbing-- }
    }
    property Item backdrop: null
    function backdropFor() {
        if (!backdrop || backdrop.parent !== body) backdrop = Qt.createQmlObject('import QtQuick; Rectangle { anchors.fill: parent; z: -1; gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "#2b3a55" } GradientStop { position: 0.6; color: "#6b4c7a" } GradientStop { position: 1; color: "#c97b4a" } } }', body)
    }
    function overflow() {
        const bad = []
        for (const r of rows()) {
            if (!r.visible || r.width <= 0) continue
            const c = r.controlItem, cx = c.mapToItem(r, 0, 0).x
            if (cx < -1 || cx + c.width > r.width + 1) bad.push(r.label + " control " + Math.round(cx) + "+" + Math.round(c.width) + ">" + Math.round(r.width))
            else if (!r.below && r.labelItem.width < 119) bad.push(r.label + " label " + Math.round(r.labelItem.width))
        }
        return bad
    }
    function laptopIndex() { return page().mons.findIndex(m => m.name === "eDP-1") }

    readonly property var common: [
        { name: "open on Displays", run: function() {
            size(1920, 1080)
            setDark(true)
            settings.open("displays")
            return 1800
        } },
        { name: "page is listed and loaded", run: function() {
            check("Displays in the page list", settings.pages.some(p => p.id === "displays"))
            check("on the Displays page", settings.page === "displays" && page() && page().visible)
            check("live monitors read", page().loaded && page().loadError === "", page().loadError)
            check("rows fit 1920x1080", overflow().length === 0, overflow().join("; "))
            backdropFor()
            return 100
        } }
    ]

    readonly property var deskCases: [
        { name: "desk: map", run: function() {
            const p = page()
            check("4 screens on the map", p.mons.length === 4 && screens().length === 4, p.mons.length + " / " + screens().length)
            check("left to right", p.mons.map(m => m.label).join(",") === "DELL P2425HE,DELL P2214H,S34J55x,Laptop", p.mons.map(m => m.label).join(","))
            check("portrait Dell drawn tall", screens()[1].height > screens()[1].width * 1.5, screens()[1].width + "x" + screens()[1].height)
            check("in proportion: Samsung 3440 wide vs Dell 1920", Math.abs(screens()[2].width / screens()[0].width - 3440 / 1920) < 0.05)
            check("the focused screen (Samsung) is marked and picked", p.mapModel[2].focused && !p.mapModel[0].focused && p.sel === 2)
            check("laptop is primary by default", p.primary === "AU Optronics 0x683D" && p.mapModel[3].primary)
            check("Apply off while nothing changed", !p.canApply)
            picture("desk-dark")
            return 300
        } },
        { name: "desk: page scrolled (screen card)", run: function() {
            page().contentY = Math.max(0, page().contentHeight - page().height)
            picture("desk-dark-lower")
            return 300
        } },
        { name: "drag the laptop: snaps to the Samsung's edge", run: function() {
            page().contentY = 0
            drag(3, 40, 300)
            const l = page().mons[3]
            check("x snapped flush to the Samsung (6440)", l.x === 6440, l.x)
            check("y moved about 300 down", Math.abs(l.y - 1140) < 30, l.y)
            check("layout valid", layoutOk())
            check("picked the dragged one", page().sel === 3)
            check("dirty: one screen changes", page().changedCount === 1, page().changedCount)
            return 600
        } },
        { name: "validate ran: no errors", run: function() {
            check("no errors from display-layout validate", page().errors.length === 0, page().errors.join("; "))
            check("Apply enabled", page().canApply)
            return 100
        } },
        { name: "drop onto the Samsung: never overlaps", run: function() {
            const before = page().mons[3]
            drag(3, -1500, -100)          // into the Samsung's middle
            check("no overlap after the drop", !Geo.anyOverlap(rects()), JSON.stringify(rects()))
            check("still touching (connected)", Geo.connected(rects()))
            return 300
        } },
        { name: "drop in empty space: pulled back to touch", run: function() {
            drag(3, 2500, 0)
            check("valid after a drop far away", layoutOk(), JSON.stringify(rects()[3]))
            check("touching someone", rects().some((r, k) => k !== 3 && Geo.touch(r, rects()[3]) >= 64))
            return 300
        } },
        { name: "drag the portrait Dell away would strand the left Dell: refused", run: function() {
            page().resetEdits()
            drag(1, 0, -3000)
            check("layout still valid", layoutOk(), JSON.stringify(rects()))
            page().resetEdits()
            return 300
        } },
        { name: "keyboard nudge", run: function() {
            const p = page()
            p.sel = 3
            row("Drag a screen to move it").forceActiveFocus()
            key(Qt.Key_Down)
            check("Down moves the picked screen 10 px", p.mons[3].y === 850 && p.mons[3].x === 6440, p.mons[3].x + "," + p.mons[3].y)
            key(Qt.Key_Down, Qt.ShiftModifier)
            check("Shift+Down 100 px", p.mons[3].y === 950, p.mons[3].y)
            key(Qt.Key_Right)
            check("Right into a gap: refused (would strand it)", p.mons[3].x === 6440, p.mons[3].x)
            key(Qt.Key_Space)
            check("Space picks the next screen", p.sel === 0, p.sel)
            p.sel = 3
            return 700
        } },
        { name: "Apply: one eval, countdown shown", run: function() {
            check("Apply enabled", page().canApply, JSON.stringify(page().errors))
            click(chipOf(row("Apply")))
            return 1800
        } },
        { name: "countdown up", run: function() {
            const e = evals()
            check("exactly one hyprctl eval, for the laptop", e.length === 1 && e[0] === 'hl.monitor({ output = "eDP-1", mode = "1920x1080@60.049", position = "6440x950", scale = 1, transform = 0 })', JSON.stringify(e))
            check("live laptop moved", liveMon("AU Opt").y === 950)
            const c = page().confirmDialog
            check("Keep this layout? shown", c.visible)
            check("covers the whole window", c.parent === win().contentItem && c.width === win().width && c.height === win().height, c.width + "x" + c.height)
            check("counts from 15", c.seconds === 15 && c.remaining >= 13, c.remaining)
            check("page not dirty: the live layout is the edited one", !page().dirty)
            check("Save waits for Keep", !page().canSave)
            picture("desk-confirm-dark", c)
            return 400
        } },
        { name: "while counting: a click outside does not close", run: function() {
            ev.mouseClick(win(), 4, 4, Qt.LeftButton, Qt.NoModifier, -1)
            check("window still open", settings.visible)
            check("still asking", page().confirmDialog.visible)
            ev.mouseClick(win(), 40, win().height / 2, Qt.LeftButton, Qt.NoModifier, -1)   // where the page list is
            check("page list behind is not reachable", settings.page === "displays")
            key(Qt.Key_Return)
            check("Enter does not keep", page().confirmDialog.visible)
            key(Qt.Key_Escape)
            check("Esc: dialog gone", !page().confirmDialog.visible)
            check("Esc did not close the window", settings.visible)
            return 1500
        } },
        { name: "Esc reverted", run: function() {
            const e = evals()
            check("revert sent one eval back to 6440x840", e.length === 2 && e[1].indexOf('position = "6440x840"') >= 0, JSON.stringify(e))
            check("live laptop back", liveMon("AU Opt").y === 840)
            check("edits back to live", !page().dirty && page().mons[3].y === 840, page().mons[3].y)
            check("note says so", page().note.indexOf("Back") === 0, page().note)
            return 100
        } },
        { name: "auto-revert at 0", run: function() {
            page().confirmDialog.seconds = 2
            page().moveTo(3, 6440, 860)
            return 700
        } },
        { name: "apply for the auto-revert", run: function() { page().apply(); return 1200 } },
        { name: "applied, waiting", run: function() {
            check("applied", liveMon("AU Opt").y === 860 && page().confirmDialog.visible)
            return 2600
        } },
        { name: "reverted by itself", run: function() {
            check("dialog gone at 0", !page().confirmDialog.visible)
            return 1500
        } },
        { name: "reverted live", run: function() {
            check("live laptop back after the countdown", liveMon("AU Opt").y === 840, liveMon("AU Opt").y)
            page().confirmDialog.seconds = 15
            page().moveTo(3, 6440, 870)
            return 700
        } },
        { name: "apply then Keep", run: function() { page().apply(); return 1200 } },
        { name: "Keep", run: function() {
            check("dialog up", page().confirmDialog.visible)
            click(page().confirmDialog.keepButton)
            return 1500
        } },
        { name: "kept, then Save", run: function() {
            check("live stays", liveMon("AU Opt").y === 870)
            check("rollback dropped", readText(runDir + "/display-layout/rollback.json.kept").indexOf("6440") >= 0 && readText(runDir + "/display-layout/rollback.json") === "")
            check("Save enabled after Keep", page().canSave)
            check("note: kept", page().note.indexOf("Kept") === 0, page().note)
            click(chipOf(row("Save")))
            return 3000
        } },
        { name: "saved", run: function() {
            const lua = readText(Quickshell.env("DISPLAY_LAYOUT_LUA"))
            check("monitors.lua has the new laptop rule", lua.indexOf('hl.monitor({ output = "eDP-1", mode = "1920x1080@60.049", position = "6440x870"') >= 0, lua.slice(0, 200))
            check("monitors.lua has all four", (lua.match(/^hl\.monitor/mg) || []).length === 4)
            check("displays.json written", readText(Quickshell.env("DISPLAY_LAYOUT_SAVED")).indexOf("6440") >= 0)
            check("Save done: off again", !page().canSave, page().note)
            check("note: saved", page().note.indexOf("Saved") === 0, page().note)
            return 100
        } },
        { name: "scale on the Samsung pulls the laptop along", run: function() {
            const p = page()
            p.sel = 2
            const sc = row("Scale")
            check("scale offers only whole-pixel ones", JSON.stringify(sc.values) === JSON.stringify([1, 1.25, 1.333333, 1.6, 1.666667, 2, 2.5]), JSON.stringify(sc.values))
            sc.forceActiveFocus(); key(Qt.Key_Right)
            check("Right: 1.25", p.mons[2].scale === 1.25, p.mons[2].scale)
            check("laptop now flush at 3000 + 2752", p.mons[3].x === 5752, p.mons[3].x)
            check("valid", layoutOk())
            const md = row("Resolution")
            check("Samsung's modes listed", md.values.length === 6 && md.values[0] === "3440x1440@59.973", JSON.stringify(md.values))
            md.forceActiveFocus(); key(Qt.Key_Right)
            check("next mode 3440x1440@49.99, scale kept if it suits", p.mons[2].mode === "3440x1440@49.99" && p.mons[2].scale === 1.25, p.mons[2].mode + " " + p.mons[2].scale)
            p.resetEdits()
            return 300
        } },
        { name: "rotate the laptop", run: function() {
            const p = page()
            p.sel = 3
            row("Rotation").edited(1)
            check("laptop 1080x1920 now", p.mapModel[3].w === 1080 && p.mapModel[3].h === 1920, p.mapModel[3].w + "x" + p.mapModel[3].h)
            check("still valid where it is", layoutOk() && p.mons[3].x === 6440)
            picture("desk-rotated-dark")
            p.resetEdits()
            return 300
        } },
        { name: "primary", run: function() {
            const p = page()
            p.sel = 0
            row("Primary screen").edited(true)
            check("primary is the left Dell", p.primary === "Dell Inc. DELL P2425HE 8BY1H14" && p.mapModel[0].primary && !p.mapModel[3].primary)
            check("Save offered for a new primary", p.canSave)
            p.primary = "AU Optronics 0x683D"
            return 100
        } },
        { name: "Identify", run: function() {
            click(chipOf(row("Identify")))
            check("identify hook called with 4 screens", identStub.calls.length === 1 && identStub.calls[0].length === 4, JSON.stringify(identStub.calls))
            check("overlay up", identReal.on && Object.keys(identReal.byName).length === 4)
            return 900
        } },
        { name: "Identify goes away", run: function() {
            check("overlay gone after its time", !identReal.on)
            return 100
        } },
        { name: "closing the window mid-trial reverts", run: function() {
            page().moveTo(3, 6440, 880)
            return 700
        } },
        { name: "apply before closing", run: function() { page().apply(); return 1200 } },
        { name: "close", run: function() {
            check("applied", liveMon("AU Opt").y === 880 && page().confirmDialog.visible)
            settings.close()
            return 2500
        } },
        { name: "closed: reverted", run: function() {
            check("live back after the window closed", liveMon("AU Opt").y === 870, liveMon("AU Opt").y)
            setDark(false)
            settings.open("displays")
            return 1800
        } },
        { name: "light pictures", run: function() {
            backdropFor()
            check("reloaded", page().mons.length === 4)
            picture("desk-light")
            page().moveTo(3, 6440, 900)
            return 700
        } },
        { name: "light confirm", run: function() { page().apply(); return 1200 } },
        { name: "light confirm picture", run: function() {
            picture("desk-confirm-light", page().confirmDialog)
            return 400
        } },
        { name: "revert by button", run: function() {
            click(page().confirmDialog.revertButton)
            return 1500
        } },
        { name: "reverted by button", run: function() {
            check("live back", liveMon("AU Opt").y === 870)
            return 100
        } },
        { name: "portrait screen fits", run: function() {
            size(1080, 1920)
            return 500
        } },
        { name: "portrait", run: function() {
            check("rows fit portrait", overflow().length === 0, overflow().join("; "))
            picture("desk-portrait-light")
            return 300
        } }
    ]

    readonly property var laptopCases: [
        { name: "laptop: one screen", run: function() {
            const p = page()
            check("1 screen", p.mons.length === 1 && screens().length === 1)
            check("map locked", map().locked)
            check("label says nothing to arrange", row("One screen: nothing to arrange") !== null)
            check("primary is the laptop", p.mapModel[0].primary)
            picture("laptop-dark")
            const md = row("Resolution")
            check("its two modes", md.values.length === 2, JSON.stringify(md.values))
            md.forceActiveFocus(); key(Qt.Key_Right)
            check("48 Hz picked", p.mons[0].mode === "1920x1080@48.04", p.mons[0].mode)
            return 700
        } },
        { name: "laptop: drag does nothing", run: function() {
            drag(0, 300, 300)
            check("not moved", page().mons[0].x === 6440 && page().mons[0].y === 840)
            check("Apply enabled for the mode", page().canApply, JSON.stringify(page().errors))
            page().apply()
            return 1200
        } },
        { name: "laptop: applied", run: function() {
            const e = evals()
            check("one eval with the 48 Hz mode", e.length === 1 && e[0].indexOf('mode = "1920x1080@48.04"') >= 0, JSON.stringify(e))
            key(Qt.Key_K)
            return 1500
        } },
        { name: "laptop: kept", run: function() {
            check("K keeps", !page().confirmDialog.visible && liveMon("AU Opt").refreshRate === 48.04 && evals().length === 1)
            setDark(false)
            page().resetEdits()
            return 400
        } },
        { name: "laptop light", run: function() {
            backdropFor()
            picture("laptop-light")
            return 300
        } }
    ]

    readonly property var cases: common.concat(which === "laptop" ? laptopCases : deskCases)
    property int at: 0
    Timer {
        interval: 900; running: true
        onTriggered: {
            if (root.grabbing > 0 || Date.now() < root.holdUntil) { interval = 50; restart(); return }
            if (root.at >= root.cases.length) {
                console.log("DTEST RESULT pass " + root.passed + " fail " + root.failed)
                done.start()
                return
            }
            const c = root.cases[root.at++]
            console.log("DTEST case: " + c.name)
            let wait = 100
            try { wait = c.run() } catch (e) { root.failed++; console.log("DTEST FAIL " + c.name + " threw: " + e + " " + e.stack) }
            interval = Math.max(20, wait || 100)
            restart()
        }
    }
    Timer { id: done; interval: 400; onTriggered: Qt.quit() }
}
