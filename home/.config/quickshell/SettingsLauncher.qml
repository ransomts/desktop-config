// Settings > Launcher: the Org capture template ($XDG_STATE_HOME/launcher.json "captureKey", read by
// LaunchView each time the o mode opens; written here through JsonFile, other keys kept) and the
// mode prefixes as a reference, from the launcher itself (launcher.view.modes, the window's hook).
import QtQuick
import QtQuick.Layouts
import Quickshell

SettingsPage {
    id: pg
    pageId: "launcher"
    title: "Launcher"
    intro: "Super+D opens it. Type a prefix first to switch what it searches; Tab cycles through the first few."
    JsonFile {
        id: lf
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/launcher.json"
        defaults: ({ captureKey: "" })
        watch: pg.shown
    }
    readonly property alias file: lf
    readonly property var modes: win && win.launcherView ? win.launcherView.modes : []

    SettingsCard {
        title: "Org capture"
        SettingsText {
            label: "Capture template key"
            sub: "The org-capture template the o prefix files notes with"
            keywords: "launcher org capture emacs template"
            fieldWidth: 80
            value: String(lf.values.captureKey || "")
            placeholder: "none"
            valid: t => /^[A-Za-z0-9]{1,4}$/.test(t)
            onEdited: t => lf.set("captureKey", t)
        }
    }
    SettingsCard {
        title: "Prefixes"
        note: pg.modes.length ? "" : "not connected (shell.qml hook missing)"
        Repeater {
            model: pg.modes.filter(m => m.id !== "apps")
            SettingsInfo {
                required property var modelData
                label: modelData.hint
                keywords: "launcher prefix mode " + modelData.id
                value: modelData.prefix.trim() === "" ? modelData.id : modelData.prefix.trim()
            }
        }
        SettingsInfo {
            label: "Focus profiles"
            sub: "Type focus, or a profile's name"
            keywords: "launcher focus profile"
            value: "focus"
        }
    }
}
