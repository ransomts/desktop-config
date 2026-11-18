pragma Singleton
// Test stand-in for SaverState.qml (tests/settings).
import QtQuick
import Quickshell

Singleton {
    property var calls: []
    readonly property QtObject cfg: QtObject { property int minutes: 5; property string scene: "same"; property bool clock: true; property bool battery: false }
    property string blocker: ""
    function setMinutes(n) { calls = calls.concat(["setMinutes " + n]); cfg.minutes = Math.max(0, Math.min(240, n)); return cfg.minutes }
    function setScene(n) { calls = calls.concat(["setScene " + n]); cfg.scene = n; return n }
    function preview(ms) { calls = calls.concat(["preview " + ms]) }
}
