// Test stand-in for the shell's Notif.qml: only the Do Not Disturb flag the launcher's mail mode reads.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    property bool dnd: false
}
