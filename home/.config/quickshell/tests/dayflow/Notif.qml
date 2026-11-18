// Test stand-in for Notif.qml: Do Not Disturb as a property, every setDnd call recorded.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    property bool dnd: false
    property var calls: []
    function setDnd(on) { calls = calls.concat([on]); if (dnd !== on) dnd = on }
}
