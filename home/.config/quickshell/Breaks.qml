pragma Singleton
// Break reminders (logic in BreaksCore.qml, settings in ~/.config/shell/breaks.json, off until switched on).
//   qs ipc call breaks status | on | off | reset
//   qs ipc call breaks set workMinutes 45        (also restMinutes, snoozeMinutes)
//   Breaks.line      "Working for 37 min" for the dashboard, "" when off or between stretches
// Hook: a Connections on Breaks (onNudge) puts the message on the island and has the pet stretch, see shell.qml.
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: breaks
    signal nudge(int minutes)
    readonly property bool enabled: core.enabled
    readonly property int workMin: core.workMin
    readonly property string line: core.line
    function status(): string { return core.status() }
    function setEnabled(on: bool): void { core.setEnabled(on) }
    function reset(): void { core.reset() }
    function setKey(key: string, value: string): string { return core.setKey(key, value) }
    BreaksCore { id: core; useIdle: idleWatch.active; onNudge: m => breaks.nudge(m) }
    // Activity = any input in the last minute, on any keyboard or pointer. A Wayland idle object, created only
    // while break reminders are on; nothing polls. (Video playing does not count as work: inhibitors are ignored.)
    LazyLoader {
        id: idleWatch
        active: breaks.enabled && Quickshell.env("SESSION_HARNESS") !== "1" && Quickshell.env("QT_QPA_PLATFORM") !== "offscreen"
        IdleMonitor {
            timeout: 60
            respectInhibitors: false
            onIsIdleChanged: core.userIdle = isIdle
        }
    }
}
