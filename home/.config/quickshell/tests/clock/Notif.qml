pragma Singleton
// Test stand-in for Notif.qml (tests/clock): only the Do Not Disturb flag.
import QtQuick
import Quickshell

Singleton { property bool dnd: false }
