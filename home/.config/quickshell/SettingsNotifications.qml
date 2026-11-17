// Settings > Notifications: Notif.dnd / setDnd, the per-app rules (Notif.apps, setRule:
// notif-rules.json), the snoozed ones (Notif.snoozed, wakeSnoozed), and a pointer to Quiet hours.
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: pg
    pageId: "notifications"
    title: "Notifications"
    // the apps, as a list that only changes when an app comes or goes (not on every rule or count),
    // so the rows are not rebuilt (and keyboard focus kept) when a rule is picked
    property var appNames: []
    readonly property string appKey: Notif.apps.map(a => a.app).join("\n")
    onAppKeyChanged: appNames = Notif.apps.map(a => a.app)
    Component.onCompleted: appNames = Notif.apps.map(a => a.app)
    function countOf(app) { const a = Notif.apps.find(x => x.app === app); return a ? a.count : 0 }

    SettingsCard {
        title: "Now"
        SettingsSwitch {
            label: "Do Not Disturb"
            sub: Notif.dnd ? "Only critical ones pop up; the rest wait in the list" : "Notifications pop up"
            keywords: "dnd silence quiet mute"
            checked: Notif.dnd
            onEdited: on => Notif.setDnd(on)
        }
        SettingsButton {
            label: "Snoozed"
            sub: Notif.snoozed.length === 0 ? "None waiting" : Notif.snoozed.length + (Notif.snoozed.length === 1 ? " notification comes back later" : " notifications come back later")
            keywords: "snooze later remind"
            enabled: Notif.snoozed.length > 0
            text: "Bring back now"
            onClicked: Notif.wakeSnoozed()
        }
        SettingsButton {
            label: "Silence during classes and meetings"
            sub: Quiet.enabled ? "Quiet hours: " + Quiet.status() : "Quiet hours are off"
            keywords: "quiet calendar lecture"
            text: "Quiet hours ›"
            onClicked: pg.win.page = "quiet"
        }
    }
    SettingsCard {
        title: "Per app"
        note: "Normal · List only (no popup) · Mute (dropped, unless critical)"
        Caption {
            visible: pg.appNames.length === 0
            Layout.fillWidth: true
            text: "No app has sent a notification yet."
        }
        Repeater {
            model: pg.appNames
            SettingsChoice {
                required property var modelData
                readonly property int count: pg.countOf(modelData)
                label: modelData || "(no name)"
                sub: count === 0 ? "nothing in the list now" : count + " in the list"
                keywords: "rule app mute list"
                options: [["normal", "Normal"], ["list", "List only"], ["mute", "Mute"]]
                value: Notif.ruleFor(modelData)
                onEdited: v => Notif.setRule(modelData, v)
            }
        }
    }
}
