// System76 power profile.
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: prof
    signal done()
    spacing: 4
    Caption { text: "Power profile" }
    Repeater {
        model: ["Battery", "Balanced", "Performance"]
        MenuRow {
            required property string modelData
            label: modelData
            current: Sys.profile.cls === modelData.toLowerCase()
            onClicked: {
                Sys.run("system76-power profile " + modelData.toLowerCase())
                prof.done()
            }
        }
    }
}
