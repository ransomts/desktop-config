// A lit-when-on button, the Chip look of WallMenu.qml, as wide as its text (or `fixedWidth`).
import QtQuick

Rectangle {
    id: chip
    property string label
    property bool on: false
    property bool cursor: false                 // the keyboard's place in a row of chips
    property real fixedWidth: 0
    property int textSize: 12
    property color tone: "transparent"         // a fill of its own (an armed button)
    signal clicked()
    implicitWidth: fixedWidth > 0 ? fixedWidth : Math.max(34, t.implicitWidth + 22)
    implicitHeight: 30
    radius: 8
    color: tone.a > 0 ? tone : on ? Theme.accentBg : (tap.containsMouse ? Theme.hover : Theme.track)
    border.width: cursor ? 2 : 0
    border.color: on ? Theme.fg : Theme.accentBg
    Behavior on color { ColorAnimation { duration: 120 } }
    Text {
        id: t
        anchors.centerIn: parent
        width: Math.min(implicitWidth, chip.width - 8)
        elide: Text.ElideRight
        text: chip.label
        color: chip.on ? Theme.accentInk : Theme.fg
        font { family: Theme.font; pixelSize: chip.textSize; bold: chip.on }
    }
    MouseArea { id: tap; anchors.fill: parent; hoverEnabled: true; onClicked: chip.clicked() }
}
