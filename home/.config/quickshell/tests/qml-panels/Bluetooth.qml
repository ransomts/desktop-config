pragma Singleton
// Test stand-in for Quickshell.Bluetooth's Bluetooth (qml-panels-test; the runner takes the real
// import out of its copy of BluetoothList.qml). The test sets defaultAdapter (or null).
import QtQuick
import Quickshell

Singleton {
    property var defaultAdapter: null
}
