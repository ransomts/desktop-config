pragma Singleton
// Test stand-in for Sys.qml (tests/settings): what the settings pages and Profiles use. run() and
// launch() are recorded, never run; bin is the runner's folder of stand-in scripts.
import QtQuick
import Quickshell

Singleton {
    id: sys
    readonly property string bin: Quickshell.env("SETTINGS_BIN") + "/"
    readonly property var clean: []
    property var calls: []
    property string nowHM: Qt.formatTime(new Date(), "HH:mm")   // ClocksCore listens to it (as in the real Sys.qml)
    function rec(what) { calls = calls.concat([what]) }
    function run(cmd) { rec("run " + cmd) }
    function launch(argv) { rec("launch " + argv.join(" ")) }
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
    property string profileCls: "balanced"
    function setProfile(name) { rec("setProfile " + name); profileCls = name }
    property int desktop: 1
    function goDesktop(n) { rec("goDesktop " + n); desktop = n }
    signal popupRequest(string name)
    onPopupRequest: name => rec("popup " + name)
    function reset() { calls = [] }
}
