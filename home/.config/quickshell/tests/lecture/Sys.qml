// Test stand-in for the shell's Sys.qml: only what the lecture tools use, and nothing that
// touches the real machine (commands and sounds are recorded, not run). See shell.qml here.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string bin: (Quickshell.env("LECTURE_TEST_BIN") || "/bin-test") + "/"     // fake scripts from lecture-test
    readonly property var clean: []
    property var ran: []                        // every shell command Lecture tried to run
    property var sounds: []                     // every sound it tried to play
    function run(cmd) { ran = ran.concat([cmd]); console.log("LECTURETEST would run:", cmd) }
    function launch(argv) { ran = ran.concat([argv.join(" ")]) }
    function sound(name) { sounds = sounds.concat([name]) }
}
