// Test stand-in for Sys.qml: scripts come from a test folder, the call and clock are set by the cases.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string bin: Quickshell.env("POWER_TEST_BIN") + "/"
    readonly property var clean: []
    property var launched: []
    function launch(argv) { launched = launched.concat([argv]) }
    function run(cmd) { launched = launched.concat([["sh", "-c", cmd]]) }
    property string nowHM: "08:00"
    property bool panelOpen: false
    property bool micInUse: false
    property bool videoInUse: false
}
