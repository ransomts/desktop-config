// Right-click menu of the bar pet (Pet.qml). The main list is what you do with it;
// "Tricks", "Focus timer", "Looks" and "Settings" swap the list for a second one,
// and "Back" returns. Keep the right-hand details short: the popup is 290 px wide
// and a detail is never cut, so a long one pushes the label out.
// (`qs ipc call pet menu PAGE` opens it on a page: tricks | focus | looks | settings.)
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: menu
    signal done()
    property string page: Pet.menuPage      // "" (main) | tricks | focus | looks | settings
    property string screenKey: ""           // the screen whose bar this menu is on
    readonly property bool main: page === ""
    Component.onDestruction: Pet.menuPage = ""
    spacing: 4
    Caption {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: menu.page === "tricks" ? Pet.name + ", ..." : menu.page === "focus" ? PetFocus.caption
              : menu.page === "looks" || menu.page === "habits" ? "Each click steps to the next" : menu.page === "settings" ? "How " + Pet.name + " behaves"
              : Pet.name + " is " + Pet.doing + "\nBond " + Pet.hearts
    }

    // ---- main ----
    MenuRow { visible: menu.main; label: "What's up?"; detail: PetSay.alarm ? "! ›" : "›"; onClicked: menu.page = "say" }    // a briefing (PetSay.qml)
    MenuRow { visible: menu.main; label: "Pet"; onClicked: { Pet.petIt(); menu.done() } }
    MenuRow { visible: menu.main; label: "Feed"; detail: Pet.hungry ? "peckish" : ""; onClicked: { Pet.giveFood(); menu.done() } }
    MenuRow { visible: menu.main; label: "Play ball"; onClicked: { Pet.playWith(); menu.done() } }
    MenuRow { visible: menu.main && PetScore.here; label: PetScore.running ? "Stop the game" : "Play a game"; detail: PetScore.best > 0 ? "best " + PetScore.best : ""; onClicked: { PetScore.toggle(); menu.done() } }     // treat catch (PetGame.qml), only on the desktop
    MenuRow { visible: menu.main; label: "Tricks"; detail: "›"; onClicked: menu.page = "tricks" }
    MenuRow {
        visible: menu.main
        label: PetFocus.mainLabel           // a single timer, or a work and break cycle (PetFocus.qml)
        detail: PetFocus.mainDetail
        onClicked: { if (Pet.focusing && !PetFocus.cycle) { Pet.startFocus(0); menu.done() } else menu.page = "focus" }
    }
    MenuRow {
        visible: menu.main
        label: Pet.napping ? "Wake up" : "Nap"
        onClicked: { Pet.napping = !Pet.napping; menu.done() }
    }
    MenuRow { visible: menu.main; label: "Reminders"; detail: (PetRemind.count > 0 ? PetRemind.count + " " : "") + "›"; onClicked: menu.page = "remind" }    // PetRemind.qml
    MenuRow { visible: menu.main; label: "Journal"; detail: (PetArc.unseen ? "★ " : "") + PetArc.daysText + " ›"; onClicked: menu.page = "journal" }
    MenuRow { visible: menu.main; label: "Looks"; detail: Pet.animal + ", " + Pet.coat + " ›"; onClicked: menu.page = "looks" }
    MenuRow { visible: menu.main; label: "Settings"; detail: "›"; onClicked: menu.page = "settings" }

    // ---- tricks ----
    Repeater {
        model: menu.page === "tricks" ? Pet.tricks : []
        MenuRow {
            required property string modelData
            label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
            onClicked: { Pet.trick(modelData); menu.done() }
        }
    }

    // ---- focus timer lengths ----
    Repeater {
        model: menu.page === "focus" && !PetFocus.active ? [15, 25, 45, 60] : []
        MenuRow {
            required property int modelData
            label: modelData + " minutes"
            onClicked: { Pet.startFocus(modelData); menu.done() }
        }
    }

    PetFocusPage { visible: menu.page === "focus"; Layout.fillWidth: true; onDone: menu.done() }     // cycles: start, skip, stop

    // ---- looks ----
    MenuRow { visible: menu.page === "looks"; label: "Animal"; detail: Pet.animal + " ›"; onClicked: Pet.nextAnimal() }
    MenuRow { visible: menu.page === "looks"; label: "Coat"; detail: (PetSecrets.costume !== "" ? PetSecrets.costume + " today" : Pet.coat) + " ›"; onClicked: Pet.nextCoat() }
    MenuRow {
        visible: menu.page === "looks"
        label: "Hat"
        detail: (Pet.hatChoice === "auto" ? (Pet.hat !== "" ? "auto: " + Pet.hat : "auto") : Pet.hatChoice) + " ›"
        onClicked: Pet.nextHat()
    }
    MenuRow { visible: menu.page === "looks"; label: "Friend"; detail: (Pet.friend === "" ? "none" : Pet.friend) + " ›"; onClicked: Pet.nextFriend() }
    MenuRow { visible: menu.page === "looks" && Pet.friend !== ""; label: "Friend's coat"; detail: Pet.friendCoat + " ›"; onClicked: Pet.nextFriendCoat() }
    MenuRow {
        visible: menu.page === "looks"
        label: "Rename"
        detail: Pet.name
        onClicked: { menu.done(); Sys.run(Sys.bin + "pet-rename") }
    }

    // ---- settings ----
    MenuRow {
        visible: menu.page === "settings"
        label: "Calm"                       // no wandering, chasing, moths or thought bubbles
        detail: Pet.calm ? "on" : "off"
        onClicked: Pet.setCalm(!Pet.calm)
    }
    MenuRow {
        visible: menu.page === "settings"
        label: "Chase the pointer"
        detail: Pet.chase ? "on" : "off"
        onClicked: Pet.setChase(!Pet.chase)
    }
    MenuRow {
        visible: menu.page === "settings"
        label: "Desktop when empty"         // comes down from the bar onto an empty desktop
        detail: Pet.roam ? "on" : "off"
        onClicked: Pet.setRoam(!Pet.roam)
    }
    MenuRow {
        visible: menu.page === "settings"
        label: "Stay on this screen"
        detail: Pet.pin === menu.screenKey ? "on" : Pet.pinOk ? "other screen" : "off"
        onClicked: Pet.setPin(Pet.pin === menu.screenKey ? "" : menu.screenKey)
    }
    MenuRow {
        visible: menu.page === "settings"
        label: "Hide while sharing"
        detail: Pet.shy ? "on" : "off"
        onClicked: Pet.setShy(!Pet.shy)
    }
    MenuRow { visible: menu.page === "settings"; label: "Habits"; detail: "›"; onClicked: menu.page = "habits" }     // bedtime, reminders, liveliness (PetPrefs.qml)
    MenuRow { visible: menu.page === "settings"; label: "Sign"; detail: PetSign.label + " ›"; onClicked: PetSign.nextSign() }     // one thing at a glance (PetSign.qml)
    MenuRow {
        visible: menu.page === "settings"
        label: "Sounds"                     // PetSound.qml: off unless turned on here
        detail: !PetSound.enabled ? "off" : Sys.sounds ? "on" : "shell muted"
        onClicked: PetSound.setEnabled(!PetSound.enabled)
    }
    MenuRow {
        visible: menu.page === "settings" && PetSound.enabled
        label: "Sound level"
        detail: PetSound.level + " ›"
        onClicked: PetSound.nextLevel()
    }
    MenuRow {
        visible: menu.page === "settings"
        label: "Hide"
        detail: "undo in Super+C"
        onClicked: { Pet.setEnabled(false); menu.done() }
    }

    // ---- habits (PetPrefs.qml): each click steps to the next choice ----
    MenuRow { visible: menu.page === "habits"; label: "Bedtime"; detail: PetPrefs.label("bedtime", PetPrefs.bedtime) + " ›"; onClicked: PetPrefs.nextHabit("bedtime") }
    MenuRow { visible: menu.page === "habits" && PetPrefs.bedtime !== "never"; label: "Wakes at"; detail: PetPrefs.label("wake", PetPrefs.wake) + " ›"; onClicked: PetPrefs.nextHabit("wake") }
    MenuRow { visible: menu.page === "habits"; label: "Meeting reminder"; detail: PetPrefs.label("meeting", PetPrefs.meeting) + " ›"; onClicked: PetPrefs.nextHabit("meeting") }
    MenuRow { visible: menu.page === "habits"; label: "Liveliness"; detail: PetPrefs.label("lively", PetPrefs.lively) + " ›"; onClicked: PetPrefs.nextHabit("lively") }
    MenuRow { visible: menu.page === "habits"; label: "Waits by the bell"; detail: PetPrefs.label("bell", PetPrefs.bell) + " ›"; onClicked: PetPrefs.nextHabit("bell") }
    MenuRow { visible: menu.page === "habits"; label: "Hungry after"; detail: PetPrefs.label("hunger", PetPrefs.hunger) + " ›"; onClicked: PetPrefs.nextHabit("hunger") }
    MenuRow { visible: menu.page === "habits"; label: "Focus length"; detail: PetPrefs.label("work", PetPrefs.work) + " ›"; onClicked: PetPrefs.nextHabit("work") }
    MenuRow { visible: menu.page === "habits"; label: "Break"; detail: PetPrefs.label("shortbreak", PetPrefs.shortbreak) + " ›"; onClicked: PetPrefs.nextHabit("shortbreak") }
    MenuRow { visible: menu.page === "habits"; label: "Long break"; detail: PetPrefs.label("longbreak", PetPrefs.longbreak) + " ›"; onClicked: PetPrefs.nextHabit("longbreak") }
    MenuRow { visible: menu.page === "habits"; label: "Next round"; detail: PetPrefs.label("carryon", PetPrefs.carryon) + " ›"; onClicked: PetPrefs.nextHabit("carryon") }
    MenuRow { visible: menu.page === "habits"; label: "Do Not Disturb in focus"; detail: PetPrefs.label("focusdnd", PetPrefs.focusdnd) + " ›"; onClicked: PetPrefs.nextHabit("focusdnd") }
    MenuRow { visible: menu.page === "habits"; label: "Reset habits"; detail: PetPrefs.isDefault ? "all default" : ""; onClicked: PetPrefs.reset() }

    PetJournal { visible: menu.page === "journal"; Layout.fillWidth: true }      // days together, counts, diary (PetArc.qml)

    PetBrief { open: menu.page === "say" }

    PetRemindPage { open: menu.page === "remind"; onDone: menu.done() }     // pending reminders and new ones (PetRemind.qml)

    MenuRow { visible: !menu.main; label: "Back"; detail: "‹"; onClicked: menu.page = menu.page === "habits" ? "settings" : "" }
}
