// One clickable line in a popup list: label on the left, detail on the right.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: row
    property string label
    property string detail: ""
    property bool current: false
    property bool danger: false
    signal clicked()
    Layout.fillWidth: true
    implicitHeight: 30
    radius: 8
    color: current ? Theme.accentBg : tap.containsMouse ? Theme.hover : "transparent"
    RowLayout {
        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
        spacing: 8
        Text {
            Layout.fillWidth: true
            text: row.label
            elide: Text.ElideRight
            color: row.current ? Theme.accentInk : row.danger ? Theme.red : Theme.fg
            font { family: Theme.font; pixelSize: 13 }
        }
        Text {
            visible: row.detail !== ""
            text: row.detail
            color: row.current ? Theme.accentInk : Theme.faint
            font { family: Theme.font; pixelSize: 11 }
        }
    }
    MouseArea { id: tap; anchors.fill: parent; hoverEnabled: true; onClicked: row.clicked() }
}
