// A group of settings rows under a small title, the Card look of Dashboard.qml.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card
    property string title: ""
    property string note: ""                    // small text at the right of the title
    default property alias content: body.data
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 28
    radius: 14
    color: Theme.tint(Theme.solidBg, Theme.dark ? 0.55 : 0.6)
    border.width: 1
    border.color: Theme.line
    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; leftMargin: 18; rightMargin: 18 }
        spacing: 2
        RowLayout {
            visible: card.title !== ""
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            Text {
                Layout.fillWidth: true
                text: card.title.toUpperCase()
                color: Theme.accent
                font { family: Theme.font; pixelSize: 11; bold: true; letterSpacing: 1.5 }
            }
            Caption { text: card.note; font.pixelSize: 11; elide: Text.ElideRight; Layout.maximumWidth: card.width * 0.6 }
        }
        ColumnLayout { id: body; Layout.fillWidth: true; spacing: 2 }
    }
}
