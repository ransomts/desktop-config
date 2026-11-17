// Settings > Appearance. Theme: Theme.dark, written by cosmic-theme-toggle; the automatic times
// are hyprsunset.conf's profiles (read and written by sunset-times; theme-by-time follows them).
// Colour plan: `palette list` / `palette use` (rewrites Theme.qml and hyprland.lua: both reload,
// so it asks twice) and the follow mode (WallState.paletteFollow, `palette follow`). Wallpaper:
// WallState.cfg as WallMenu.qml writes it. Animations: anim-preset (state file watched).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

SettingsPage {
    id: pg
    pageId: "appearance"
    title: "Appearance"

    // ---- what the scripts say (read when the page is shown) ----
    property var sun: ({})                      // sunset-times get: { light, dark, temp }
    property var plans: []                      // [{ name, live, about }]
    property string pending: ""                 // a plan picked here, not yet in use
    readonly property string livePlan: (plans.find(p => p.live) || { name: "" }).name
    function refresh() { if (!sunGet.running) sunGet.running = true; if (!planGet.running) planGet.running = true; Sys.readNight() }
    onShownChanged: if (shown) refresh()
    Component.onCompleted: if (shown) refresh()
    Process {
        id: sunGet
        command: Sys.clean.concat([Sys.bin + "sunset-times", "get"])
        stdout: StdioCollector { onStreamFinished: { try { pg.sun = JSON.parse(text) } catch (e) { pg.sun = {} } } }
    }
    Process {
        id: sunSet
        onRunningChanged: if (!running) pg.refresh()
    }
    function setSun(what, v) { sunSet.command = Sys.clean.concat([Sys.bin + "sunset-times", "set", what, String(v)]); sunSet.running = true }
    Process {
        id: planGet
        command: Sys.clean.concat([Sys.bin + "palette", "list"])
        stdout: StdioCollector {
            onStreamFinished: pg.plans = text.split("\n").map(l => /^([* ])\s(\S+)\s+(.*)$/.exec(l)).filter(m => m)
                                             .map(m => ({ name: m[2], live: m[1] === "*", about: m[3].trim() }))
        }
    }
    FileView { id: animFile; path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/anim-preset"; watchChanges: pg.shown; printErrors: false; onFileChanged: reload() }
    readonly property string anim: animFile.loaded ? (animFile.text().trim() || "snappy") : "snappy"

    SettingsCard {
        title: "Theme"
        SettingsChoice {
            label: "Mode"
            sub: "Every app follows (COSMIC's is_dark switch)"
            keywords: "dark light theme"
            options: [["dark", "Dark"], ["light", "Light"]]
            value: Theme.dark ? "dark" : "light"
            onEdited: v => Sys.run(Sys.bin + "cosmic-theme-toggle " + v)
        }
        SettingsText {
            label: "Light from"
            sub: "Light mode and normal colours start at this time"
            keywords: "automatic switch time morning hyprsunset"
            fieldWidth: 90
            value: pg.sun.light || ""
            placeholder: "HH:MM"
            valid: t => /^([01]?\d|2[0-3]):[0-5]\d$/.test(t)
            onEdited: t => pg.setSun("light", t)
        }
        SettingsText {
            label: "Dark from"
            sub: "Dark mode and the warm night light start at this time"
            keywords: "automatic switch time evening night hyprsunset"
            fieldWidth: 90
            value: pg.sun.dark || ""
            placeholder: "HH:MM"
            valid: t => /^([01]?\d|2[0-3]):[0-5]\d$/.test(t)
            onEdited: t => pg.setSun("dark", t)
        }
        SettingsStepper {
            label: "Night light warmth"
            sub: "From the dark time on (6000 K is no change)"
            keywords: "hyprsunset temperature kelvin"
            value: pg.sun.temp || 4500
            from: 2500; to: 6000; stepSize: 100; suffix: " K"
            onEdited: v => pg.setSun("temp", v)
        }
        SettingsSwitch {
            label: "Night light now"
            sub: "By hand; the next switch time takes over again"
            keywords: "hyprsunset warm"
            checked: Sys.night
            onEdited: on => Sys.setNight(on ? Sys.nightWanted : 6000)
        }
    }

    SettingsCard {
        title: "Colour plan"
        note: pg.livePlan !== "" ? "in use: " + pg.livePlan : ""
        SettingsChoice {
            label: "Plan"
            sub: "Pick one, then use it below"
            keywords: "palette colours accent"
            below: true
            options: pg.plans.map(p => [p.name, p.name.charAt(0).toUpperCase() + p.name.slice(1)])
            value: pg.pending !== "" ? pg.pending : pg.livePlan
            onEdited: v => pg.pending = v === pg.livePlan ? "" : v
        }
        SettingsButton {
            label: pg.pending !== "" ? "Use " + pg.pending : "Plan in use"
            sub: pg.pending !== "" ? "Rewrites the themed files; Hyprland and this shell reload" : "Pick another plan above to change it"
            keywords: "palette use apply"
            enabled: pg.pending !== ""
            text: "Use it"
            confirm: "reloads Hyprland and the shell"
            onClicked: { Sys.run(Sys.bin + "palette use '" + pg.pending.replace(/'/g, "") + "' >/dev/null 2>&1"); pg.pending = "" }
        }
        SettingsChoice {
            label: "Change plan by itself"
            sub: WallState.paletteFollow === "off" ? "Off: the plan stays as chosen" : "Each change of " + (WallState.paletteFollow === "scene" ? "wallpaper scene" : "listed time") + " can switch the plan (and reload); tables: palette follow set"
            keywords: "palette follow scene time automatic"
            options: [["off", "Off"], ["scene", "With the scene"], ["time", "By time"]]
            value: WallState.paletteFollow
            onEdited: v => Sys.run(Sys.bin + "palette follow " + v + " >/dev/null 2>&1")
        }
    }

    SettingsCard {
        title: "Wallpaper"
        note: WallState.cfg.hidden ? "plain image" : WallState.moving ? "moving" : WallState.cfg.running ? (WallState.hot ? "resting: fan busy" : "still: on battery") : "still"
        SettingsChoice {
            label: "Scene"
            keywords: "wallpaper animated"
            below: true
            options: WallState.scenes.map(s => [s, s.charAt(0).toUpperCase() + s.slice(1)])
            value: WallState.cfg.scene
            onEdited: v => WallState.setScene(v)
        }
        SettingsChoice {
            label: "Motion"
            sub: "Moves on mains power only"
            keywords: "wallpaper animation still plain hyprpaper"
            options: [["moving", "Moving"], ["still", "Still"], ["plain", "Plain image"]]
            value: WallState.cfg.hidden ? "plain" : WallState.cfg.running ? "moving" : "still"
            onEdited: v => { if (v === "plain") WallState.cfg.hidden = true; else { WallState.cfg.hidden = false; WallState.cfg.running = v === "moving" } }
        }
        SettingsChoice {
            label: "Frames a second"
            sub: "Fewer is less work for the GPU"
            keywords: "fps wallpaper"
            enabled: !WallState.cfg.hidden && WallState.cfg.running
            options: [5, 10, 15, 20, 30]
            value: WallState.cfg.fps
            onEdited: v => WallState.cfg.fps = v
        }
        SettingsSlider {
            label: "Speed"
            keywords: "wallpaper flow"
            enabled: !WallState.cfg.hidden && WallState.cfg.running
            from: 0.002; to: 0.05; stepSize: 0.001
            value: WallState.cfg.speed
            text: (WallState.cfg.speed / 0.012).toFixed(1) + "×"
            onEdited: v => WallState.cfg.speed = v
        }
        Repeater {
            model: [["daylight", "Daylight colours", "Colours shift with the time of day"],
                    ["music", "Pulse with music", "Scenes move with what is playing"],
                    ["weather", "Weather", "Rain, fog and snow drawn over the scene"],
                    ["pointer", "Lean toward the pointer", ""],
                    ["agenda", "Today's events", "A band along the bottom"],
                    ["desks", "Each desktop a different part", ""],
                    ["rest", "Rest when covered", "A screen full of windows holds its frame"],
                    ["sharp", "No blur while moving", "Saves GPU work"],
                    ["season", "Seasonal touches", "Leaves, snow, petals, fireflies, the game-day paw"],
                    ["pillbars", "Bars in the music pill", ""],
                    ["heat", "Heat guard", "Hold still while the fan is busy"]]
            SettingsSwitch {
                required property var modelData
                label: modelData[1]
                sub: modelData[2]
                keywords: "wallpaper effect " + modelData[0]
                checked: WallState.cfg[modelData[0]] === true
                onEdited: on => WallState.setEffect(modelData[0], on)
            }
        }
        SettingsStepper {
            label: "Rest when the fan averages"
            sub: "Moves again below " + WallState.fanResume + (WallState.fanAvg > 0 ? "  ·  now " + Math.round(WallState.fanAvg) : "")
            keywords: "heat guard fan rpm"
            enabled: WallState.cfg.heat
            value: WallState.cfg.fanMax
            from: 1500; to: 6000; stepSize: 100; suffix: " rpm"
            onEdited: v => WallState.cfg.fanMax = v
        }
        SettingsStepper {
            label: "…or the CPU reaches"
            keywords: "heat guard temperature cap"
            enabled: WallState.cfg.heat
            value: WallState.cfg.heatCap
            from: 60; to: 98; suffix: " °C"
            onEdited: v => WallState.cfg.heatCap = v
        }
    }

    SettingsCard {
        title: "Motion and pointer"
        SettingsChoice {
            label: "Animations"
            sub: pg.anim === "calm" ? "Slower, everything fades, no dimming" : pg.anim === "stock" ? "Hyprland's defaults" : "Quick; desktops slide a little; unfocused windows dim"
            keywords: "anim-preset hyprland"
            options: [["snappy", "Snappy"], ["calm", "Calm"], ["stock", "Stock"]]
            value: pg.anim
            onEdited: v => Sys.run(Sys.bin + "anim-preset " + v + " >/dev/null")
        }
        SettingsInfo {
            label: "Cursor theme"
            sub: "Set in hyprland.lua (hl.env), read only here"
            keywords: "pointer mouse xcursor"
            value: (Quickshell.env("XCURSOR_THEME") || "default") + (Quickshell.env("XCURSOR_SIZE") ? ", " + Quickshell.env("XCURSOR_SIZE") + " px" : "")
        }
    }
}
