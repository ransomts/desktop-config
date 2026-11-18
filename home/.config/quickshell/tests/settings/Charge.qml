pragma Singleton
// Test stand-in for Charge.qml (agent power; tests/settings). The runner leaves it out for the
// "no Charge" pass.
import QtQuick
import Quickshell

Singleton {
    property var calls: []
    property string profile: "balanced"
    property bool busy: false
    property string error: ""
    readonly property string label: profile === "full_charge" ? "Full charge" : profile === "balanced" ? "Balanced (stops at 90%)" : "Longest life (stops at 60%)"
    function set(name) { calls = calls.concat(["set " + name]); profile = name }
    function refresh() { calls = calls.concat(["refresh"]) }
}
