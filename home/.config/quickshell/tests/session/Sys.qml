// Test stand-in for the shell's Sys.qml: only what Session.qml reads. Programs the scripts start are
// real (session-save / session-restore --status etc. against a fake hyprctl); Sys.launch is recorded, not run.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string bin: Quickshell.env("SESSION_BIN") + "/"
    readonly property var clean: ["env"]
    property var launched: []
    function run(cmd) { }
    function launch(argv) { launched = launched.concat([argv.join(" ")]) }
}
