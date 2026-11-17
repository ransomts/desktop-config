// Settings > Screensaver and idle: SaverState.cfg (saver.json), Sys.keepAwake, and hypridle's
// own times (hypridle.conf, read only here).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

SettingsPage {
    id: pg
    pageId: "saver"
    title: "Screensaver and idle"
    FileView { id: idleConf; path: Quickshell.env("HOME") + "/.config/hypr/hypridle.conf"; printErrors: false }
    // [{ seconds, what }] from the listener blocks
    readonly property var idle: {
        if (!idleConf.loaded) return []
        const out = []
        const re = /listener\s*\{([^}]*)\}/g
        let m
        while ((m = re.exec(idleConf.text())) !== null) {
            const t = /^\s*timeout\s*=\s*(\d+)/m.exec(m[1]), c = /^\s*on-timeout\s*=\s*(.*)$/m.exec(m[1])
            if (t && c) out.push({ seconds: parseInt(t[1]), what: /lock/.test(c[1]) ? "lock" : /dpms/.test(c[1]) ? "screens off" : c[1].trim() })
        }
        return out.sort((a, b) => a.seconds - b.seconds)
    }
    function mins(s) { return s % 60 === 0 ? s / 60 + " min" : s + " s" }

    SettingsCard {
        title: "Screensaver"
        note: SaverState.cfg.minutes > 0 && SaverState.blocker !== "" ? "would not start now: " + SaverState.blocker : ""
        SettingsStepper {
            label: "Start after"
            sub: "Idle minutes; the wallpaper scene comes up with a clock"
            keywords: "screensaver idle minutes saver"
            value: SaverState.cfg.minutes
            from: 0; to: 240
            text: SaverState.cfg.minutes === 0 ? "never" : SaverState.cfg.minutes + " min"
            onEdited: v => SaverState.setMinutes(v)
        }
        SettingsChoice {
            label: "Scene"
            keywords: "screensaver scene cycle"
            below: true
            enabled: SaverState.cfg.minutes > 0
            options: [["same", "Same as the wallpaper"], ["cycle", "A new one every 2 min"]].concat(WallState.scenes.map(s => [s, s.charAt(0).toUpperCase() + s.slice(1)]))
            value: SaverState.cfg.scene
            onEdited: v => SaverState.setScene(v)
        }
        SettingsSwitch {
            label: "Clock and date"
            keywords: "screensaver clock"
            enabled: SaverState.cfg.minutes > 0
            checked: SaverState.cfg.clock
            onEdited: on => SaverState.cfg.clock = on
        }
        SettingsSwitch {
            label: "Also on battery"
            sub: "It then shows a held frame"
            keywords: "screensaver battery"
            enabled: SaverState.cfg.minutes > 0
            checked: SaverState.cfg.battery
            onEdited: on => SaverState.cfg.battery = on
        }
        SettingsButton {
            label: "Try it"
            sub: "Up for 8 seconds; any key ends it"
            keywords: "screensaver preview"
            text: "Preview"
            onClicked: { pg.win.visible = false; SaverState.preview(8000) }
        }
    }
    SettingsCard {
        title: "Idle"
        SettingsSwitch {
            label: "Keep awake"
            sub: "The screen won't dim, blank or lock (until the shell reloads)"
            keywords: "caffeine inhibit idle sleep"
            checked: Sys.keepAwake
            onEdited: on => Sys.keepAwake = on
        }
        Repeater {
            model: pg.idle
            SettingsInfo {
                required property var modelData
                label: modelData.what.charAt(0).toUpperCase() + modelData.what.slice(1)
                sub: "hypridle.conf"
                keywords: "idle hypridle timeout"
                value: "after " + pg.mins(modelData.seconds)
            }
        }
    }
}
