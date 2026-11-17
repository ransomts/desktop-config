// Settings > Power. Charge limit: the Charge singleton (Charge.qml, system76-power thresholds through
// charge-profile; polkit asks for the password), when it is loaded. Travel reminder:
// ~/.config/shell/power.json (ChargeTravel.qml). Break reminders: ~/.config/shell/breaks.json
// (Breaks.qml). Both files go through JsonFile, so the rows work whether or not their owner is
// loaded, and keep keys they do not know. Power profile: Sys.profileCls / Sys.setProfile.
import QtQuick
import QtQuick.Layouts
import Quickshell

SettingsPage {
    id: pg
    pageId: "power"
    title: "Power"
    readonly property var charge: { try { return Charge } catch (e) { return null } }
    onShownChanged: if (shown && charge && charge.refresh) charge.refresh()
    readonly property string cfgDir: Quickshell.env("HOME") + "/.config/shell/"
    JsonFile {
        id: power
        path: Quickshell.env("POWER_CONFIG") || pg.cfgDir + "power.json"
        defaults: ({ travelWords: ["flight", "travel", "conference"], remind: false, eveningAt: "19:00" })
        watch: pg.shown
    }
    JsonFile {
        id: breaks
        path: Quickshell.env("BREAKS_FILE") || pg.cfgDir + "breaks.json"
        defaults: ({ enabled: false, workMinutes: 50, restMinutes: 5, snoozeMinutes: 15 })
        watch: pg.shown
    }
    readonly property alias powerFile: power
    readonly property alias breaksFile: breaks

    SettingsCard {
        title: "Battery"
        SettingsChoice {
            label: "Charge limit"
            sub: !pg.charge ? "Not available: Charge.qml is not loaded" : pg.charge.busy ? "Waiting for the password prompt…"
                 : pg.charge.error !== "" ? pg.charge.error : pg.charge.label !== "" ? pg.charge.label : "Reading…"
            keywords: "battery charge threshold lifespan system76"
            enabled: pg.charge !== null && !pg.charge.busy
            wrapWidth: 380
            options: [["full_charge", "Full"], ["balanced", "Balanced"], ["max_lifespan", "Longest life"]]
            value: pg.charge ? pg.charge.profile : ""
            onEdited: v => pg.charge.set(v)
        }
        SettingsSwitch {
            label: "Remind me before travel"
            sub: "In the evening before an event with one of the words below, if a limit is on"
            keywords: "battery travel charge reminder"
            checked: power.values.remind === true
            onEdited: on => power.set("remind", on)
        }
        SettingsChips {
            label: "Travel words"
            keywords: "battery travel"
            enabled: power.values.remind === true
            items: Array.isArray(power.values.travelWords) ? power.values.travelWords : []
            onEdited: l => power.set("travelWords", l)
        }
        SettingsText {
            label: "Remind after"
            keywords: "battery travel evening time"
            enabled: power.values.remind === true
            fieldWidth: 90
            value: String(power.values.eveningAt || "")
            placeholder: "HH:MM"
            valid: t => /^([01]?\d|2[0-3]):[0-5]\d$/.test(t)
            onEdited: t => power.set("eveningAt", t.length === 4 ? "0" + t : t)
        }
    }
    SettingsCard {
        title: "Break reminders"
        SettingsSwitch {
            label: "Remind me to take breaks"
            sub: "A nudge on the island after active work; never while presenting, in a call or in Do Not Disturb"
            keywords: "break rest stretch health"
            checked: breaks.values.enabled === true
            onEdited: on => breaks.set("enabled", on)
        }
        SettingsStepper {
            label: "After working for"
            keywords: "break work minutes"
            enabled: breaks.values.enabled === true
            value: Number(breaks.values.workMinutes) || 50
            from: 10; to: 180; stepSize: 5; suffix: " min"
            onEdited: v => breaks.set("workMinutes", v)
        }
        SettingsStepper {
            label: "Break length"
            keywords: "break rest minutes"
            enabled: breaks.values.enabled === true
            value: Number(breaks.values.restMinutes) || 5
            from: 1; to: 30; suffix: " min"
            onEdited: v => breaks.set("restMinutes", v)
        }
        SettingsStepper {
            label: "Snooze for"
            keywords: "break snooze later"
            enabled: breaks.values.enabled === true
            value: Number(breaks.values.snoozeMinutes) || 15
            from: 5; to: 60; stepSize: 5; suffix: " min"
            onEdited: v => breaks.set("snoozeMinutes", v)
        }
    }
    SettingsCard {
        title: "Performance"
        SettingsChoice {
            label: "Power profile"
            sub: "system76-power"
            keywords: "performance battery balanced cpu fan"
            options: [["battery", "Battery"], ["balanced", "Balanced"], ["performance", "Performance"]]
            value: Sys.profileCls
            onEdited: v => Sys.setProfile(v)
        }
    }
}
