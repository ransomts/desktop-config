pragma Singleton
// (copied from tests/settings for qml-panels-test; keep the two in step by hand)
// Test stand-in for Pet.qml (tests/settings).
import QtQuick
import Quickshell

Singleton {
    property var calls: []
    function rec(s) { calls = calls.concat([s]) }
    property string name: "Cub"
    property bool enabled: true
    property bool calm: false
    property bool chase: true
    property bool roam: true
    property bool shy: true
    property string menuPage: ""
    function setEnabled(on) { rec("setEnabled " + on); enabled = on }
    function setCalm(on) { rec("setCalm " + on); calm = on }
    function setChase(on) { rec("setChase " + on); chase = on }
    function setRoam(on) { rec("setRoam " + on); roam = on }
    function setShy(on) { rec("setShy " + on); shy = on }
}
