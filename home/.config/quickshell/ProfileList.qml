// System76 power profile, and below it where charging stops (Charge.qml).
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
    Caption { text: "Charge limit"; Layout.topMargin: 6 }
    MenuRow {
        label: "Stop at " + Charge.cap + "%"
        current: Charge.capped
        onClicked: { Charge.set("cap"); prof.done() }
    }
    MenuRow {       // a limit set elsewhere (Settings, the control panel): shown so the list always has the current one
        visible: Charge.limited && !Charge.capped
        label: Charge.label
        current: true
    }
    MenuRow {
        label: "Full charge"
        current: Charge.loaded && !Charge.limited
        onClicked: { Charge.set("full_charge"); prof.done() }
    }
    Component.onCompleted: Charge.refresh()     // the limit may have been changed outside the shell
}
