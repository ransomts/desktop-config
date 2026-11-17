// The "Reminders" page of the pet's menu (PetMenu.qml): the pending reminders (click one to
// cancel it) and rows to set a new one. The new ones ask for their note (and the "At a
// time..." row for the time first) with ~/.local/bin/pet-remind, which uses qs-pick.
// Opening this page counts as having seen the reminder the pet is showing you.
// While Do Not Disturb is on the notes are hidden (the screen may be shared).
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    property bool open: false               // this is the page being shown
    signal done()                           // close the menu (before the text box opens)
    visible: open
    onOpenChanged: if (open) PetRemind.done()
    Component.onCompleted: if (open) PetRemind.done()
    Layout.fillWidth: true
    spacing: 4

    Caption {
        Layout.fillWidth: true
        text: PetRemind.count === 0 ? "No reminders set" : "Click one to cancel it"
    }
    Repeater {
        model: page.open ? PetRemind.pending : []
        MenuRow {
            required property var modelData
            label: Notif.dnd ? "(note hidden)" : modelData.note
            detail: PetRemind.whenText(modelData) + " ✕"
            onClicked: PetRemind.cancel(modelData.id)
        }
    }
    Repeater {
        model: page.open ? [["In 10 minutes", "10m"], ["In 30 minutes", "30m"], ["In 1 hour", "1h"]] : []
        MenuRow {
            required property var modelData
            label: modelData[0]
            detail: "›"
            onClicked: { page.done(); Sys.run(Sys.bin + "pet-remind " + modelData[1]) }
        }
    }
    MenuRow {
        visible: page.open
        label: "At a time..."
        detail: "›"
        onClicked: { page.done(); Sys.run(Sys.bin + "pet-remind") }
    }
}
