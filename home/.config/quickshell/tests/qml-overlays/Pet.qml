pragma Singleton
// Test stand-in for Pet.qml (tests/qml-overlays): what the Dashboard's pet card, PetSay and
// PetAntics read; the three buttons are recorded.
import QtQuick
import Quickshell

Singleton {
    id: pet
    property var calls: []
    function rec(s) { calls = calls.concat([s]) }
    property string name: "Cub"
    property bool enabled: true
    property int hearts: 3
    property int bond: 80
    property string mood: "idle"
    property string animal: "cat"
    property string coat: "tiger"
    property bool hungry: false
    property string doing: "watching the bar"
    property bool calm: false
    property bool hiding: false
    property real pleased: 0
    property string menuPage: ""
    signal pat(var who)
    signal feed()
    signal play()
    function petIt() { rec("petIt"); pat(0) }
    function giveFood() { rec("giveFood"); feed() }
    function playWith() { rec("playWith"); play() }
    function mins(hm) { const p = String(hm).split(":"); return parseInt(p[0]) * 60 + parseInt(p[1]) }
}
