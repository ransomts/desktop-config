// Palette shared by the bar and the control panel: the same Clemson-orange
// colours as waybar's colors-dark.css / colors-light.css. Follows COSMIC's
// is_dark file, the one switch both desktops use.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: theme
    property bool dark: true

    readonly property color bg:        dark ? tint("#16161a", 0.60) : tint("#f6f3ee", 0.65)
    readonly property color panelBg:   dark ? tint("#16161a", 0.72) : tint("#f6f3ee", 0.78)
    readonly property color solidBg:   dark ? "#16161a" : "#f6f3ee"      // tooltips
    readonly property color fg:        dark ? "#e6e1dc" : "#26262b"
    readonly property color accent:    dark ? "#f56600" : "#522d80"      // accent as text: orange is weak on light pills, so Regalia purple
    readonly property color accentBg:  "#f56600"                         // accent as a fill
    readonly property color accentInk: "#16161a"                         // text on an accent or red fill
    readonly property color alt:       "#522d80"
    readonly property color altInk:    dark ? "#e6e1dc" : "#f6f3ee"
    readonly property color dim:       dark ? "#595959" : "#8c8782"
    readonly property color faint:     dark ? "#8a8580" : "#8c8782"      // small captions
    readonly property color line:      dark ? tint("#595959", 0.5) : tint("#595959", 0.35)
    readonly property color hover:     tint("#f56600", 0.25)
    readonly property color track:     dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)
    readonly property color warn:      dark ? "#f5a623" : "#a86200"
    readonly property color ok:        dark ? "#7fb069" : "#3f7d2c"
    readonly property color red:       dark ? "#e5484d" : "#d13438"
    readonly property string font:     "FiraCode Nerd Font"

    // a colour at a given opacity (the hex values here are rewritten by ~/.local/bin/palette)
    function tint(hex, a) { const c = typeof hex === "string" ? Qt.color(hex) : hex; return Qt.rgba(c.r, c.g, c.b, a) }
    function reload() { modeFile.reload() }

    FileView {
        id: modeFile
        path: Quickshell.env("HOME") + "/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark"
        watchChanges: true
        onFileChanged: { modeFile.reload() }
        onLoaded: theme.dark = text().trim() === "true"
    }
    // cosmic-config replaces the file by rename, which a file watch can lose track of
    Timer { interval: 3000; running: true; repeat: true; onTriggered: modeFile.reload() }
}
