pragma Singleton
// Test stand-in for WallState.qml (qml-panels-test): the tests/settings stub (copied) plus what
// WallMenu.qml and MediaPop.qml use (cpuTemp, wxDemo, pillbars).
import QtQuick
import Quickshell

Singleton {
    readonly property var scenes: ["silk", "aurora", "contours", "ink", "ridges", "sky", "terrain", "flow", "ripples", "field", "pulsar", "depths"]
    readonly property var effects: ["daylight", "music", "weather", "pointer", "agenda", "desks", "rest", "sharp", "heat", "season"]
    property var calls: []
    readonly property QtObject cfg: QtObject {
        property string scene: "silk"
        property bool running: true
        property int fps: 20
        property bool hidden: false
        property real speed: 0.012
        property bool daylight: true
        property bool music: true
        property bool weather: false
        property bool pointer: true
        property bool agenda: true
        property bool desks: true
        property bool rest: true
        property bool pillbars: true
        property bool heat: true
        property int fanMax: 3700
        property int heatCap: 88
        property bool season: true
        property bool sharp: true
    }
    property bool forced: false
    function force(on) { calls = calls.concat(["force " + on]); forced = on; if (on) { cfg.hidden = false; cfg.running = true } }
    Connections {
        target: cfg
        function onRunningChanged() { if (!cfg.running) forced = false }
        function onHiddenChanged() { if (cfg.hidden) forced = false }
    }
    readonly property bool moving: cfg.running && !cfg.hidden
    property bool hot: false
    property real fanAvg: 0
    property real cpuTemp: 0
    property string wxDemo: ""
    readonly property int fanResume: Math.round(cfg.fanMax * 0.8)
    property string paletteFollow: "off"
    function setScene(name) { calls = calls.concat(["setScene " + name]); if (scenes.indexOf(name) >= 0) cfg.scene = name; return cfg.scene }
    function setEffect(name, on) { calls = calls.concat(["setEffect " + name + " " + on]); cfg[name] = on }
}
