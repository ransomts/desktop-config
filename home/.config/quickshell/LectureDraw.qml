// Draw on the screen (Super+Z then D, qs ipc call lecture draw): a full-screen overlay on
// the screen that had focus when it opened, holding the keyboard and mouse while drawing.
// Tab "holds": the ink stays on screen but the window takes no input (empty mask, no
// keyboard) until draw is toggled again. Esc leaves and clears. LectureDrawView.qml has
// the keys, the toolbar and the ink.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: win
    visible: shown
    property bool shown: false          // set after the screen is picked, so it opens there
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-lecture-draw"
    WlrLayershell.keyboardFocus: Lecture.hold ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
    // drawing: the whole window takes input; held: none of it does
    mask: Region { item: Lecture.hold ? null : view }

    // the screen is chosen when drawing starts and kept until it ends
    property string screenName: ""
    screen: Quickshell.screens.find(s => s.name === screenName) || Quickshell.screens[0]
    Connections {
        target: Lecture
        function onDrawOnChanged() {
            if (!Lecture.drawOn) { win.shown = false; return }
            const m = Hyprland.focusedMonitor
            win.screenName = m ? m.name : ""
            win.shown = true
        }
        function onHoldChanged() { if (!Lecture.hold) view.focusKeys() }
    }
    onVisibleChanged: if (visible) view.focusKeys()

    LectureDrawView { id: view; anchors.fill: parent }
}
