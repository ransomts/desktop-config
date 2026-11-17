// Calendar-aware Do Not Disturb (the logic is in QuietCore.qml, the rules in quiet.js).
//   qs ipc call quiet status | on | off | skip | resync
// Hook: a Connections on Quiet (onAnnounce) puts the message on the island, see shell.qml.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: quiet
    signal announce(string title, string sub)
    readonly property bool active: core.active
    readonly property bool enabled: core.enabled
    function status(): string { return core.status() }
    function setEnabled(on: bool): void { core.setEnabled(on) }
    function skip(): string { return core.skip() }
    function resync(): void { core.resync() }
    QuietCore { id: core; onAnnounce: (t, s) => quiet.announce(t, s) }
}
