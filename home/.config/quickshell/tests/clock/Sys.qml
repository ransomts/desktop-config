pragma Singleton
// Test stand-in for Sys.qml (tests/clock): what the clock tools use, recording every command and sound.
import QtQuick
import Quickshell

Singleton {
    readonly property string bin: Quickshell.env("CLOCK_BIN") + "/"
    readonly property var clean: []
    property bool sounds: true
    property string nowHM: "10:00"
    property var today: []
    property var runs: []                       // every shell command Sys.run was given
    property var played: []                     // every sound name
    function run(cmd) { runs = runs.concat([cmd]) }
    function launch(argv) { runs = runs.concat([argv.join(" ")]) }
    function sound(name) { played = played.concat([name]) }
    function forget() { runs = []; played = [] }
}
