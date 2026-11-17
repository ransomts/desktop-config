// Settings > Input: keyboard, touchpad and pointer. Every value is read live from Hyprland when the page
// opens (input-settings get) and written through input-settings set, which applies it at once with one
// hyprctl eval and records it in ~/.config/shell/input.json so it is re-applied at login. Nothing is
// polled; the page asks only while it is shown. Calls queue, one at a time, so a quick run of clicks
// on a stepper is not lost. The switch/stepper shows the new value at once and is then corrected by the
// read that follows each call.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

SettingsPage {
    id: pg
    pageId: "input"
    title: "Input"
    glyph: "󰌌"
    intro: "Keyboard, touchpad and pointer, applied as you change them and kept for the next login."
    property var vals: ({})                     // input-settings get: the live values
    property var saved: ({})
    property var devSaved: ({})                 // { deviceName: { sensitivity, layout } }
    property var devices: []                    // [{ name, kind: touchpad | mouse | keyboard, system }]
    property string layoutKey: "Super+Space"
    property bool loaded: false
    property string error: ""
    property var queue: []
    readonly property var pointers: devices.filter(d => d.kind === "mouse")
    readonly property var pads: devices.filter(d => d.kind === "touchpad")
    readonly property var keyboards: devices.filter(d => d.kind === "keyboard" && !d.system)
    readonly property var moonlanders: devices.filter(d => d.kind === "keyboard" && /moonlander/i.test(d.name))
    readonly property int systemKeys: devices.filter(d => d.kind === "keyboard" && d.system).length
    readonly property alias getter: getProc
    readonly property alias setter: setProc

    function refresh() { if (!getProc.running && !setProc.running && queue.length === 0) getProc.running = true }
    onShownChanged: if (shown) refresh()
    Component.onCompleted: if (shown) refresh()
    function v(k, fallback) { return vals[k] === undefined ? fallback : vals[k] }
    function devVal(name, field, fallback) { const d = devSaved[name]; return d && d[field] !== undefined ? d[field] : fallback }

    function enqueue(args) { queue = queue.concat([args]); pump() }
    function pump() {
        if (setProc.running || queue.length === 0) return
        setProc.command = Sys.clean.concat([Sys.bin + "input-settings"], queue[0])
        queue = queue.slice(1)
        setProc.running = true
    }
    function put(key, value) {                  // one global option
        const o = {}; o[key] = value
        vals = Object.assign({}, vals, o)
        enqueue(["set", key, String(value)])
    }
    function putDev(names, field, value) {      // one field on one or more devices
        for (const n of names) {
            const d = Object.assign({}, devSaved[n] || {}); d[field] = value
            const all = Object.assign({}, devSaved); all[n] = d; devSaved = all
            enqueue(["set", "device:" + n + ":" + field, String(value)])
        }
    }
    function resetAll() { vals = ({}); enqueue(["reset", "all"]) }

    Process {
        id: getProc
        command: Sys.clean.concat([Sys.bin + "input-settings", "get"])
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    pg.vals = d.values || {}; pg.saved = d.saved || {}; pg.devSaved = d.deviceSaved || {}
                    pg.devices = d.devices || []; pg.layoutKey = d.layoutKey || "Super+Space"
                } catch (e) { pg.error = "Could not read the current values" }
                pg.loaded = true
            }
        }
    }
    Process {
        id: setProc
        stderr: StdioCollector { id: setErr; onStreamFinished: pg.error = text.trim().split("\n").pop() }
        onRunningChanged: if (!running) { if (pg.queue.length) pg.pump(); else pg.refresh() }
        onStarted: pg.error = ""
    }

    SettingsCard {
        title: "Keyboard"
        enabled: pg.loaded
        SettingsStepper {
            label: "Key repeat rate"
            sub: "Characters per second while a key is held"
            keywords: "keyboard repeat rate speed typing"
            value: pg.v("repeat_rate", 25); from: 1; to: 100; stepSize: 5; suffix: " /s"
            onEdited: x => pg.put("repeat_rate", Math.round(x))
        }
        SettingsStepper {
            label: "Key repeat delay"
            sub: "How long a key is held before it repeats"
            keywords: "keyboard repeat delay wait"
            value: pg.v("repeat_delay", 600); from: 100; to: 2000; stepSize: 50; suffix: " ms"
            onEdited: x => pg.put("repeat_delay", Math.round(x))
        }
        SettingsSwitch {
            label: "Num Lock on at start"
            sub: "Takes effect for keyboards connected after the change"
            keywords: "keyboard numlock numpad"
            checked: pg.v("numlock_by_default", false)
            onEdited: on => pg.put("numlock_by_default", on)
        }
        SettingsChoice {
            label: "First layout"
            sub: "The laptop keyboard types this one until you switch"
            keywords: "keyboard layout dvorak us qwerty"
            options: [["dvorak", "Dvorak"], ["us", "US"]]
            value: pg.v("first_layout", "dvorak")
            onEdited: x => pg.put("first_layout", x)
        }
        SettingsInfo {
            label: "Switch layout"
            sub: "Alt+Shift does not switch, on purpose"
            keywords: "keyboard layout switch key"
            value: pg.layoutKey
        }
        SettingsChoice {
            visible: pg.moonlanders.length > 0
            label: "Moonlander layout"
            sub: "Firmware: it types Dvorak itself and Hyprland reads plain US. Software: Hyprland applies Dvorak to it"
            keywords: "keyboard moonlander zsa layout dvorak firmware"
            wrapWidth: 300
            options: [["us", "Firmware"], ["dvorak", "Software"]]
            value: pg.moonlanders.length ? pg.devVal(pg.moonlanders[0].name, "layout", "us") : "us"
            onEdited: x => pg.putDev(pg.moonlanders.map(d => d.name), "layout", x)
        }
        SettingsRow {
            label: "Try it here"
            sub: "Hold a key to feel the repeat rate and delay"
            keywords: "keyboard test try repeat"
            below: true
            takesFocus: false
            Rectangle {
                width: parent.width; height: 34; radius: 8
                color: Theme.track
                border.width: tryInput.activeFocus ? 2 : 1
                border.color: tryInput.activeFocus ? Theme.accentBg : Theme.line
                TextInput {
                    id: tryInput
                    objectName: "tryInput"
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    clip: true
                    selectionColor: Theme.hover
                    font { family: Theme.font; pixelSize: 14 }
                    Text { visible: !tryInput.text && !tryInput.activeFocus; anchors.verticalCenter: parent.verticalCenter; text: "Click here, then hold a key"; color: Theme.faint; font: tryInput.font }
                }
            }
        }
    }

    SettingsCard {
        title: "Touchpad"
        enabled: pg.loaded
        SettingsSwitch {
            label: "Tap to click"
            keywords: "touchpad tap click"
            checked: pg.v("touchpad.tap_to_click", true)
            onEdited: on => pg.put("touchpad.tap_to_click", on)
        }
        SettingsSwitch {
            label: "Tap and drag"
            sub: "Tap, then touch again and drag"
            keywords: "touchpad tap drag"
            checked: pg.v("touchpad.tap_and_drag", true)
            onEdited: on => pg.put("touchpad.tap_and_drag", on)
        }
        SettingsSwitch {
            label: "Pause while typing"
            sub: "The pad ignores touches while a key is down and just after"
            keywords: "touchpad disable while typing palm"
            checked: pg.v("touchpad.disable_while_typing", true)
            onEdited: on => pg.put("touchpad.disable_while_typing", on)
        }
        SettingsSwitch {
            label: "Middle click by tapping left and right together"
            keywords: "touchpad middle button emulation"
            checked: pg.v("touchpad.middle_button_emulation", false)
            onEdited: on => pg.put("touchpad.middle_button_emulation", on)
        }
        SettingsSwitch {
            label: "Click by number of fingers"
            sub: "One finger left, two right, three middle, wherever you press"
            keywords: "touchpad clickfinger fingers right click"
            checked: pg.v("touchpad.clickfinger_behavior", false)
            onEdited: on => pg.put("touchpad.clickfinger_behavior", on)
        }
        SettingsSwitch {
            label: "Natural scrolling"
            sub: "Content follows your fingers"
            keywords: "touchpad natural scroll direction reverse"
            checked: pg.v("touchpad.natural_scroll", true)
            onEdited: on => pg.put("touchpad.natural_scroll", on)
        }
        SettingsStepper {
            label: "Scroll speed"
            keywords: "touchpad scroll factor speed"
            value: pg.v("touchpad.scroll_factor", 1); from: 0.1; to: 10; stepSize: 0.1; suffix: "×"
            onEdited: x => pg.put("touchpad.scroll_factor", x)
        }
    }

    SettingsCard {
        title: "Mouse and trackball"
        enabled: pg.loaded
        SettingsStepper {
            label: "Pointer speed"
            sub: "-1 slowest, 0 as the device reports, 1 fastest. Touchpad included"
            keywords: "mouse pointer sensitivity speed trackball"
            value: pg.v("sensitivity", 0); from: -1; to: 1; stepSize: 0.1
            onEdited: x => pg.put("sensitivity", x)
        }
        SettingsChoice {
            label: "Acceleration"
            sub: "Adaptive speeds up with a fast hand; flat is the same at any speed"
            keywords: "mouse accel acceleration profile flat adaptive"
            options: [["adaptive", "Adaptive"], ["flat", "Flat"]]
            value: pg.v("accel_profile", "adaptive")
            onEdited: x => pg.put("accel_profile", x)
        }
        SettingsSwitch {
            label: "Natural scrolling"
            sub: "Mouse wheel and trackball; the touchpad has its own above"
            keywords: "mouse natural scroll direction reverse wheel"
            checked: pg.v("natural_scroll", false)
            onEdited: on => pg.put("natural_scroll", on)
        }
        SettingsStepper {
            label: "Scroll speed"
            keywords: "mouse scroll factor speed wheel"
            value: pg.v("scroll_factor", 1); from: 0.1; to: 10; stepSize: 0.1; suffix: "×"
            onEdited: x => pg.put("scroll_factor", x)
        }
        SettingsChoice {
            label: "Focus"
            sub: "Hover: the window under the pointer is focused. Click: only a click focuses"
            keywords: "mouse follow focus hover click window"
            wrapWidth: 330
            options: [[1, "Hover"], [0, "Click"], [2, "Click, pointer free"], [3, "Click, loose"]]
            value: pg.v("follow_mouse", 1)
            onEdited: x => pg.put("follow_mouse", x)
        }
        Repeater {
            model: pg.pointers
            SettingsStepper {
                required property var modelData
                label: modelData.name + " speed"
                sub: "This device only, in place of the speed above"
                keywords: "mouse trackball device pointer speed " + modelData.name
                value: pg.devVal(modelData.name, "sensitivity", 0); from: -1; to: 1; stepSize: 0.1
                onEdited: x => pg.putDev([modelData.name], "sensitivity", x)
            }
        }
        SettingsRow {
            label: "Try it here"
            sub: pg.tryNote
            keywords: "mouse scroll direction test try"
            below: true
            takesFocus: false
            Rectangle {
                width: parent.width; height: 96; radius: 8
                color: Theme.track; border.width: 1; border.color: Theme.line
                clip: true
                Flickable {
                    id: tryScroll
                    objectName: "tryScroll"
                    anchors.fill: parent
                    contentWidth: width; contentHeight: 520
                    boundsBehavior: Flickable.StopAtBounds
                    property real last: 0
                    onContentYChanged: { if (contentY > last) pg.tryNote = "Scrolled down: content moved up"; else if (contentY < last) pg.tryNote = "Scrolled up: content moved down"; last = contentY }
                    Column {
                        width: parent.width
                        Repeater {
                            model: 26
                            Text { required property int index; width: parent.width; height: 20; leftPadding: 10; text: (index + 1) + "  scroll here"; color: index % 5 === 0 ? Theme.accent : Theme.faint; font { family: Theme.font; pixelSize: 12 } }
                        }
                    }
                }
            }
        }
    }
    property string tryNote: "Scroll in the box to see which way the content moves"

    SettingsCard {
        title: "Devices"
        note: "as Hyprland names them"
        Repeater {
            model: pg.keyboards.concat(pg.pointers, pg.pads)
            SettingsInfo {
                required property var modelData
                label: modelData.name
                value: modelData.kind === "keyboard" ? "keyboard" : modelData.kind
                keywords: "devices " + modelData.kind
            }
        }
        SettingsInfo {
            visible: pg.systemKeys > 0
            label: "Other key devices"
            value: pg.systemKeys + " (buttons, lid, hotkeys)"
        }
        SettingsInfo {
            visible: pg.error !== ""
            label: "Last problem"
            value: pg.error
        }
    }

    SettingsCard {
        title: "Reset"
        SettingsButton {
            text: "Reset to defaults"
            confirm: "puts every option on this page back to the hyprland.lua values"
            label: "Reset input settings"
            sub: "Forgets the saved changes (input.json)"
            keywords: "input reset defaults"
            onClicked: pg.resetAll()
        }
    }
}
