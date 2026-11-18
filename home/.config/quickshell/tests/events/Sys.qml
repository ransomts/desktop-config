// Test stand-in for the shell's Sys.qml: what LaunchView, EventQuick and Calendar use. Commands are
// recorded, not run. `bin` is the real bin directory under test ($EVENTS_TEST_BIN) so EventQuick can
// run the real `quick-event parse` in one case. See tests/events/shell.qml.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string bin: Quickshell.env("EVENTS_TEST_BIN") + "/"
    readonly property var clean: ["env"]
    property var ran: []                        // every shell string passed to run()
    property var launched: []                   // every argv passed to launch()
    function run(cmd) { ran = ran.concat([cmd]) }
    function launch(argv) { launched = launched.concat([argv]) }
    property int emacsFocused: 0
    function focusEmacs() { emacsFocused++ }
    function reset() { ran = []; launched = []; emacsFocused = 0 }
    property var today: []
    property string nowHM: "10:36"
}
