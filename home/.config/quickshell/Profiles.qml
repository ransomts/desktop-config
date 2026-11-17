pragma Singleton
// (pragma first: the singleton scanner gives up on a comment header above it)
// Focus profiles ("Teaching", "Grading", "Writing"): one click sets Do Not Disturb, the
// wallpaper's motion, the island, the pet's calm, keep awake and break reminders, opens apps
// and goes to a desktop; end() puts back what it changed. Logic and file format: ProfilesCore.qml.
//   qs ipc call profile apply NAME | end | status | list
// Hooks: shell.qml sets Profiles.island = island; launcher row through launcherRows(q, view);
// the control panel row is FocusRow.qml; the settings page is SettingsFocus.qml.
import QtQuick
import Quickshell

Singleton {
    id: profiles
    property alias island: core.island
    readonly property var list: core.list
    readonly property var names: core.names
    readonly property var fields: core.fields
    readonly property string active: core.active
    readonly property var changed: core.changed
    readonly property alias file: core.profilesFile
    function apply(name: string): string { return core.apply(name) }
    function end(): string { return core.end() }
    function status(): string { return core.status() }
    function listText(): string { return core.listText() }
    function describe(p) { return core.describe(p) }
    function find(name) { return core.find(name) }
    function edit(name, key, value) { return core.edit(name, key, value) }
    function add(name) { return core.add(name) }
    function remove(name) { return core.remove(name) }
    function launcherRows(q, view) { return core.launcherRows(q, view) }
    ProfilesCore { id: core }
}
