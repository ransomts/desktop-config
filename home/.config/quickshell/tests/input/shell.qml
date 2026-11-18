// Tests for the settings Input page (SettingsInput.qml) against the real bin/input-settings, which talks
// to a fake hyprctl (tests/input/hyprctl) that logs every eval and applies it to a table of options seeded
// from real getoption captures. NOT part of the shell: bin/input-test copies the files next to this and
// runs it offscreen. Cases log ITEST PASS or FAIL; the last line is "ITEST RESULT pass N fail M".
// INPUT_PASS=none: the run without a Moonlander or trackball connected. Pictures: $INPUT_TEST_OUT.
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property int passed: 0
    property int failed: 0
    function check(what, ok, detail) {
        if (ok) passed++; else failed++
        console.log("ITEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
    }
    readonly property string stateDir: Quickshell.env("FAKE_STATE")
    readonly property string picDir: Quickshell.env("INPUT_TEST_OUT")
    readonly property bool none: Quickshell.env("INPUT_PASS") === "none"
    readonly property string modeFile: Quickshell.env("HOME") + "/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark"

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 760; implicitHeight: 2020
        color: Theme.solidBg
        Rectangle {
            id: stage
            anchors.fill: parent
            color: Theme.solidBg
            SettingsInput { id: pg; anchors.fill: parent; anchors.margins: 16 }
        }
    }
    TestEvent { id: ev }
    FileView { id: hand; printErrors: false; blockLoading: true; blockWrites: true }
    function readText(f) { hand.path = ""; hand.path = f; try { return hand.text() } catch (e) { return "" } }
    function evals() { return readText(stateDir + "/evals").split("\n").filter(l => l) }
    function calls() { return readText(stateDir + "/calls").split("\n").filter(l => l) }
    function opts() { try { return JSON.parse(readText(stateDir + "/opts.json")) } catch (e) { return {} } }
    function saved() { try { return JSON.parse(readText(Quickshell.env("INPUT_SETTINGS_FILE"))) } catch (e) { return null } }
    function lastEval() { const e = evals(); return e.length ? e[e.length - 1] : "" }
    function setDark(d) { hand.path = ""; hand.path = modeFile; hand.setText(d ? "true\n" : "false\n"); Theme.reload() }

    function rowsIn(item, out) {
        if (!item) return out
        if (item.settingRow === true) out.push(item)
        for (const k of (item.children || [])) rowsIn(k, out)
        return out
    }
    function row(label, n) { const r = rowsIn(pg.contentItem, []).filter(x => x.label === label); return r[n || 0] || null }
    function findType(item, pred) {
        if (!item) return null
        if (pred(item)) return item
        for (const k of (item.children || [])) { const r = findType(k, pred); if (r) return r }
        return null
    }
    function chips(r) { const out = []; (function w(i) { if (!i) return; if (i.label !== undefined && i.clicked && i.fixedWidth !== undefined) out.push(i); for (const k of (i.children || [])) w(k) })(r.controlItem); return out }
    function click(item) {
        const w = item.Window.window
        if (w && !w.active) w.requestActivate()
        const p = item.mapToItem(null, item.width / 2, item.height / 2)
        ev.mouseClick(w, p.x, p.y, Qt.LeftButton, Qt.NoModifier, -1)
    }
    function clickChip(r, label) { const c = chips(r).find(x => x.label === label); if (!c) { check("chip " + label + " exists on " + r.label, false); return } click(c) }
    function clickSwitch(r) { click(r.controlItem.children[0]) }
    function busy() { return pg.queue.length > 0 || pg.setter.running || pg.getter.running }

    // ---- the steps: { name, run(), after() }  run starts an action; after checks once everything settled ----
    property var steps: []
    property int at: -1
    property int quiet: 0
    function exact(what, want) { const e = lastEval(); check(what + " eval", e === want, e) }
    function steppers() {
        // [label, nth, expected value after +, after -] on a stepper: + then back
        return [
            ["Key repeat rate", 0, "repeat_rate = 30", "repeat_rate = 25"],
            ["Key repeat delay", 0, "repeat_delay = 650", "repeat_delay = 600"],
            ["Scroll speed", 0, "scroll_factor = 1.1", "scroll_factor = 1.0"],   // touchpad
            ["Pointer speed", 0, "sensitivity = 0.1", "sensitivity = 0.0"],
            ["Scroll speed", 1, "scroll_factor = 1.1", "scroll_factor = 1.0"]    // mouse
        ]
    }
    Component.onCompleted: {
        const S = []
        const add = (name, run, after) => S.push({ name: name, run: run, after: after })
        add("page loads the live values", () => {}, () => {
            const v = pg.vals
            check("repeat rate read", v["repeat_rate"] === 25 && v["repeat_delay"] === 600, JSON.stringify(v))
            check("touchpad values read", v["touchpad.tap_to_click"] === true && v["touchpad.natural_scroll"] === true && v["touchpad.middle_button_emulation"] === false)
            check("empty accel profile reads as adaptive", v["accel_profile"] === "adaptive")
            check("first layout read from kb_variant dvorak,", v["first_layout"] === "dvorak")
            check("rows show them", row("Key repeat rate").value === 25 && row("Tap to click").checked === true && row("Natural scrolling", 1).checked === false)
            check("page loaded flag", pg.loaded && pg.error === "")
            check("layout key shown read-only", row("Switch layout").value === "Super+Space")
            check("no eval just from opening", evals().length === 0)
        })
        // switches: click on, click off (touchpad then mouse)
        const sw = [
            ["Tap to click", 0, "touchpad = { tap_to_click = false }", "touchpad = { tap_to_click = true }"],
            ["Tap and drag", 0, "touchpad = { tap_and_drag = false }", "touchpad = { tap_and_drag = true }"],
            ["Pause while typing", 0, "touchpad = { disable_while_typing = false }", "touchpad = { disable_while_typing = true }"],
            ["Middle click by tapping left and right together", 0, "touchpad = { middle_button_emulation = true }", "touchpad = { middle_button_emulation = false }"],
            ["Click by number of fingers", 0, "touchpad = { clickfinger_behavior = true }", "touchpad = { clickfinger_behavior = false }"],
            ["Natural scrolling", 0, "touchpad = { natural_scroll = false }", "touchpad = { natural_scroll = true }"],
            ["Natural scrolling", 1, "natural_scroll = true", "natural_scroll = false"],
            ["Num Lock on at start", 0, "numlock_by_default = true", "numlock_by_default = false"]
        ]
        for (const [label, n, a, b] of sw) {
            add(label + " (" + n + ") on/off", () => { clickSwitch(row(label, n)) }, () => {
                check(label + " first click eval", lastEval() === "hl.config({ input = { " + a + " } })", lastEval())
                clickSwitch(row(label, n))
            })
            add(label + " (" + n + ") back", () => {}, () => {
                check(label + " second click eval", lastEval() === "hl.config({ input = { " + b + " } })", lastEval())
            })
        }
        for (const [label, n, up, down] of steppers()) {
            add(label + " (" + n + ") up", () => { row(label, n).stepped(1) }, () => {
                check(label + " + eval", lastEval() === "hl.config({ input = { " + (n === 0 && label === "Scroll speed" ? "touchpad = { " + up + " }" : up) + " } })", lastEval())
                row(label, n).stepped(-1)
            })
            add(label + " (" + n + ") down", () => {}, () => {
                check(label + " - eval", lastEval() === "hl.config({ input = { " + (n === 0 && label === "Scroll speed" ? "touchpad = { " + down + " }" : down) + " } })", lastEval())
                check(label + " shown value follows", Math.abs(row(label, n).value - (label === "Key repeat rate" ? 25 : label === "Key repeat delay" ? 600 : label === "Scroll speed" ? 1 : 0)) < 1e-6, row(label, n).value)
            })
        }
        add("stepper stops at its limit", () => { root.evalsBefore = evals().length; pg.vals = Object.assign({}, pg.vals, { repeat_rate: 100 }); row("Key repeat rate").stepped(1) }, () => {
            check("no eval past 100", evals().length === root.evalsBefore, lastEval())
            pg.refresh()
        })
        add("accel profile both ways", () => { clickChip(row("Acceleration"), "Flat") }, () => {
            exact("flat", 'hl.config({ input = { accel_profile = "flat" } })')
            check("accel reads flat afterwards", pg.vals["accel_profile"] === "flat" && row("Acceleration").value === "flat")
            clickChip(row("Acceleration"), "Adaptive")
        })
        add("accel back", () => {}, () => exact("adaptive", 'hl.config({ input = { accel_profile = "adaptive" } })'))
        add("first layout both ways", () => { clickChip(row("First layout"), "US") }, () => {
            exact("us first", 'hl.config({ input = { kb_variant = ",dvorak" } })')
            check("reads back us", pg.vals["first_layout"] === "us")
            clickChip(row("First layout"), "Dvorak")
        })
        add("first layout back", () => {}, () => exact("dvorak first", 'hl.config({ input = { kb_variant = "dvorak," } })'))
        for (const [id, lbl] of [[0, "Click"], [2, "Click, pointer free"], [3, "Click, loose"], [1, "Hover"]]) {
            add("focus " + lbl, () => { clickChip(row("Focus"), lbl) }, () => {
                exact("focus " + lbl, "hl.config({ input = { follow_mouse = " + id + " } })")
                check("focus row shows " + id, row("Focus").value === id)
            })
        }
        if (!none) {
            add("moonlander row present and sets both names", () => {
                check("Moonlander row visible", row("Moonlander layout") && row("Moonlander layout").visible)
                clickChip(row("Moonlander layout"), "Software")
            }, () => {
                const e = evals().slice(-2)
                check("both Moonlander names get hl.device", e.length === 2 && e[0].indexOf('name = "zsa-technology-labs-moonlander-mark-i"') > 0 && e[1].indexOf('name = "zsa-technology-labs-moonlander-mark-i-keyboard"') > 0, JSON.stringify(e))
                check("software = Dvorak variant, caps kept", e[0] === 'hl.device({ name = "zsa-technology-labs-moonlander-mark-i", kb_layout = "us", kb_variant = "dvorak", kb_options = "caps:ctrl_modifier" })', e[0])
                check("row shows Software", row("Moonlander layout").value === "dvorak")
                clickChip(row("Moonlander layout"), "Firmware")
            })
            add("moonlander back", () => {}, () => {
                const e = evals().slice(-2)
                check("firmware = plain US", e[1].indexOf('kb_variant = ""') > 0 && e[1].indexOf('kb_layout = "us"') > 0, e[1])
                check("saved in the file", JSON.stringify(saved().devices["zsa-technology-labs-moonlander-mark-i"]) === '{"layout":"us"}', JSON.stringify(saved()))
            })
            add("trackball speed row", () => {
                const r = row("kensington-expert-wireless-trackball speed")
                check("trackball row exists, touchpad twin has none", r !== null && row("elan0412:00-04f3:311d-mouse speed") === null)
                r.stepped(1)
            }, () => {
                exact("trackball", 'hl.device({ name = "kensington-expert-wireless-trackball", sensitivity = 0.1 })')
                check("shows 0.1", Math.abs(row("kensington-expert-wireless-trackball speed").value - 0.1) < 1e-6)
                row("kensington-expert-wireless-trackball speed").stepped(-1)
            })
            add("trackball back", () => {}, () => exact("trackball back", 'hl.device({ name = "kensington-expert-wireless-trackball", sensitivity = 0.0 })'))
        } else {
            add("no Moonlander or trackball: rows hidden", () => {}, () => {
                check("Moonlander row hidden", !row("Moonlander layout").visible)
                check("no per-device speed rows", rowsIn(pg.contentItem, []).filter(r => r.label.endsWith(" speed") && r.label.indexOf("Scroll") < 0 && r.label !== "Pointer speed").length === 0)
            })
        }
        add("devices card lists names read-only", () => {}, () => {
            const names = rowsIn(pg.contentItem, []).filter(r => r.takesFocus === false && r.label.indexOf("elan0412") === 0).map(r => r.label)
            check("touchpad listed", names.indexOf("elan0412:00-04f3:311d-touchpad") >= 0, JSON.stringify(names))
            check("laptop keyboard listed, power-button not", row("at-translated-set-2-keyboard") !== null && row("power-button") === null)
            check("system devices counted", row("Other key devices") && row("Other key devices").visible)
        })
        add("try it: typing and scrolling", () => {
            const t = findType(pg.contentItem, x => x.objectName === "tryInput")
            t.forceActiveFocus()
            t.Window.window.requestActivate()
            for (const c of "abc") ev.keyClickChar(c, Qt.NoModifier, -1)
        }, () => {
            const t = findType(pg.contentItem, x => x.objectName === "tryInput")
            check("try box takes typing", t.text === "abc", t.text)
            const f = findType(pg.contentItem, x => x.objectName === "tryScroll")
            f.contentY = 40
            check("scroll box says which way", pg.tryNote.indexOf("Scrolled down") === 0, pg.tryNote)
            f.contentY = 10
            check("and back up", pg.tryNote.indexOf("Scrolled up") === 0, pg.tryNote)
        })
        add("a failing hyprctl is reported and not recorded", () => {
            hand.path = ""; hand.path = stateDir + "/fail"; hand.setText("x")
            clickSwitch(row("Tap to click"))
        }, () => {
            check("error shown", pg.error.indexOf("failed") >= 0 || pg.error.indexOf("boom") >= 0, pg.error)
            check("not saved as off", saved().overrides["touchpad.tap_to_click"] !== false, JSON.stringify(saved().overrides))
            check("row went back to the live value", row("Tap to click").checked === true)
            check("Last problem row visible", row("Last problem") && row("Last problem").visible)
            Qt.createQmlObject('import Quickshell.Io; Process { command: ["rm", "-f", "' + stateDir + '/fail"]; running: true }', root)
        })
        add("reset needs a second click", () => { row("Tap to click").edited(false) }, () => {
            root.evalsBefore = evals().length
            check("overrides saved before reset", saved().overrides["touchpad.tap_to_click"] === false)
            click(chips(row("Reset input settings"))[0])
        })
        add("after first click nothing happened", () => {}, () => {
            check("button armed", row("Reset input settings").armed === true)
            check("no eval on the first click", evals().length === root.evalsBefore)
            check("saved untouched", saved().overrides["touchpad.tap_to_click"] === false)
            click(chips(row("Reset input settings"))[0])
        })
        add("second click resets", () => {}, () => {
            check("exactly one reset eval", evals().length === root.evalsBefore + 1, evals().length + " vs " + root.evalsBefore)
            const e = lastEval()
            check("reset eval puts the defaults back", e.indexOf("hl.config({ input = {") === 0 && e.indexOf("tap_to_click = true") > 0 && e.indexOf("repeat_rate = 25") > 0 && e.indexOf("kb_variant") > 0, e)
            check("saved file empty", JSON.stringify(saved().overrides) === "{}" && JSON.stringify(saved().devices) === "{}", JSON.stringify(saved()))
            check("page shows defaults again", row("Tap to click").checked === true && !row("Reset input settings").armed)
        })
        add("hidden page does not ask Hyprland", () => { root.callsBefore = calls().length; pg.visible = false }, () => {})
        add("hidden stays quiet", () => {}, () => {
            check("no hyprctl call while hidden", calls().length === root.callsBefore, calls().length + " vs " + root.callsBefore)
            pg.visible = true
        })
        add("shown again reads again", () => {}, () => {
            check("reads once shown", calls().length > root.callsBefore)
        })
        // pictures: lots of state, dark and light
        add("picture dark", () => { setDark(true); pg.contentY = 0; row("Tap to click").edited(false); row("Pointer speed").stepped(1) }, () => {})
        add("picture dark take", () => { root.pic("input-dark") }, () => {})
        add("picture light", () => { setDark(false) }, () => {})
        add("picture light take", () => { root.pic("input-light") }, () => {})
        root.steps = S
    }
    property int evalsBefore: 0
    property int callsBefore: 0
    property bool second: false
    property int grabbing: 0
    function pic(name) {
        if (!picDir || none) return
        grabbing++
        const ok = stage.grabToImage(r => { r.saveToFile(picDir + "/" + name + ".png"); console.log("ITEST picture " + name); grabbing--; hold = Date.now() + 250 })
        if (!ok) { grabbing--; check("picture " + name, false) }
    }
    property double hold: 0
    property var pendingAfter: null
    Timer {
        interval: 120; running: true; repeat: true
        onTriggered: {
            if (root.grabbing > 0 || Date.now() < root.hold) return
            if (root.busy() || root.quiet > 0) { if (root.quiet > 0) root.quiet--; return }
            if (root.pendingAfter) {
                const a = root.pendingAfter; root.pendingAfter = null
                try { a() } catch (e) { root.failed++; console.log("ITEST FAIL " + root.steps[root.at].name + " threw: " + e) }
                root.quiet = 2          // actions started by `after` need a moment to show as running
                return
            }
            if (++root.at >= root.steps.length) {
                console.log("ITEST RESULT pass " + root.passed + " fail " + root.failed)
                done.start(); stop(); return
            }
            const s = root.steps[root.at]
            console.log("ITEST case: " + s.name)
            try { s.run() } catch (e) { root.failed++; console.log("ITEST FAIL " + s.name + " threw: " + e) }
            root.pendingAfter = s.after
            root.quiet = 2
        }
    }
    Timer { id: done; interval: 300; onTriggered: Qt.quit() }
}
