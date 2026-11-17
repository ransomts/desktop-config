// The list under the bell pill (Super+N): recent notifications grouped by app, newest
// group first (NotifGroups.qml), with the Do Not Disturb switch and Clear on top. Ones
// that arrived since the list was last looked at carry an orange edge; opening the list
// marks them seen (the count on the pill goes away). c clears all (Bar.qml handles the
// key: it sets `fresh` to 0 and calls Notif.clear()). Snoozed ones are counted at the
// bottom; "Bring back" delivers them now.
import QtQuick
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: list
    property int fresh: 0                   // how many at the top were unseen when the list opened
    property bool all: false                // six groups, or every one
    readonly property int cap: all ? 40 : 6
    spacing: 8

    function take() { if (Notif.unseen > 0) { fresh += Notif.unseen; Notif.markSeen() } }
    Component.onCompleted: take()
    Connections { target: Notif; function onHistoryChanged() { list.take() } }     // one arrives while the list is open

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Text {
            Layout.fillWidth: true
            text: "Notifications"
            color: Theme.fg
            font { family: Theme.font; pixelSize: 14; bold: true }
        }
        Rectangle {     // Do Not Disturb switch
            implicitWidth: dndLabel.implicitWidth + 18
            implicitHeight: 24
            radius: 8
            color: Notif.dnd ? Theme.accentBg : dndTap.containsMouse ? Theme.hover : Theme.track
            Text {
                id: dndLabel
                anchors.centerIn: parent
                text: (Notif.dnd ? Icons.bellOff : Icons.bell) + (Notif.dnd ? " Silenced" : " Silence")
                color: Notif.dnd ? Theme.accentInk : Theme.fg
                font { family: Theme.font; pixelSize: 11 }
            }
            MouseArea { id: dndTap; anchors.fill: parent; hoverEnabled: true; onClicked: Notif.setDnd(!Notif.dnd) }
        }
        Caption {
            visible: Notif.history.length > 0
            text: "Clear (c)"
            color: clearTap.containsMouse ? Theme.accent : Theme.faint
            MouseArea { id: clearTap; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: { list.fresh = 0; Notif.clear() } }
        }
    }

    Caption {
        visible: Notif.history.length === 0
        Layout.topMargin: 6
        Layout.bottomMargin: 6
        text: "Nothing here"
    }
    Caption {
        visible: Notif.dnd
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: "Do Not Disturb is on: only critical notifications pop up, the rest land here."
    }

    NotifGroups {
        id: groups
        Layout.fillWidth: true
        limit: list.cap
        fresh: list.fresh
        onRemoving: indices => { list.fresh -= indices.filter(i => i < list.fresh).length }
    }

    Caption {
        visible: Notif.groups.length > 6
        Layout.alignment: Qt.AlignHCenter
        text: list.all ? "Fewer" : "All " + Notif.groups.length + " apps (" + Notif.history.length + ")"
        color: moreTap.containsMouse ? Theme.accent : Theme.faint
        MouseArea { id: moreTap; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: list.all = !list.all }
    }
    Caption {
        visible: Notif.snoozed.length > 0
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: Icons.clock + " " + Notif.snoozed.length + " snoozed, next back "
              + (Notif.nextDue > 0 ? Qt.formatDateTime(new Date(Notif.nextDue), new Date(Notif.nextDue).toDateString() === new Date().toDateString() ? "HH:mm" : "ddd HH:mm") : "")
              + ".  Bring back"
        color: wakeTap.containsMouse ? Theme.accent : Theme.faint
        MouseArea { id: wakeTap; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: Notif.wakeSnoozed() }
    }
}
