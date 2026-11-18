pragma Singleton
// (copied from tests/settings for qml-panels-test; keep the two in step by hand)
// Test stand-in for Health.qml (tests/settings): made-up jobs.
import QtQuick
import Quickshell

Singleton {
    property var calls: []
    property var jobs: [
        { id: "mail", name: "Mail sync", state: "failed", why: "mbsync exited 1" },
        { id: "roam", name: "push-roam", state: "stale", why: "last ran 3 h ago" },
        { id: "cal", name: "Calendars", state: "ok", why: "" },
        { id: "backup", name: "Backup", state: "off", why: "timer disabled" }
    ]
    property var notices: [{ id: "apt", name: "Package updates", why: "12 package updates", actionable: false }]
    property var hiddenJobs: [{ id: "old", name: "Old job" }]
    property var ignored: ({})
    property bool loaded: true
    property bool busy: false
    readonly property var bad: jobs.filter(j => (j.state === "failed" || j.state === "stale") && !ignored[j.id])
    function ignore(id) { calls = calls.concat(["ignore " + id]); const m = Object.assign({}, ignored); m[id] = 1; ignored = m }
    function unignore(id) { calls = calls.concat(["unignore " + id]); const m = Object.assign({}, ignored); delete m[id]; ignored = m }
    function refresh(force) { calls = calls.concat(["refresh"]) }
}
