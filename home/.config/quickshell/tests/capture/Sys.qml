// Test stand-in for the shell's Sys.qml: only what the webcam bubble reads, nothing that
// touches the real machine. See tests/capture/shell.qml.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string bin: "/nonexistent/"
    readonly property var clean: []
    property var ran: []
    function run(cmd) { ran = ran.concat([cmd]); console.log("CTEST would run:", cmd) }
}
