pragma Singleton
// (copied from tests/settings for qml-panels-test; keep the two in step by hand)
// Test stand-in for PetPrefs.qml (tests/settings): the three habits the page shows.
import QtQuick
import Quickshell

Singleton {
    id: pp
    property var calls: []
    readonly property var choices: ({ bedtime: ["21:00", "22:00", "23:00", "00:00", "01:00", "never"], meeting: ["off", "2", "5", "10", "15"], lively: ["quiet", "normal", "lively"] })
    property string bedtime: "23:00"
    property string meeting: "5"
    property string lively: "normal"
    function label(key, v) { return key === "meeting" ? (v === "off" ? "off" : v + " min") : v }
    function setHabit(key, value) { calls = calls.concat(["setHabit " + key + " " + value]); pp[key] = value; return key + "=" + value }
}
