// Test stand-in for the shell's Sys.qml: only what Shot*.qml and SharePick*.qml use, and
// nothing that touches the real machine (runs and launches are recorded, not run).
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string bin: "/bin-test/"
    readonly property var clean: []
    property var launched: []
    function launch(argv) { launched = launched.concat([argv]); console.log("SHOTTEST would launch:", JSON.stringify(argv)) }
    function run(cmd) { launched = launched.concat([["sh", "-c", cmd]]); console.log("SHOTTEST would run:", cmd) }
    function sound(name) {}
}
