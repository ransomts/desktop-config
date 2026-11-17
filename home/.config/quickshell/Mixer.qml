// Sound: pick the output, set its level, and set the level of each app playing; then the
// same for the microphone.
// Used in the control panel and in the popup under the volume pill.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

ColumnLayout {
    id: mixer
    spacing: 8

    readonly property var outputs: Pipewire.nodes.values.filter(n => !n.isStream && n.isSink && n.audio)
    // playback streams, minus the screen reader's silent placeholder
    readonly property var apps: Pipewire.nodes.values.filter(n => n.isStream && n.audio
        && (n.type & PwNodeType.AudioOutStream) === PwNodeType.AudioOutStream && !/speech-dispatcher/.test(appName(n)))
    readonly property var inputs: Pipewire.nodes.values.filter(n => !n.isStream && !n.isSink && n.audio)
    PwObjectTracker { objects: mixer.apps }

    function appName(n) {
        const p = n.properties || {}
        return p["application.name"] || n.description || n.nickname || n.name
    }

    Caption { text: "Output" }
    Repeater {
        model: mixer.outputs
        Rectangle {
            id: row
            required property var modelData
            readonly property bool current: Sys.sink !== null && Sys.sink.id === modelData.id
            Layout.fillWidth: true
            implicitHeight: 28
            radius: 8
            color: current ? Theme.accentBg : pick.containsMouse ? Theme.hover : "transparent"
            Text {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                text: row.modelData.description || row.modelData.name
                elide: Text.ElideRight
                color: row.current ? Theme.accentInk : Theme.fg
                font { family: Theme.font; pixelSize: 12 }
            }
            MouseArea { id: pick; anchors.fill: parent; hoverEnabled: true; onClicked: Pipewire.preferredDefaultAudioSink = row.modelData }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Caption { text: "Volume" }
        Item { Layout.fillWidth: true }
        Caption {
            color: Theme.fg
            text: !Sys.sink || !Sys.sink.audio ? "no output" : Sys.sink.audio.muted ? "muted" : Math.round(Sys.sink.audio.volume * 100) + "%"
        }
    }
    Slider {
        Layout.fillWidth: true
        value: Sys.sink && Sys.sink.audio ? Sys.sink.audio.volume : 0
        off: !!Sys.sink && !!Sys.sink.audio && Sys.sink.audio.muted
        onMoved: v => { if (Sys.sink && Sys.sink.audio) Sys.sink.audio.volume = v }
        onRightClicked: if (Sys.sink && Sys.sink.audio) Sys.sink.audio.muted = !Sys.sink.audio.muted
    }

    Caption { text: "Apps"; visible: mixer.apps.length > 0; Layout.topMargin: 4 }
    Repeater {
        model: mixer.apps
        ColumnLayout {
            id: app
            required property var modelData
            Layout.fillWidth: true
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: mixer.appName(app.modelData)
                    elide: Text.ElideRight
                    color: Theme.fg
                    font { family: Theme.font; pixelSize: 12 }
                }
                Caption { text: app.modelData.audio.muted ? "muted" : Math.round(app.modelData.audio.volume * 100) + "%" }
            }
            Slider {
                Layout.fillWidth: true
                implicitHeight: 10
                value: app.modelData.audio.volume
                off: app.modelData.audio.muted
                onMoved: v => app.modelData.audio.volume = v
                onRightClicked: app.modelData.audio.muted = !app.modelData.audio.muted
            }
        }
    }

    Caption { text: "Microphone"; Layout.topMargin: 4; visible: mixer.inputs.length > 0 }
    Repeater {
        model: mixer.inputs.length > 1 ? mixer.inputs : []
        Rectangle {
            id: inRow
            required property var modelData
            readonly property bool current: Sys.source !== null && Sys.source.id === modelData.id
            Layout.fillWidth: true
            implicitHeight: 28
            radius: 8
            color: current ? Theme.accentBg : inPick.containsMouse ? Theme.hover : "transparent"
            Text {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                text: inRow.modelData.description || inRow.modelData.name
                elide: Text.ElideRight
                color: inRow.current ? Theme.accentInk : Theme.fg
                font { family: Theme.font; pixelSize: 12 }
            }
            MouseArea { id: inPick; anchors.fill: parent; hoverEnabled: true; onClicked: Pipewire.preferredDefaultAudioSource = inRow.modelData }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        visible: !!Sys.source && !!Sys.source.audio
        Text {
            Layout.fillWidth: true
            text: Sys.source ? (Sys.source.description || Sys.source.name) : ""
            visible: mixer.inputs.length <= 1
            elide: Text.ElideRight
            color: Theme.fg
            font { family: Theme.font; pixelSize: 12 }
        }
        Item { Layout.fillWidth: true; visible: mixer.inputs.length > 1 }
        Caption {
            color: Theme.fg
            text: !Sys.source || !Sys.source.audio ? "" : Sys.source.audio.muted ? "muted" : Math.round(Sys.source.audio.volume * 100) + "%"
        }
    }
    Slider {
        Layout.fillWidth: true
        visible: !!Sys.source && !!Sys.source.audio
        value: Sys.source && Sys.source.audio ? Sys.source.audio.volume : 0
        off: !!Sys.source && !!Sys.source.audio && Sys.source.audio.muted
        onMoved: v => { if (Sys.source && Sys.source.audio) Sys.source.audio.volume = v }
        onRightClicked: if (Sys.source && Sys.source.audio) Sys.source.audio.muted = !Sys.source.audio.muted
    }
}
