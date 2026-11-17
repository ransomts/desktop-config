// Launcher (Super+D): apps you start most come first; type to filter, Up/Down to move,
// Enter to start, Escape or a click outside to close. Apps start through `uwsm app`, like
// the fuzzel launcher this replaced. A prefix (or Tab) switches to another list:
// = calculator, : emoji, v clipboard, w windows, / files, ? keybindings, o Org capture,
// m mail, n notes, t Firefox tabs, and "qr TEXT" for a QR code; the modes are in LaunchView.qml.
//   qs ipc call launcher toggle          apps
//   qs ipc call launcher open PREFIX     straight into a mode (again with the same one closes it);
//                                        used by clip-menu, emoji-picker, window-switcher, keybind-help
//   qs ipc call launcher openWith TEXT   apps with TEXT typed ("event 2026-11-20 " = add an event that day)
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: launcher
    visible: false
    property alias view: view
    property string startMode: "apps"
    function toggle() { startMode = "apps"; visible = !visible }
    function open(prefix) {
        const m = view.modeOf(prefix)
        if (visible && view.mode === m) { visible = false; return }     // the same key again closes it
        startMode = m
        if (visible) view.begin(m)
        else visible = true
    }
    // open on the app list with the query already typed (the calendar popup's "+ Add event" sends "event 2026-11-20 ")
    function openWith(text) {
        startMode = "apps"
        if (visible) view.begin("apps"); else visible = true
        view.queryText = text
    }
    onVisibleChanged: if (visible) view.begin(startMode); else view.end()

    screen: {
        const m = Hyprland.focusedMonitor
        return Quickshell.screens.find(s => m && s.name === m.name) || Quickshell.screens[0]
    }
    color: "transparent"
    implicitWidth: 560
    implicitHeight: 470
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-launcher"     // blurred by a layer rule in hyprland.lua
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    HyprlandFocusGrab {
        windows: [launcher]
        active: launcher.visible
        onCleared: launcher.visible = false
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Theme.panelBg
        border.width: 2
        border.color: Theme.accentBg

        LaunchView {
            id: view
            anchors.fill: parent
            onCloseRequested: launcher.visible = false
        }
    }
}
