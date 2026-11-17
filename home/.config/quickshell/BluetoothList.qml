// Paired Bluetooth devices: click to connect or disconnect.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

ColumnLayout {
    id: bt
    signal done()
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: !adapter ? [] : adapter.devices.values.filter(d => d.paired || d.connected)
        .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        Caption { text: "Bluetooth" }
        Item { Layout.fillWidth: true }
        Caption {
            visible: bt.adapter !== null
            text: bt.adapter && bt.adapter.enabled ? "Turn off" : "Turn on"
            color: powerTap.containsMouse ? Theme.accent : Theme.faint
            MouseArea { id: powerTap; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: bt.adapter.enabled = !bt.adapter.enabled }
        }
    }
    Caption { visible: bt.adapter === null; text: "No Bluetooth adapter" }
    Caption { visible: bt.adapter !== null && !bt.adapter.enabled; text: "Bluetooth is off" }
    Repeater {
        model: bt.adapter && bt.adapter.enabled ? bt.devices : []
        MenuRow {
            required property var modelData
            label: modelData.name || modelData.address
            detail: (modelData.connected ? "connected" : "") + (modelData.connected && modelData.batteryAvailable ? "  " + Math.round(modelData.battery * 100) + "%" : "")
            current: modelData.connected
            onClicked: { if (modelData.connected) modelData.disconnect(); else modelData.connect() }
        }
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line; Layout.topMargin: 4; Layout.bottomMargin: 4 }
    MenuRow { label: "Bluetooth manager…"; onClicked: { Sys.run("blueman-manager"); bt.done() } }
}
