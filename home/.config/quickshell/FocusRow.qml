// The focus profiles as one row of chips, for the control panel (Panel.qml hook): a chip per
// profile (Profiles.list), lit while it is on; a click starts it, a click on the lit one ends it.
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: fr
    Layout.fillWidth: true
    spacing: 8
    Text {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: 7
        text: "Focus"
        color: Theme.faint
        font { family: Theme.font; pixelSize: 12 }
    }
    // two to a row: four names beside "Focus" in one row cut "Presenting" short (Fit.qml, 2026-11-17)
    GridLayout {
        Layout.fillWidth: true
        columns: 2; columnSpacing: 8; rowSpacing: 8
        Repeater {
            model: Profiles.list
            SettingsChip {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                label: modelData.name
                on: Profiles.active === modelData.name
                onClicked: on ? Profiles.end() : Profiles.apply(modelData.name)
            }
        }
    }
}
