pragma Singleton
// Test stand-in for Charge.qml (qml-panels-test): the tests/settings stub plus what ProfileList.qml
// reads (cap, end, loaded, limited, capped), with the same rules as the real one.
import QtQuick
import Quickshell

Singleton {
    property var calls: []
    property string profile: "balanced"
    property int end: 90
    property int cap: 80
    property bool loaded: true
    property bool busy: false
    property string error: ""
    readonly property bool limited: loaded && profile !== "full_charge" && end < 100
    readonly property bool capped: loaded && profile === "custom" && end === cap
    readonly property string label: profile === "full_charge" ? "Full charge" : profile === "balanced" ? "Balanced (stops at 90%)"
                                  : profile === "custom" ? "Stops at " + end + "%" : "Longest life (stops at 60%)"
    function set(name) { calls = calls.concat(["set " + name]) }
    function refresh() { calls = calls.concat(["refresh"]) }
    function toggle() { calls = calls.concat(["toggle"]) }
}
