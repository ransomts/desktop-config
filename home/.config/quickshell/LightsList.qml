// The light pill's popup (Bar.qml "lights"): all on / off, the presets, the full controls.
// Lights.qml does the work; this only lists it.
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: list
    signal done()
    spacing: 4
    Caption { text: "Lights: " + (Lights.busy ? "working…" : Lights.stateText()) }
    MenuRow {
        label: "All on"
        current: Lights.allOn
        onClicked: { Lights.on(); list.done() }
    }
    MenuRow {
        label: "All off"
        current: Lights.allOff
        onClicked: { Lights.off(); list.done() }
    }
    Caption { visible: Lights.presets.length > 0; text: "Presets"; Layout.topMargin: 6 }
    Repeater {
        model: Lights.presets
        MenuRow {
            required property var modelData
            label: modelData.name
            onClicked: { Lights.preset(modelData.name); list.done() }
        }
    }
    Caption {
        visible: Lights.error !== ""
        text: Lights.error
        color: Theme.warn
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.topMargin: 6
    }
    MenuRow {
        Layout.topMargin: 6
        label: "Full controls…"
        detail: "Super+Ctrl+L"
        onClicked: { Lights.openWindow(); list.done() }
    }
}
