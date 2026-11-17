// Spotlight (Super+Z then L, qs ipc call lecture spot): every screen dimmed except a soft
// circle around the pointer. Clicks and keys pass through. The pointer comes from
// ~/.local/bin/cursor-track ("x y" lines, about 30 a second while it moves), which runs
// only while the spotlight is on. Size: qs ipc call lecture spotsize PX (radius).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: spot
    property real px: -1e5                  // pointer, layout pixels
    property real py: -1e5
    readonly property var windows: perScreen.instances

    Process {
        running: Lecture.spotOn
        command: Sys.clean.concat([Sys.bin + "cursor-track"])
        stdinEnabled: true                  // closed when this stops: the script exits with it
        stdout: SplitParser {
            onRead: line => {
                const p = line.split(" ")
                if (p.length === 2) { spot.px = Number(p[0]); spot.py = Number(p[1]) }
            }
        }
        onRunningChanged: if (!running) { spot.px = -1e5; spot.py = -1e5 }
    }

    Variants {
        id: perScreen
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: Lecture.spotOn
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qs-lecture-spot"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}                 // clicks pass straight through

            LectureSpotView {
                anchors.fill: parent
                px: spot.px - win.modelData.x
                py: spot.py - win.modelData.y
            }
        }
    }
}
