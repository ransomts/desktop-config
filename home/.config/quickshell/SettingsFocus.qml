// Settings > Focus profiles: edits ~/.config/shell/profiles.json through Profiles (edit / add /
// remove keep everything else in the file), and applies or ends one (Profiles.apply / end).
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: pg
    pageId: "focus"
    title: "Focus profiles"
    intro: "One click sets these; ending it puts back what it changed, except what you changed by hand in between. Also in the launcher (type focus) and the control panel."
    function cap(s) { return s.charAt(0).toUpperCase() + s.slice(1) }
    // the profiles' names, changed only when one comes or goes, so editing one does not rebuild
    // its card (and lose keyboard focus)
    property var names: []
    readonly property string namesKey: Profiles.names.join("\n")
    onNamesKeyChanged: names = Profiles.names
    Component.onCompleted: names = Profiles.names

    SettingsCard {
        title: "Now"
        SettingsInfo {
            label: Profiles.active === "" ? "No profile on" : Profiles.active + " is on"
            sub: Profiles.active === "" ? "" : Profiles.status()
            keywords: "focus profile active"
            value: ""
        }
        SettingsButton {
            label: "End it"
            sub: "Put back what it changed"
            keywords: "focus profile end stop"
            enabled: Profiles.active !== ""
            text: "End " + (Profiles.active || "focus")
            onClicked: Profiles.end()
        }
    }
    Repeater {
        model: pg.names
        SettingsCard {
            id: card
            required property var modelData
            readonly property var p: Profiles.find(modelData) || ({ name: modelData, apps: [], desk: 0 })
            readonly property bool on: Profiles.active === p.name
            title: p.name
            note: on ? "on now" : Profiles.describe(p)
            SettingsButton {
                label: card.on ? "On now" : "Start " + card.p.name
                keywords: "focus profile apply start " + card.p.name
                text: card.on ? "End" : "Start"
                lit: card.on
                onClicked: card.on ? Profiles.end() : Profiles.apply(card.p.name)
            }
            Repeater {
                model: Profiles.fields
                SettingsChoice {
                    required property var modelData
                    label: modelData.label
                    keywords: "focus profile " + card.p.name + " " + modelData.key
                    chipWidth: 76
                    options: modelData.values.map(v => [v, v === "leave" ? "Leave" : pg.cap(v)])
                    value: card.p[modelData.key]
                    onEdited: v => Profiles.edit(card.p.name, modelData.key, v)
                }
            }
            SettingsChips {
                label: "Apps to open"
                sub: "Desktop ids (firefox, org.gnome.Nautilus); add @N to open one on desktop N"
                keywords: "focus profile apps open launch " + card.p.name
                placeholder: "add an app…"
                valid: t => /^[A-Za-z0-9._-]+(@\d+)?$/.test(t)
                items: card.p.apps
                onEdited: l => Profiles.edit(card.p.name, "apps", l)
            }
            SettingsStepper {
                label: "Go to desktop"
                keywords: "focus profile desk desktop workspace " + card.p.name
                value: card.p.desk
                from: 0; to: 10
                text: card.p.desk === 0 ? "stay" : String(card.p.desk)
                onEdited: v => Profiles.edit(card.p.name, "desk", v)
            }
            SettingsButton {
                label: "Remove this profile"
                keywords: "focus profile delete " + card.p.name
                enabled: !card.on
                text: "Remove"
                confirm: "removes " + card.p.name
                onClicked: Profiles.remove(card.p.name)
            }
        }
    }
    SettingsCard {
        title: "New profile"
        SettingsText {
            label: "Name"
            sub: "Starts with every switch on Leave"
            keywords: "focus profile add new create"
            value: ""
            placeholder: "e.g. Meetings"
            valid: t => t !== "" && !Profiles.find(t)
            onEdited: t => { Profiles.add(t); input.text = "" }
        }
    }
}
