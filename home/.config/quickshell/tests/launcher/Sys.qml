// Test stand-in for the shell's Sys.qml: only what the launcher and the pick list use, and
// nothing that touches the real machine (run and launch are recorded, not run).
// See tests/launcher/shell.qml.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string bin: "/bin-test/"
    readonly property var clean: []
    property var ran: []                        // every shell string passed to run()
    property var launched: []                   // every argv passed to launch()
    function run(cmd) { ran = ran.concat([cmd]) }
    function launch(argv) { launched = launched.concat([argv]) }
    property int emacsFocused: 0                // times focusEmacs() was called
    function focusEmacs() { emacsFocused++ }
    function reset() { ran = []; launched = []; emacsFocused = 0 }
}
