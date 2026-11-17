// Drop preview: while a tiled window is dragged with the mouse, an outline shows where
// it will land if dropped now. ~/.local/bin/drop-preview works out the spot (and has the
// notes on how Hyprland decides it); this only draws it. Never takes input.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: drop
    property bool enabled: true
    property bool active: false
    property rect zone: Qt.rect(0, 0, 0, 0)       // layout pixels

    Process {
        running: drop.enabled
        command: Sys.clean.concat([Sys.bin + "drop-preview"])
        stdout: SplitParser {
            onRead: line => {
                if (line.charAt(0) === "Z") {
                    const p = line.split(" ")
                    drop.zone = Qt.rect(Number(p[1]), Number(p[2]), Number(p[3]), Number(p[4]))
                    drop.active = true
                } else drop.active = false
            }
        }
        onRunningChanged: if (!running) drop.active = false
    }

    PanelWindow {
        id: win
        readonly property real cx: drop.zone.x + drop.zone.width / 2
        readonly property real cy: drop.zone.y + drop.zone.height / 2
        screen: Quickshell.screens.find(s => win.cx >= s.x && win.cx < s.x + s.width
                                          && win.cy >= s.y && win.cy < s.y + s.height) || Quickshell.screens[0]
        visible: drop.active || box.opacity > 0.01
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-drop-preview"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        Rectangle {
            id: box
            x: drop.zone.x - (win.screen ? win.screen.x : 0)
            y: drop.zone.y - (win.screen ? win.screen.y : 0)
            width: drop.zone.width
            height: drop.zone.height
            radius: 10
            color: Theme.tint(Theme.accentBg, 0.14)
            border.width: 3
            border.color: Theme.accentBg
            opacity: drop.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        }
    }
}
