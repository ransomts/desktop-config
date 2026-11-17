// Settings > Bar and island. Sys.barVisible, the island (shell.qml's `island`, through the window's
// hook), cursor shake and drop preview (ids in shell.qml, hooks too), Sys.sounds, Tailscale.
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: pg
    pageId: "bar"
    title: "Bar and island"
    readonly property var island: win ? win.island : null
    readonly property var cursorFind: win ? win.cursorFind : null
    readonly property var dropPreview: win ? win.dropPreview : null

    SettingsCard {
        title: "Bar"
        SettingsSwitch {
            label: "Show the bar"
            sub: "Until the shell reloads (not remembered)"
            keywords: "hide panel top"
            checked: Sys.barVisible
            onEdited: on => Sys.barVisible = on
        }
        SettingsSwitch {
            label: "Island messages"
            sub: pg.island ? "Short notes that grow out of the clock: meetings, recording, headphones" : "Not connected (shell.qml hook missing)"
            keywords: "island popup clock"
            enabled: pg.island !== null
            checked: pg.island ? pg.island.enabled : false
            onEdited: on => pg.island.setEnabled(on)
        }
        SettingsSwitch {
            label: "Shell sounds"
            sub: "Screenshot, recording and other small cues"
            keywords: "audio cue sound"
            checked: Sys.sounds
            onEdited: on => Sys.setSounds(on)
        }
    }
    SettingsCard {
        title: "Pointer and windows"
        SettingsSwitch {
            label: "Shake to find the pointer"
            sub: "Until the shell reloads (not remembered)"
            keywords: "cursor shake grow find"
            enabled: pg.cursorFind !== null
            checked: pg.cursorFind ? pg.cursorFind.enabled : false
            onEdited: on => pg.cursorFind.enabled = on
        }
        SettingsSwitch {
            label: "Show where a dragged window lands"
            sub: "Until the shell reloads (not remembered)"
            keywords: "drop preview tiling drag"
            enabled: pg.dropPreview !== null
            checked: pg.dropPreview ? pg.dropPreview.enabled : false
            onEdited: on => pg.dropPreview.enabled = on
        }
    }
    SettingsCard {
        title: "Network"
        SettingsSwitch {
            label: "Tailscale"
            sub: "tailscale up / down"
            keywords: "vpn tailnet"
            checked: Sys.tail.cls === "on"
            onEdited: on => Sys.setTailscale(on)
        }
    }
}
