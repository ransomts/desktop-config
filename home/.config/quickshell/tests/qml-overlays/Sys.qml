pragma Singleton
// Test stand-in for Sys.qml (tests/qml-overlays): what the overlays (Overview, Switcher, Dashboard,
// CursorFind, DropPreview, WallState, PetSay, PetAntics) read. run() and launch() are recorded, never
// run; bin is the runner's folder of stand-in scripts (dashboard-data, cursor-shake, drop-preview).
import QtQuick
import Quickshell

Singleton {
    id: sys
    readonly property string bin: Quickshell.env("QO_BIN") + "/"
    readonly property var clean: []
    property var calls: []
    function rec(what) { calls = calls.concat([what]) }
    function run(cmd) { rec("run " + cmd) }
    function launch(argv) { rec("launch " + argv.join(" ")) }
    function reset() { calls = [] }

    // desktops: monitorOrder as the real Sys (slot = place in the list, from 1)
    property var monitorOrder: ["eDP-1", "DP-3"]
    function slotOf(name) { return monitorOrder.indexOf(name) + 1 }
    property int desktop: 1
    function goDesktop(n) { rec("goDesktop " + n) }

    function readBrightness() { rec("readBrightness") }
    property var tipTarget: null
    signal popupRequest(string name)
    onPopupRequest: name => rec("popup " + name)

    // calendar, as Sys keeps it from agenda-day
    property string nowHM: "10:30"
    property var today: []
    property var currentEvent: null
    property var nextEvent: null
    property string netKind: "wifi"
    property string netName: "eduroam"

    // the player the bar would show (null: nothing playing)
    property QtObject fakePlayer: QtObject {
        property string trackTitle: "Blue in Green"
        property string trackArtist: "Miles Davis"
        property string trackArtUrl: ""
        property string identity: "Music Player Daemon"
        property bool isPlaying: true
        property bool canTogglePlaying: true
        property bool canGoNext: true
        property bool canGoPrevious: true
        function togglePlaying() { sys.rec("player toggle"); isPlaying = !isPlaying }
        function next() { sys.rec("player next") }
        function previous() { sys.rec("player previous") }
    }
    property var player: null
}
