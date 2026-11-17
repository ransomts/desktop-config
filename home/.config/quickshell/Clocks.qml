pragma Singleton
// (pragma first: the singleton scanner gives up on a comment header above it)
// Everyday clock tools: timers (several at once), alarms, a stopwatch and a world clock. Logic and
// state file: ClocksCore.qml; reading "10m tea" and friends: clocks.js. The big lecture countdown is
// Lecture.qml / LectureTimerView.qml; this is the plain, general tool and does not draw anything big.
//   qs ipc call clock timer 10m tea | 1h30 | 25 (minutes)      qs ipc call clock alarm 7:30 | 6:45am weekdays stand-up | tomorrow 9
//   qs ipc call clock list | cancel ID|all | stopwatch start|stop|toggle|lap|reset|status | snooze
// Hooks: shell.qml sets Clocks.island = island, adds Clocks.launcherRows(q, view) to the launcher's
// providers and calls Clocks.unlocked() when the lock screen says hello; the UI is ClockPanel.qml (in
// Calendar.qml) and SettingsClock.qml. Views that show seconds call Clocks.watch(key, true) while open.
import QtQuick
import Quickshell

Singleton {
    id: clocks
    property alias island: core.island
    property alias core: core
    readonly property var timers: core.timers
    readonly property var alarms: core.alarms
    readonly property var stopwatch: core.stopwatchView
    readonly property var ringing: core.ringing
    readonly property var worldLines: core.worldLines
    readonly property var cities: core.cities
    readonly property double nowMs: core.nowMs
    readonly property int runningCount: core.runningCount
    readonly property string summary: core.summaryText
    readonly property string tip: core.tip                 // "Timer: tea 4 min left"; "" when none
    readonly property alias config: core.config
    function tipFor(minute) { return core.tipFor(minute) }
    function watch(key, on) { core.watch(key, on) }
    function worldWatch(key, on) { core.worldWatch(key, on) }
    function timerSpec(spec: string): string { return core.timerSpec(spec) }
    function alarmSpec(spec: string): string { return core.alarmSpec(spec) }
    function list(): string { return core.list() }
    function cancel(id: string): string { return core.cancel(id) }
    function stopwatchAction(action: string): string { return core.stopwatchAction(action) }
    function snooze(): string { return core.snooze() }
    function status(): string { return core.status() }
    function unlocked() { core.unlocked() }
    function launcherRows(q, view) { return core.launcherRows(q, view) }
    ClocksCore { id: core }
}
