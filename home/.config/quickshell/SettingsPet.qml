// Settings > Pet: the main switches (Pet.qml), its sounds (PetSound.qml) and three habits
// (PetPrefs.qml, choices and labels from there). Everything else is in its own menu.
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: pg
    pageId: "pet"
    title: "Pet"

    SettingsCard {
        title: Pet.name
        SettingsSwitch {
            label: "On the bar"
            keywords: "pet cub tiger show hide"
            checked: Pet.enabled
            onEdited: on => Pet.setEnabled(on)
        }
        SettingsSwitch {
            label: "Calm"
            sub: "No wandering, chasing, moths or thought bubbles"
            keywords: "pet quiet still"
            checked: Pet.calm
            onEdited: on => Pet.setCalm(on)
        }
        SettingsSwitch {
            label: "Chase the pointer"
            keywords: "pet mouse"
            checked: Pet.chase
            onEdited: on => Pet.setChase(on)
        }
        SettingsSwitch {
            label: "Come down to an empty desktop"
            keywords: "pet roam desk wallpaper"
            checked: Pet.roam
            onEdited: on => Pet.setRoam(on)
        }
        SettingsSwitch {
            label: "Hide while sharing the screen"
            keywords: "pet shy camera capture"
            checked: Pet.shy
            onEdited: on => Pet.setShy(on)
        }
    }
    SettingsCard {
        title: "Sounds and habits"
        SettingsSwitch {
            label: "Its sounds"
            sub: !Sys.sounds ? "The shell's sounds are off (Bar and island)" : "Plays one when turned on"
            keywords: "pet audio meow"
            checked: PetSound.enabled
            onEdited: on => PetSound.setEnabled(on)
        }
        SettingsChoice {
            label: "Sound level"
            keywords: "pet volume"
            enabled: PetSound.enabled
            options: PetSound.levelNames.map(n => [n, n.charAt(0).toUpperCase() + n.slice(1)])
            value: PetSound.level
            onEdited: v => PetSound.setLevel(v)
        }
        Repeater {
            model: [["lively", "Liveliness", "How often it does something when idle"],
                    ["bedtime", "Bedtime", "It sleeps from then until it wakes"],
                    ["meeting", "Meeting reminder", "Runs to the clock this long before an event"]]
            SettingsChoice {
                required property var modelData
                label: modelData[1]
                sub: modelData[2]
                keywords: "pet habit " + modelData[0]
                wrapWidth: 340
                options: PetPrefs.choices[modelData[0]].map(c => [c, PetPrefs.label(modelData[0], c)])
                value: PetPrefs[modelData[0]]
                onEdited: v => PetPrefs.setHabit(modelData[0], v)
            }
        }
        SettingsButton {
            label: "Looks, tricks, reminders and the rest"
            sub: "Its own menu (right-click the pet)"
            keywords: "pet menu habits coat hat friend"
            text: "Open its menu ›"
            onClicked: { pg.win.visible = false; Pet.menuPage = "settings"; Sys.popupRequest("pet") }
        }
    }
}
