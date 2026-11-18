// A stand-in for PetSprite.qml (tests/qml-overlays), with exactly what PetAntics.qml reads, sets and
// calls; every call is recorded in `calls`. The real PetAntics is its child, as in PetSprite.
import QtQuick

Item {
    id: s
    property var calls: []
    function rec(w) { calls = calls.concat([w]) }
    readonly property int k: 2
    readonly property int box: 32
    readonly property int size: 32
    width: 32; height: 32
    property int who: 0
    property bool active: true
    property bool carried: false
    property bool hovered: false
    property bool walking: false
    property bool flying: false
    property bool grooming: false
    property var afterWalk: null
    property bool busy: false
    property string mood: "idle"
    property string animal: "cat"
    property var kind: ({ shell: false })
    property bool faceLeft: false
    property int frame: 0
    property real hop: 0
    property string bubble: ""
    property bool upside: false
    property bool weigh: false
    property bool atop: false
    property var spans: ({ bell: { from: 300, to: 330 }, clock: { from: 400, to: 480 } })
    property real clockX: 440
    readonly property int fWalk: 1
    readonly property int fSit: 4
    readonly property int fSleep: 5
    readonly property int fBlink: 6
    readonly property int fGroom: 8
    readonly property int fPounce: 9
    readonly property int fLoaf: 12
    function stopMoving() { rec("stopMoving") }
    function endBusy() { rec("endBusy"); busy = false }
    function reset() { rec("reset") }
    function hopOnce() { rec("hopOnce") }
    function rang() { rec("rang") }
    function pushed() { rec("pushed") }
    function patted(g) { rec("patted " + g); busy = false }
    function nearestSpot(x) { return x }
    function walkTo(x, speed, then) { rec("walkTo " + x); s.x = x; if (then) then() }
    property alias antics: a
    PetAntics { id: a; sprite: s }
}
