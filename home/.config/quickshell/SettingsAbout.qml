// Settings > About: versions (qs --version, hyprctl version -j; read when the page is shown), where
// the config and the tests live, and the command that runs every test suite (shown, not run).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

SettingsPage {
    id: pg
    pageId: "about"
    title: "About"
    property string qsVersion: ""
    property string hyprVersion: ""
    onShownChanged: if (shown) { if (!qsv.running) qsv.running = true; if (!hv.running) hv.running = true }
    Process { id: qsv; command: Sys.clean.concat(["sh", "-c", "qs --version 2>/dev/null || \"$HOME/.nix-profile/bin/qs\" --version"]); stdout: StdioCollector { onStreamFinished: pg.qsVersion = text.trim().split("\n")[0] } }
    Process { id: hv; command: Sys.clean.concat(["hyprctl", "version", "-j"]); stdout: StdioCollector { onStreamFinished: { try { const o = JSON.parse(text); pg.hyprVersion = (o.tag || o.version || "") + (o.commit ? " (" + String(o.commit).slice(0, 7) + ")" : "") } catch (e) { pg.hyprVersion = "" } } } }
    readonly property string configDir: String(Quickshell.shellDir || "").replace(/^file:\/\//, "")
    readonly property string suites: "pet agenda lecture shot launcher saver health dayflow notify capture auth settings"

    SettingsCard {
        title: "Versions"
        SettingsInfo { label: "Quickshell"; keywords: "about version qs"; value: pg.qsVersion || "…" }
        SettingsInfo { label: "Hyprland"; keywords: "about version hyprland"; value: pg.hyprVersion || "…" }
    }
    SettingsCard {
        title: "Where things are"
        SettingsInfo { label: "Shell config"; keywords: "about quickshell folder"; value: pg.configDir }
        SettingsInfo { label: "Tests"; keywords: "about tests harness"; value: pg.configDir + "/tests/" }
        SettingsInfo { label: "Settings files"; keywords: "about json config shell"; value: "~/.config/shell/" }
        SettingsInfo { label: "State"; keywords: "about state files"; value: (Quickshell.env("XDG_STATE_HOME") || "~/.local/state") + "/" }
        SettingsInfo {
            label: "Run all tests"
            sub: "Copy it into a terminal; nothing runs from here"
            keywords: "about tests run suites"
            value: "for t in " + pg.suites + "; do ~/.local/bin/$t-test || echo \"$t FAILED\"; done"
        }
    }
}
