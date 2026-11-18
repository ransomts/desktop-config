// Test stand-in for the shell's Sys.qml: only what WallAgenda reads, and nothing that
// touches the real machine (launches are recorded, not run). See tests/agenda/shell.qml.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string bin: "/bin-test/"
    readonly property var clean: []
    property var launched: []                   // every argv WallAgenda tried to start
    function launch(argv) { launched = launched.concat([argv]); console.log("AGENDATEST would launch:", JSON.stringify(argv)) }
    property string nowHM: "10:00"
    property var today: []
}
