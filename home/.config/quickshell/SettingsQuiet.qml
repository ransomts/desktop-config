// Settings > Quiet hours: the rules in ~/.config/shell/quiet.json (QuietCore.qml watches the file,
// so a change here applies at once). Read through quiet.js normalize(), the same as Quiet does;
// written key by key through JsonFile (other keys in the file are kept). Status and Skip: Quiet.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "quiet.js" as Rules

SettingsPage {
    id: pg
    pageId: "quiet"
    title: "Quiet hours"
    intro: "Do Not Disturb turns itself on for calendar events that match these rules and back off when they end (unless you changed it in between)."
    JsonFile {
        id: qf
        path: Quickshell.env("QUIET_RULES") || Quickshell.env("HOME") + "/.config/shell/quiet.json"
        defaults: Rules.DEFAULTS
        watch: pg.shown
    }
    readonly property var rules: Rules.normalize(qf.values)
    readonly property alias file: qf

    SettingsCard {
        title: "Quiet hours"
        note: Quiet.active ? "quiet now" : ""
        SettingsSwitch {
            label: "Silence during matching events"
            sub: Quiet.status()
            keywords: "quiet dnd calendar lecture automatic"
            checked: pg.rules.enabled
            onEdited: on => qf.set("enabled", on)
        }
        SettingsButton {
            label: "Skip the event under way"
            sub: Quiet.active ? "Notifications come back for the rest of it" : "Nothing quiet now"
            keywords: "quiet skip"
            enabled: Quiet.active
            text: "Skip"
            onClicked: Quiet.skip()
        }
        SettingsStepper {
            label: "Start early"
            sub: "Minutes before the event"
            keywords: "quiet lead before"
            value: pg.rules.lead
            from: 0; to: 120; stepSize: 5
            text: pg.rules.lead === 0 ? "on time" : pg.rules.lead + " min"
            onEdited: v => qf.set("lead", v)
        }
    }
    SettingsCard {
        title: "Which events"
        note: "an event matching any of these"
        SettingsChips {
            label: "Words in the title"
            sub: "Case does not matter; part of a word counts"
            keywords: "quiet titles match"
            items: pg.rules.titles
            onEdited: l => qf.set("titles", l)
        }
        SettingsChips {
            label: "Org tags"
            keywords: "quiet tags"
            items: pg.rules.tags
            onEdited: l => qf.set("tags", l)
        }
        SettingsChips {
            label: "Whole calendars"
            sub: "Calendar file names, e.g. clemson"
            keywords: "quiet calendars"
            items: pg.rules.calendars
            onEdited: l => qf.set("calendars", l)
        }
    }
}
