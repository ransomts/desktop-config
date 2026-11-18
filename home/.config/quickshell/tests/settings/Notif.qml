pragma Singleton
// Test stand-in for Notif.qml (tests/settings): DND, per-app rules, snoozed; calls recorded.
import QtQuick
import Quickshell

Singleton {
    property var calls: []
    property bool dnd: false
    function setDnd(on) { calls = calls.concat(["setDnd " + on]); dnd = on }
    property var rules: ({ "Slack": "list" })
    property var counts: ({ "Thunderbird": 12, "Slack": 4, "Discord": 2 })
    function ruleFor(app) { const r = rules[app]; return r === "mute" || r === "list" ? r : "normal" }
    function setRule(app, rule) { calls = calls.concat(["setRule " + app + " " + rule]); const r = Object.assign({}, rules); if (rule === "normal") delete r[app]; else r[app] = rule; rules = r; return true }
    readonly property var apps: Object.keys(counts).map(a => ({ app: a, count: counts[a], rule: ruleFor(a) }))
    property var snoozed: [{ id: "a" }, { id: "b" }]
    function wakeSnoozed() { calls = calls.concat(["wakeSnoozed"]); snoozed = [] }
}
