// Webcam bubble: a round, mirrored camera picture over everything, for screen recordings
// (screen-record --cam) and calls. Off by default; qs ipc call cam toggle | on | off | size PX | status.
// It shows on the screen that has focus when it is turned on (turn it on again to bring it to
// another screen). The window covers the screen but takes input only on the bubble (an
// elliptic mask), so the rest of the screen stays click-through. See CamState.qml for the
// camera feed (on only while shown) and CamView.qml for dragging and resizing.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: win
    visible: CamState.shown
    screen: Quickshell.screens.find(s => s.name === CamState.screenName) || Quickshell.screens[0]
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-cam"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {
        x: view.bubble.x; y: view.bubble.y
        width: view.bubble.width; height: view.bubble.height
        shape: RegionShape.Ellipse
    }

    CamView { id: view; anchors.fill: parent }
}
