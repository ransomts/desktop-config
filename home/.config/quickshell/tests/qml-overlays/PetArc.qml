pragma Singleton
// Test stand-in for PetArc.qml (tests/qml-overlays): the journal's numbers and diary.
import QtQuick
import Quickshell

Singleton {
    property var calls: []
    property string summary: "Together 12 days. Yesterday: caught the ball twice."
    property string daysText: "12 days"
    property string since: "6 Nov"
    property var counts: ({ pats: 41, meals: 17, games: 9, tricks: 5, focus: 3 })
    property var hats: []
    property var next: ({ days: 30 })
    property string nextLabel: "a month together"
    property string nextDetail: "in 18 days"
    property var entries: []
    function markSeen() { calls = calls.concat(["markSeen"]) }
    function pretty(d, short) { return Qt.formatDate(new Date(d + "T12:00:00"), "MMM d") }
}
