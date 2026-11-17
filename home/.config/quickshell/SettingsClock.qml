// Settings > Clocks: the alarms (the same list the calendar popup and the launcher show; Clocks
// keeps it in $XDG_STATE_HOME/clocks.json), the snooze length and the alarm sound, and the world
// clock's cities in ~/.config/shell/clocks.json (through JsonFile, other keys kept). A city is a
// time zone name, optionally with a label: "Europe/Berlin" or "Berlin=Europe/Berlin". The zone is
// checked against the names this machine knows (bin/tz-now --list); a wrong one is refused.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "clocks.js" as C

SettingsPage {
    id: pg
    pageId: "clock"
    title: "Clocks"
    intro: "Alarms, timers and the world clock. Timers and alarms are started from the calendar popup, the launcher (timer 10m tea, alarm 7:30) or qs ipc call clock."
    readonly property var core: Clocks.core
    property string cityError: ""
    property string alarmError: ""
    onShownChanged: { core.settingsOpen = shown; if (shown) core.loadZones() }
    function cityText(c) { return c.name === c.tz.split("/").pop().replace(/_/g, " ") ? c.tz : c.name + "=" + c.tz }
    function parseCity(t) {
        const i = t.indexOf("=")
        const tz = (i >= 0 ? t.slice(i + 1) : t).trim().replace(/ /g, "_")
        const name = i >= 0 ? t.slice(0, i).trim() : ""
        return { name: name !== "" ? name : tz.split("/").pop().replace(/_/g, " "), tz: tz }
    }

    SettingsCard {
        title: "Alarms"
        note: pg.core.alarms.length === 0 ? "none set" : pg.core.alarms.length + " set"
        Repeater {
            model: pg.core.alarms
            ColumnLayout {
                id: al
                required property var modelData
                Layout.fillWidth: true
                spacing: 0
                SettingsSwitch {
                    label: al.modelData.time + (al.modelData.label !== "" ? "  " + al.modelData.label : "")
                    sub: C.whenText(al.modelData, Clocks.nowMs) + (al.modelData.enabled ? "" : "  ·  off")
                    keywords: "alarm wake time"
                    checked: al.modelData.enabled
                    onEdited: on => pg.core.setAlarmEnabled(al.modelData.id, on)
                }
                SettingsButton {
                    label: "Remove " + al.modelData.time + (al.modelData.label !== "" ? "  " + al.modelData.label : "")
                    keywords: "alarm delete"
                    text: "Remove"
                    onClicked: pg.core.removeAlarm(al.modelData.id)
                }
            }
        }
        SettingsText {
            id: newAlarm
            label: "New alarm"
            sub: pg.alarmError !== "" ? pg.alarmError : "7:30, 6:45am weekdays stand-up, tomorrow 9, mon wed fri 7"
            keywords: "alarm add set wake"
            placeholder: "7:30 weekdays"
            fieldWidth: 220
            value: ""
            valid: t => { const p = C.parseAlarm(t, pg.core.now()); pg.alarmError = p.error || ""; return !p.error }
            onEdited: t => { pg.core.alarmSpec(t); newAlarm.input.text = "" }
        }
    }
    SettingsCard {
        title: "Snooze and sound"
        SettingsStepper {
            label: "Snooze for"
            sub: "Clicking a ringing alarm on the island, or qs ipc call clock snooze"
            keywords: "alarm snooze minutes"
            value: pg.core.snoozeMinutes
            from: 1; to: 60; stepSize: 1
            text: pg.core.snoozeMinutes + " min"
            onEdited: v => Clocks.config.set("snoozeMinutes", v)
        }
        SettingsSwitch {
            label: "Play a sound"
            sub: "Alarms and timers; Do Not Disturb silences timers but never alarms"
            keywords: "alarm timer sound ring"
            checked: pg.core.soundOn
            onEdited: on => Clocks.config.set("sound", on)
        }
        SettingsButton {
            label: "Try the sound"
            sub: Sys.sounds ? "The shell's sounds are on" : "The shell's sounds are off (control panel)"
            keywords: "alarm sound test"
            text: "Play"
            onClicked: Sys.sound(pg.core.soundName)
        }
    }
    SettingsCard {
        title: "World clock"
        note: "shown in the calendar popup"
        SettingsChips {
            label: "Cities"
            sub: "A time zone name, or Label=Zone: Europe/Berlin, Berlin=Europe/Berlin"
            keywords: "world clock time zone city"
            items: pg.core.cities.map(pg.cityText)
            placeholder: "Zone…"
            valid: t => {
                const c = pg.parseCity(t)
                if (pg.core.zoneNames.length === 0) { pg.cityError = "the list of zones is still loading, try again"; return false }
                if (!pg.core.validZone(c.tz)) { pg.cityError = "not a time zone: " + c.tz; return false }
                pg.cityError = ""
                return true
            }
            onEdited: l => pg.core.setCities(l.map(pg.parseCity))
        }
        SettingsInfo {
            visible: pg.cityError !== ""
            label: "Not added"
            value: pg.cityError
        }
    }
}
