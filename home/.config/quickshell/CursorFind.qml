// Shake to find the pointer: shake the mouse and a large pointer grows at the
// cursor, then shrinks away when the shaking stops.
// ~/.local/bin/cursor-shake watches the position and reports shakes; this draws
// the pointer on the screen under the cursor. The window never takes input.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: find
    property bool enabled: true
    property bool shaking: false
    property real px: 0                 // pointer, layout pixels
    property real py: 0
    readonly property int big: 150      // px the pointer grows to
    // qs ipc call cursor flash X Y: show the big pointer there for a second (testing)
    function flash(x, y) { px = x; py = y; shaking = true; flashOff.restart() }
    Timer { id: flashOff; interval: 1000; onTriggered: find.shaking = false }

    Process {
        running: find.enabled
        command: Sys.clean.concat([Sys.bin + "cursor-shake"])
        stdout: SplitParser {
            onRead: line => {
                if (line.charAt(0) === "S") {
                    const p = line.split(" ")
                    find.px = Number(p[1]); find.py = Number(p[2]); find.shaking = true
                } else find.shaking = false
            }
        }
        onRunningChanged: if (!running) find.shaking = false
    }

    PanelWindow {
        id: win
        screen: Quickshell.screens.find(s => find.px >= s.x && find.px < s.x + s.width
                                          && find.py >= s.y && find.py < s.y + s.height) || Quickshell.screens[0]
        visible: find.shaking || arrow.size > 25
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-cursor-find"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}                 // clicks pass straight through

        Image {
            id: arrow
            // the theme's 96px arrow; its tip (hotspot) is at 15,5 of 96
            property real size: find.shaking ? find.big : 24
            Behavior on size { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            source: Qt.resolvedUrl("assets/cursor-big.png")   // 480px, redrawn sharp from the theme arrow
            width: size; height: size
            smooth: true; mipmap: true
            x: find.px - (win.screen ? win.screen.x : 0) - size * 15 / 96        // image is 480px, same proportions
            y: find.py - (win.screen ? win.screen.y : 0) - size * 5 / 96
        }
    }
}
