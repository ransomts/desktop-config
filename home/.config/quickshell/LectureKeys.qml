// Key display (Super+Z then K, qs ipc call lecture keys): the keys and chords being
// pressed, as pills along the bottom of the focused screen, for students to follow.
// ~/.local/bin/lecture-keys reads the keyboards and runs only while this is on; it
// writes nothing and stops after 2 hours. Lecture.qml switches it off when the session
// locks and when presenting ends. Clicks and keys pass through.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: win
    visible: Lecture.keysOn
    screen: {
        const m = Hyprland.focusedMonitor
        return Quickshell.screens.find(s => m && s.name === m.name) || Quickshell.screens[0]
    }
    color: "transparent"
    anchors { left: true; right: true; bottom: true }
    implicitHeight: 160
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-lecture-keys"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    onVisibleChanged: if (!visible) view.reset()

    Process {
        id: reader
        running: Lecture.keysOn
        command: Sys.clean.concat([Sys.bin + "lecture-keys"])
        stdinEnabled: true                  // closed when this stops: the reader exits with it
        stdout: SplitParser { onRead: line => view.push(line) }
        onRunningChanged: {
            if (running || !Lecture.keysOn) return
            if (view.problem !== "") giveUp.restart()       // show why for a few seconds
            else Lecture.keysOff()                          // it stopped by itself (the 2 h limit)
        }
    }
    Timer { id: giveUp; interval: 5000; onTriggered: Lecture.keysOff() }

    LectureKeysView { id: view; anchors.fill: parent }
}
