// Level popup for the media keys (volume, brightness, mic, airplane, touchpad).
// ~/.local/bin/osd calls:  qs ipc call osd level KIND TEXT PERCENT   (-1 = no bar)
// Drawn here rather than as a mako notification, so Do Not Disturb doesn't hide it.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: osd
    property string kind: ""
    property string label: ""
    property int pct: -1

    function show(k, text, percent) {
        kind = k; label = text; pct = percent
        visible = true
        if (k === "vol") Sys.sound("audio-volume-change")
        hide.restart()
    }

    readonly property string glyph: {
        const off = /mute|off/i.test(label)
        if (kind === "vol") return off ? Icons.volMuted : pct < 34 ? Icons.volLow : pct < 67 ? Icons.volMid : Icons.volHigh
        if (kind === "mic") return off ? Icons.micMuted : Icons.mic
        if (kind === "bright") return "☀"
        return ""
    }

    visible: false
    // on the screen you're working on
    screen: {
        const m = Hyprland.focusedMonitor
        return Quickshell.screens.find(s => m && s.name === m.name) || Quickshell.screens[0]
    }
    color: "transparent"
    anchors.bottom: true
    margins.bottom: 90
    implicitWidth: 300
    implicitHeight: pct >= 0 ? 66 : 46
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-osd"        // blurred by a layer rule in hyprland.lua
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}                           // clicks pass straight through

    Timer { id: hide; interval: 1500; onTriggered: osd.visible = false }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Theme.panelBg
        border.width: 2
        border.color: Theme.accentBg

        Column {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 }
            spacing: 9
            Row {
                spacing: 10
                Text {
                    visible: osd.glyph !== ""
                    text: osd.glyph
                    color: Theme.accent
                    font { family: Theme.font; pixelSize: 16 }
                }
                Text {
                    text: osd.label
                    color: Theme.fg
                    font { family: Theme.font; pixelSize: 14 }
                }
            }
            Rectangle {
                visible: osd.pct >= 0
                width: parent.width
                height: 8
                radius: 4
                color: Theme.track
                Rectangle {
                    width: Math.max(parent.height, parent.width * Math.min(100, osd.pct) / 100)
                    height: parent.height
                    radius: parent.radius
                    color: /mute/i.test(osd.label) ? Theme.dim : Theme.accentBg
                    Behavior on width { NumberAnimation { duration: 90 } }
                }
            }
        }
    }
}
