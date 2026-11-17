// The pet menu's focus page (PetMenu.qml), the rows that go with PetFocus.qml.
// While nothing runs: a row that starts a work and break cycle (PetMenu.qml lists the single
// timer lengths above it). While something runs: what it is, minutes left, the round, a skip
// and a stop. The caption above says the round and today's count.
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    signal done()
    spacing: 4

    // ---- nothing running ----
    MenuRow {
        visible: !PetFocus.active
        label: PetFocus.cycleLabel
        detail: "then " + PetPrefs.longbreak + " after 4"
        onClicked: { PetFocus.startCycle(); page.done() }
    }

    // ---- running ----
    MenuRow {
        visible: PetFocus.focusing || PetFocus.onBreak
        label: PetFocus.focusing ? "Focus" : PetFocus.longBreak ? "Long break" : "Break"
        detail: PetFocus.left + " min left"
    }
    MenuRow {
        visible: PetFocus.cycle
        label: "Round"
        detail: PetFocus.round + " of 4"
    }
    MenuRow {
        visible: PetFocus.waiting
        label: "Start round " + PetFocus.round
        detail: PetFocus.mins(PetFocus.workMin) + " min"
        onClicked: { PetFocus.resume(); page.done() }
    }
    MenuRow {
        visible: PetFocus.cycle && PetFocus.focusing
        label: "Skip to break"
        onClicked: { PetFocus.skip(); page.done() }
    }
    MenuRow {
        visible: PetFocus.onBreak
        label: "Skip break"
        onClicked: { PetFocus.skip(); page.done() }
    }
    MenuRow {
        visible: PetFocus.active
        label: "Stop"
        detail: PetFocus.cycle ? "ends the cycle" : ""
        onClicked: { PetFocus.stop(); page.done() }
    }
}
