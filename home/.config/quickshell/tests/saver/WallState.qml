// Test stand-in for WallState.qml: the scene list, settings, palette and the animation clock
// the screensaver reads, and nothing that talks to Hyprland, the fan or the network.
// See tests/saver/shell.qml.
pragma Singleton
import QtQuick
import Quickshell
import "palettes.js" as Pal

Singleton {
    id: ws
    readonly property var scenes: ["silk", "aurora", "contours", "ink", "ridges", "sky", "terrain", "flow", "ripples", "field", "pulsar", "depths"]
    readonly property QtObject cfg: QtObject {
        property string scene: "contours"
        property real speed: 0.012
        property int fps: 20
        property bool desks: true
        property bool running: true
        property bool hidden: false
        property bool heat: true
        property real lat: 34.6834
        property real lng: -82.8374
    }
    property bool hot: false
    property bool onBattery: false
    // as the real one: mains, set moving, not hidden, fan not busy
    readonly property bool moving: cfg.running && !cfg.hidden && !onBattery && !(cfg.heat && hot)
    property real clock: 1234
    Timer {
        interval: Math.round(1000 / ws.cfg.fps); repeat: true; running: ws.moving
        onTriggered: ws.clock += interval / 1000
    }
    property real dayPhase: 0.9
    property real sunAlt: -30
    readonly property real sunSin: Math.sin(sunAlt * Math.PI / 180)
    property real wxCloud: 0
    readonly property rect layoutBox: Qt.rect(0, 0, 1280, 360)
    function tone(scene, dark, i) { return Qt.color((Pal.palettes[scene] || Pal.palettes.silk)[dark ? "dark" : "light"].c[i]) }
    function stops(scene, dark) {
        const s = (Pal.palettes[scene] || Pal.palettes.silk)[dark ? "dark" : "light"].s
        return Qt.vector4d(s[0], s[1], s[2], 1.0)
    }
}
