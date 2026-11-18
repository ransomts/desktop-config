pragma Singleton
// Test stand-in for CamState.qml (tests/settings): no camera.
import QtQuick
import Quickshell

Singleton {
    property var calls: []
    property bool shown: false
    property string error: ""
    property var cameras: []                // none: the page shows "No camera found"
    property int camIndex: -1
    readonly property int minSize: 120
    readonly property int maxSize: 480
    readonly property QtObject cfg: QtObject { property int size: 220; property string device: "/dev/video0" }
    function on() { calls = calls.concat(["on"]); shown = true }
    function off() { calls = calls.concat(["off"]); shown = false }
    function scan() { calls = calls.concat(["scan"]) }
    function use(path) { calls = calls.concat(["use " + path]); cfg.device = path }
    function setSize(px) { calls = calls.concat(["setSize " + px]); cfg.size = Math.max(minSize, Math.min(maxSize, Math.round(px))); return cfg.size }
}
