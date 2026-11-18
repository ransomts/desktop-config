// Test stand-in for the shell's Sys.qml: only what Health, HealthPill and HealthList read,
// and nothing that touches the real machine (commands are recorded, not run).
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string bin: "/bin-test/"
    readonly property var clean: []
    property var ran: []
    function run(cmd) { ran = ran.concat([cmd]); console.log("HEALTHTEST would run:", cmd) }
    property var tipTarget: null
    property string tipText: ""
    property var tipWindow: null
}
