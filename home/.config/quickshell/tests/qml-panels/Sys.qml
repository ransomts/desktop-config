pragma Singleton
// Test stand-in for Sys.qml (qml-panels-test): the settings stub of tests/settings (copied, same
// members) plus what the bar's popups read: sink/source, netKind/netName, teams, player, profile.
// run() and launch() are recorded, never run; bin is the runner's folder of stand-in scripts.
import QtQuick
import Quickshell

Singleton {
    id: sys
    readonly property string bin: Quickshell.env("PANELS_BIN") + "/"
    readonly property var clean: []
    property var calls: []
    function rec(what) { calls = calls.concat([what]) }
    function run(cmd) { rec("run " + cmd) }
    function launch(argv) { rec("launch " + argv.join(" ")) }
    function reset() { calls = [] }
    function sound(name) { rec("sound " + name) }

    // ---- as the settings stub ----
    property bool barVisible: true
    property bool sounds: true
    function setSounds(on) { rec("setSounds " + on); sounds = on }
    property bool keepAwake: false
    property var tail: ({ cls: "off", text: "" })
    function setTailscale(on) { rec("setTailscale " + on); tail = { cls: on ? "on" : "off", text: "" } }
    property int nightK: 6000
    readonly property bool night: nightK < 5900
    property int nightWanted: 4500
    function readNight() { rec("readNight") }
    function setNight(k) { rec("setNight " + k); nightK = k }
    property string nowHM: Qt.formatTime(new Date(), "HH:mm")
    property int desktop: 1
    function goDesktop(n) { rec("goDesktop " + n); desktop = n }
    signal popupRequest(string name)
    onPopupRequest: name => rec("popup " + name)

    // ---- the popups ----
    property var sink: null                 // a node from the test's Pipewire stub
    property var source: null
    property string netKind: "wifi"
    property string netName: "Torus Shaped Earth"
    readonly property QtObject teams: QtObject { property var data: ({}) }
    function teamsOpen(roomId) { rec("teamsOpen " + (roomId || "")) }
    function teamsList() { rec("teamsList") }
    property string playerPin: ""
    property var realPlayers: []
    property var player: null
    property string profileCls: "balanced"
    function setProfile(name) { rec("setProfile " + name); profileCls = name }
    readonly property QtObject profile: QtObject { readonly property string cls: sys.profileCls }
}
