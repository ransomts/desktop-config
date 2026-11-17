// A two-line on/off tile for the control panel.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: t
    property string label
    property string caption
    property bool on: false
    signal clicked()
    Layout.fillWidth: true
    implicitHeight: 58
    radius: 10
    color: on ? Theme.accentBg : (area.containsMouse ? Theme.hover : Theme.track)
    Behavior on color { ColorAnimation { duration: 120 } }
    Column {
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 2
        Text {
            text: t.caption
            color: t.on ? Theme.accentInk : Theme.faint
            font { family: Theme.font; pixelSize: 11 }
        }
        Text {
            text: t.label
            width: t.width - 24
            elide: Text.ElideRight
            color: t.on ? Theme.accentInk : Theme.fg
            font { family: Theme.font; pixelSize: 14; bold: true }
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: t.clicked()
    }
}
