// Test stand-in for the shell's Sys.qml: only what Notif.qml and the notification views
// read, and nothing that touches the real machine (no sounds, nothing run). See tests/notify/shell.qml.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string bin: "/nonexistent/"
    readonly property var clean: []
    property int sounds: 0
    property string lastSound: ""
    property int refreshes: 0
    property string nowHM: "12:00"
    function sound(name) { sounds++; lastSound = name }
    function refreshSoon() { refreshes++ }
    function run(cmd) {}
    function launch(argv) {}
}
