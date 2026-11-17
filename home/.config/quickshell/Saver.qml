// The screensaver's windows: one opaque Overlay layer per screen, above every window and the
// bar, existing only while it is up (SaverState.shown, plus the fade-out). The picture is
// SaverView.qml, the logic SaverState.qml. Not in Hyprland's blur list on purpose: it is
// opaque once faded in, so nothing behind it needs blurring.
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property bool primary: modelData.name === SaverState.petScreen
                                            || (SaverState.petScreen === "" && modelData === Quickshell.screens[0])
            visible: SaverState.shown || view.opacity > 0
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qs-saver"
            // the keys on one screen only, and only while it is up (Esc or any key dismisses)
            WlrLayershell.keyboardFocus: SaverState.shown && primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"                // the view fades; the window has nothing of its own
            SaverView {
                id: view
                anchors.fill: parent
                screenObj: win.modelData
                index: Quickshell.screens.indexOf(win.modelData)
            }
        }
    }
}
