pragma Singleton
// Test stand-in for Sys.qml (tests/input): the page only needs bin and clean. bin is the runner's folder
// holding the real input-settings, which talks to the fake hyprctl.
import QtQuick
import Quickshell

Singleton {
    readonly property string bin: Quickshell.env("INPUT_BIN") + "/"
    readonly property var clean: []
    function run(cmd) { }
}
