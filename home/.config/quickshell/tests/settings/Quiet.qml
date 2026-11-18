pragma Singleton
// Test stand-in for Quiet.qml (tests/settings).
import QtQuick
import Quickshell

Singleton {
    property bool enabled: true
    property bool active: false
    property var calls: []
    function status() { return active ? "quiet until 10:50 (Lecture)" : "on, nothing quiet now" }
    function skip() { calls = calls.concat(["skip"]); active = false; return "skipped" }
    function setEnabled(on) { calls = calls.concat(["setEnabled " + on]); enabled = on }
}
