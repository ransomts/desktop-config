pragma Singleton
// Test stand-in for PetSecrets.qml (tests/qml-overlays): the sky (PetSky, PetAntics), what was found
// (recorded), and the signals the antics answer.
import QtQuick
import Quickshell

Singleton {
    property var foundList: []
    function found(what) { foundList = foundList.concat([what]) }
    property bool offended: false
    property bool clemson: false
    property string sky: ""
    property real skyT: 0
    property bool skyLtr: true
    property real skyY: 0.2
    property int count: 0
    property string summary: ""
    signal touchdown()
    signal act(string name)
}
