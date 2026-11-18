pragma Singleton
// Test stand-in for PetFocus.qml (tests/qml-overlays).
import QtQuick
import Quickshell

Singleton {
    property int doneToday: 0
    property bool cycle: false
    property int round: 1
}
