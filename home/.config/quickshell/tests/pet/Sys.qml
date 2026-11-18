// Test stand-in for the shell's Sys.qml: only what the pet reads, and nothing that
// touches the real machine (commands are logged, not run). See tests/pet/shell.qml.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string bin: "/nonexistent/"
    readonly property var clean: []
    property var ran: []                        // every command the pet tried to run
    function run(cmd) { ran = ran.concat([cmd]); console.log("PETTEST would run:", cmd) }
    property bool sounds: true
    property double lastSound: 0
    function sound(name) { }
    signal popupRequest(string name)

    property string nowHM: "14:00"              // mid-afternoon: awake whatever the real time is
    property var today: []
    property var nextEvent: null
    property var currentEvent: null
    property var player: null
    property string netKind: "wifi"
    property string netName: "test"
    property bool videoInUse: false
    readonly property int desktop: 1

    property Item tipTarget: null
    property string tipText: ""
    property var tipWindow: null
}
