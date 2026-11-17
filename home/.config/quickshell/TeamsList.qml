// Unread Teams chats (Sys.teams, from teams-unread): newest first, the count on the right
// (accent when you are mentioned). Click a chat to open it in Emacs at its first unread message.
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: list
    signal done()
    spacing: 4
    readonly property var rooms: Sys.teams.data.rooms || []
    Caption { text: list.rooms.length ? "Teams: unread" : "Teams: nothing unread" }
    Repeater {
        model: list.rooms
        Rectangle {
            id: row
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: col.implicitHeight + 12
            radius: 8
            color: tap.containsMouse ? Theme.hover : "transparent"
            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
                spacing: 1
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        elide: Text.ElideRight
                        color: Theme.fg
                        font { family: Theme.font; pixelSize: 13; bold: row.modelData.mentions > 0 }
                    }
                    Text {
                        text: (row.modelData.mentions > 0 ? "@ " : "") + row.modelData.count
                        color: row.modelData.mentions > 0 ? Theme.accent : Theme.faint
                        font { family: Theme.font; pixelSize: 11; bold: row.modelData.mentions > 0 }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: row.modelData.preview || ""
                    elide: Text.ElideRight
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 11 }
                }
            }
            MouseArea {
                id: tap
                anchors.fill: parent
                hoverEnabled: true
                onClicked: { Sys.teamsOpen(row.modelData.id); list.done() }
            }
        }
    }
    MenuRow {
        label: "All chats in Emacs"
        detail: "middle-click"
        onClicked: { Sys.teamsList(); list.done() }
    }
}
