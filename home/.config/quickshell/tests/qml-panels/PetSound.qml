pragma Singleton
// (copied from tests/settings for qml-panels-test; keep the two in step by hand)
// Test stand-in for PetSound.qml (tests/settings): nothing plays.
import QtQuick
import Quickshell

Singleton {
    property var calls: []
    property bool enabled: false
    property string level: "quiet"
    readonly property var levelNames: ["quiet", "soft", "normal"]
    function setEnabled(on) { calls = calls.concat(["setEnabled " + on]); enabled = on }
    function setLevel(n) { calls = calls.concat(["setLevel " + n]); level = n; return n }
}
