pragma Singleton
// Test stand-in for Quickshell.Hyprland's Hyprland singleton (tests/qml-overlays). The runner takes
// `import Quickshell.Hyprland` out of the copied files, so `Hyprland` means this: monitors, workspaces
// and toplevels come from the fixtures the cases set, never from a compositor. refresh*() is recorded.
import QtQuick
import Quickshell

Singleton {
    id: h
    property var calls: []
    function rec(what) { calls = calls.concat([what]) }
    property QtObject monitors: QtObject { property var values: [] }
    property QtObject workspaces: QtObject { property var values: [] }
    property QtObject toplevels: QtObject { property var values: [] }
    property var focusedMonitor: null
    property var focusedWorkspace: null
    function refreshMonitors() { rec("refreshMonitors") }
    function refreshWorkspaces() { rec("refreshWorkspaces") }
    function refreshToplevels() { rec("refreshToplevels") }
    function dispatch(s) { rec("dispatch " + s) }
    signal rawEvent(var event)
}
