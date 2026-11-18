pragma Singleton
// Test stand-in for Lecture.qml (tests/settings).
import QtQuick
import Quickshell

Singleton {
    property var calls: []
    property int spotRadius: 150
    function setSpotSize(px) { calls = calls.concat(["setSpotSize " + px]); spotRadius = Math.max(40, Math.min(800, Math.round(px))) }
    readonly property var tools: ["pen", "marker", "arrow", "box", "ellipse", "line"]
    property string tool: "pen"
    function setTool(n) { calls = calls.concat(["setTool " + n]); tool = n }
    readonly property var colorNames: ["orange", "purple", "red", "green", "white"]
    property int colorIndex: 0
    readonly property var weights: [2, 3, 4, 6, 8, 12, 16, 24]
    property int weightIndex: 2
    property bool keysOn: false
    property string keysProblem: ""
    function toggleKeys() { calls = calls.concat(["toggleKeys"]); keysOn = !keysOn }
    property real zoomFactor: 1
}
