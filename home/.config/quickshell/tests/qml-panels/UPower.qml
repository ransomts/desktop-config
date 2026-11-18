pragma Singleton
// Test stand-in for Quickshell.Services.UPower's UPower (qml-panels-test; the runner takes the real
// import out of its copy of BatteryWarn.qml).
import QtQuick
import Quickshell

Singleton {
    property bool onBattery: false
    readonly property QtObject displayDevice: QtObject {
        property bool ready: true
        property bool isLaptopBattery: true
        property real percentage: 0.8          // 0..1, as Quickshell gives it
    }
}
