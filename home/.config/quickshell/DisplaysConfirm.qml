// "Keep this layout?" after Settings > Displays applied one. Covers the whole settings window
// (start() lifts it onto the window's content), so the page cannot be left, the window not
// closed by a click and the search not opened until you choose. Counts down from `seconds`
// and says reverted() at 0; Esc or R is Revert, K (or a click) is Keep. Enter does nothing on
// purpose: a key pressed on a dark screen must not keep a broken layout.
// (display-layout also reverts by itself a few seconds later if nobody answers at all.)
import QtQuick
import QtQuick.Layouts

FocusScope {
    id: dlg
    property int seconds: 15
    property int remaining: seconds
    readonly property bool running: visible
    signal kept()
    signal reverted()
    visible: false
    z: 1000
    function start(host) {
        if (host) parent = host
        anchors.fill = parent
        remaining = seconds
        visible = true
        tick.restart()
        forceActiveFocus()
    }
    function finish(keep) {
        if (!visible) return
        tick.stop()
        visible = false
        if (keep) kept(); else reverted()
    }
    Timer { id: tick; interval: 1000; repeat: true; onTriggered: { dlg.remaining--; if (dlg.remaining <= 0) dlg.finish(false) } }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_R) dlg.finish(false)
        else if (event.key === Qt.Key_K) dlg.finish(true)
        event.accepted = true            // nothing reaches the settings window behind
    }

    Rectangle {                         // the scrim: swallows every click
        anchors.fill: parent
        color: Theme.dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(1, 1, 1, 0.55)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted = true }
    }
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(440, parent.width - 32)
        height: col.implicitHeight + 40
        radius: 16
        color: Theme.solidBg
        border.width: 1
        border.color: Theme.line
        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 10
            Text {
                text: "Keep this layout?"
                color: Theme.fg
                font { family: Theme.font; pixelSize: 18; bold: true }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "The old layout comes back in " + dlg.remaining + (dlg.remaining === 1 ? " second" : " seconds") + " unless you keep this one."
                color: Theme.faint
                font { family: Theme.font; pixelSize: 12 }
            }
            Rectangle {                 // the time left, as a bar that shrinks once a second
                Layout.fillWidth: true
                implicitHeight: 4
                radius: 2
                color: Theme.track
                Rectangle { width: parent.width * dlg.remaining / dlg.seconds; height: parent.height; radius: 2; color: Theme.accentBg }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
                Item { Layout.fillWidth: true }
                SettingsChip { id: revertBtn; label: "Revert (Esc)"; onClicked: dlg.finish(false) }
                SettingsChip { id: keepBtn; label: "Keep (K)"; on: true; onClicked: dlg.finish(true) }
            }
        }
    }
    readonly property alias keepButton: keepBtn
    readonly property alias revertButton: revertBtn
}
