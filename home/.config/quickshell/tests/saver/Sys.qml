// Test stand-in for the shell's Sys.qml: only what the screensaver reads, and nothing that
// touches the real machine. See tests/saver/shell.qml.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string bin: "/nonexistent/"
    readonly property var clean: []
    function run(cmd) { console.log("SAVERTEST would run:", cmd) }
    property bool videoInUse: false
    property bool keepAwake: false
    readonly property int desktop: 1
}
