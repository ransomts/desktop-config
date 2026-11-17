// Notification popups: a stack in the top-right corner of the screen you're on.
// The cards themselves are NotifStack.qml (grouping, badge, snooze and rule menu).
// The window exists only while something is shown: no popups, no cost.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: win
    visible: Notif.shown.length > 0
    screen: {
        const m = Hyprland.focusedMonitor
        return Quickshell.screens.find(s => m && s.name === m.name) || Quickshell.screens[0]
    }
    color: "transparent"
    anchors { top: true; right: true }
    margins { top: 8; right: 8 }
    implicitWidth: 380
    implicitHeight: Math.max(1, stack.implicitHeight)
    exclusionMode: ExclusionMode.Normal       // below the bar
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-notifications"   // blurred by a layer rule in hyprland.lua
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    NotifStack {
        id: stack
        width: 380
    }
}
