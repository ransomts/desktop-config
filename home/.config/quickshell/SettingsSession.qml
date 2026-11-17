// Settings > Session: session restore's switch and skip list in ~/.config/shell/session.json
// (Session.qml reads it), through JsonFile so the page works whether or not Session is loaded.
import QtQuick
import QtQuick.Layouts
import Quickshell

SettingsPage {
    id: pg
    pageId: "session"
    title: "Session"
    intro: "At login the island offers to reopen the windows of the last session; nothing reopens unasked."
    JsonFile {
        id: sf
        path: Quickshell.env("SESSION_CONFIG") || Quickshell.env("HOME") + "/.config/shell/session.json"
        defaults: ({ enabled: false, skip: [] })
        watch: pg.shown
    }
    readonly property alias file: sf

    SettingsCard {
        title: "Restore"
        SettingsSwitch {
            label: "Offer to reopen windows at login"
            sub: "Saved at logout and every 10 minutes: app, desktop and place"
            keywords: "session restore reopen login windows"
            checked: sf.values.enabled === true
            onEdited: on => sf.set("enabled", on)
        }
        SettingsChips {
            label: "Never reopen"
            sub: "App classes or desktop ids"
            keywords: "session skip exclude apps"
            enabled: sf.values.enabled === true
            items: Array.isArray(sf.values.skip) ? sf.values.skip : []
            onEdited: l => sf.set("skip", l)
        }
    }
}
