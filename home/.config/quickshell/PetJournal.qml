// The Journal page of the pet's menu (PetMenu.qml): how long you have been together, what
// you have done with it, the milestone it is nearest, and the last few lines of its diary
// (all kept by PetArc.qml). Nothing here is clickable. Details stay short: the popup is
// 290 px wide and a detail is never cut.
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: journal
    spacing: 2
    onVisibleChanged: if (visible) PetArc.markSeen()
    Component.onCompleted: if (visible) PetArc.markSeen()

    component Line: RowLayout {
        id: line
        property string label
        property string detail
        Layout.fillWidth: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        Layout.preferredHeight: 24
        spacing: 8
        Text {
            Layout.fillWidth: true
            text: line.label
            elide: Text.ElideRight
            color: Theme.fg
            font { family: Theme.font; pixelSize: 13 }
        }
        Text {
            visible: line.detail !== ""
            text: line.detail
            color: Theme.faint
            font { family: Theme.font; pixelSize: 11 }
        }
    }

    Line { label: "Together"; detail: PetArc.daysText + ", since " + PetArc.since }
    Line { label: "Pats, meals, games"; detail: PetArc.counts.pats + ", " + PetArc.counts.meals + ", " + PetArc.counts.games }
    Line { label: "Tricks, focus timers"; detail: PetArc.counts.tricks + ", " + PetArc.counts.focus }
    Line { visible: PetFocus.doneToday > 0 || PetFocus.cycle; label: "Focus today"; detail: PetFocus.doneToday + (PetFocus.cycle ? ", round " + PetFocus.round + " of 4" : "") }
    Line { visible: PetArc.hats.length > 0; label: "Hats earned"; detail: PetArc.hats.join(", ") }
    Line { visible: PetSecrets.count > 0; label: "Secrets found"; detail: PetSecrets.summary }      // which ones: PetSecrets.qml
    Line { visible: PetArc.next !== null; label: "Next: " + PetArc.nextLabel; detail: PetArc.nextDetail }

    Caption { Layout.leftMargin: 10; Layout.topMargin: 6; text: "Diary" }
    Repeater {
        model: PetArc.entries.slice(0, 6)
        RowLayout {
            id: entry
            required property var modelData
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            spacing: 8
            Text {
                Layout.preferredWidth: 52
                Layout.alignment: Qt.AlignTop
                text: PetArc.pretty(entry.modelData.d, true)
                color: Theme.faint
                font { family: Theme.font; pixelSize: 11 }
            }
            Text {
                Layout.fillWidth: true
                text: entry.modelData.t
                wrapMode: Text.Wrap
                color: Theme.fg
                font { family: Theme.font; pixelSize: 12 }
            }
        }
    }
}
