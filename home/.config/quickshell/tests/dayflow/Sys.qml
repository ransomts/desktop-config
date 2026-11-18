// Test stand-in for Sys.qml: a clock and an agenda the cases set, and a launch recorder.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string bin: "/bin-test/"
    readonly property var clean: []
    property var launched: []
    function launch(argv) { launched = launched.concat([argv]) }
    function run(cmd) { launched = launched.concat([["sh", "-c", cmd]]) }
    property string nowHM: "08:00"
    property var today: []
    property bool todayLoaded: true
}
