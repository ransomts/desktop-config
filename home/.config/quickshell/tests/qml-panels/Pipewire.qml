pragma Singleton
// Test stand-in for Quickshell.Services.Pipewire's Pipewire (qml-panels-test; the runner takes the
// real import out of its copy of Mixer.qml). Nodes are plain objects the test builds.
import QtQuick
import Quickshell

Singleton {
    readonly property QtObject nodes: QtObject { property var values: [] }
    property var preferredDefaultAudioSink: null
    property var preferredDefaultAudioSource: null
}
