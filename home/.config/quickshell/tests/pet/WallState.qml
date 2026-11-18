// Test stand-in for WallState.qml (the real one drives the wallpaper and talks to Hyprland).
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    property date seasonDay: new Date(2026, 6, 1)      // 1 July: no hat by the date
    property string seasonKind: ""
    property var game: null
    property string wxDemo: ""
    property string wxKind: "clear"
    property bool wxWanted: false
    readonly property QtObject cfg: QtObject { property bool hidden: false }
}
