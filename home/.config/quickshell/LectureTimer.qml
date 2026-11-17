// Lecture timer (qs ipc call lecture timer MINUTES LABEL, or the lecture menu): a big
// countdown in the top-right corner (under the bar, clear of the
// draw toolbar and the key display at the bottom) of the screen that had focus when it started.
// Clicks pass through everywhere but the timer itself: point at it for Pause / Reset / Stop. LectureTimerView.qml draws it and keeps time.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: win
    visible: shown
    property bool shown: false          // set after the screen is picked, so it opens there
    property string screenName: ""
    screen: Quickshell.screens.find(s => s.name === screenName) || Quickshell.screens[0]
    Connections {
        target: Lecture
        function onTimerEndChanged() {
            if (Lecture.timerEnd <= 0) { win.shown = false; return }
            if (win.shown) return               // a new length while showing: stay on that screen
            const m = Hyprland.focusedMonitor
            win.screenName = m ? m.name : ""
            win.shown = true
        }
    }
    color: "transparent"
    anchors { right: true; top: true }
    margins { right: 24; top: 54 }
    implicitWidth: view.implicitWidth
    implicitHeight: view.implicitHeight
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-lecture-timer"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: view }

    LectureTimerView { id: view }
}
