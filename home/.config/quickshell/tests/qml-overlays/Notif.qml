pragma Singleton
// Test stand-in for Notif.qml (tests/qml-overlays): Do Not Disturb, the recent list, unseen count.
import QtQuick
import Quickshell

Singleton {
    property bool dnd: false
    property var history: []
    property int unseen: 0
}
