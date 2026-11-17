// What's playing, with cover art and previous / play-pause / next.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

RowLayout {
    id: card
    readonly property var player: Sys.player
    visible: player !== null && (player.trackTitle || "") !== ""
    spacing: 12

    Rectangle {
        implicitWidth: 56; implicitHeight: 56
        radius: 8
        color: Theme.track
        clip: true
        Image {
            anchors.fill: parent
            source: card.player ? (card.player.trackArtUrl || "") : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
        }
        Text {
            anchors.centerIn: parent
            visible: !card.player || (card.player.trackArtUrl || "") === ""
            text: Icons.playerDefault
            color: Theme.faint
            font { family: Theme.font; pixelSize: 22 }
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        Text {
            Layout.fillWidth: true
            text: card.player ? card.player.trackTitle : ""
            elide: Text.ElideRight
            color: Theme.fg
            font { family: Theme.font; pixelSize: 13; bold: true }
        }
        Caption {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: card.player ? (card.player.trackArtist || card.player.identity || "") : ""
        }
        Row {
            spacing: 6
            Layout.topMargin: 2
            Repeater {
                model: [
                    { label: "◀◀", act: "prev" },
                    { label: "", act: "toggle" },
                    { label: "▶▶", act: "next" }
                ]
                Rectangle {
                    id: b
                    required property var modelData
                    width: 40; height: 24; radius: 7
                    color: tap.containsMouse ? Theme.hover : Theme.track
                    Text {
                        anchors.centerIn: parent
                        text: b.modelData.act === "toggle" ? (card.player && card.player.isPlaying ? Icons.paused : Icons.playing) : b.modelData.label
                        color: Theme.fg
                        font { family: Theme.font; pixelSize: b.modelData.act === "toggle" ? 14 : 9 }
                    }
                    MouseArea {
                        id: tap
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            const p = card.player
                            if (!p) return
                            if (b.modelData.act === "prev" && p.canGoPrevious) p.previous()
                            else if (b.modelData.act === "next" && p.canGoNext) p.next()
                            else if (b.modelData.act === "toggle" && p.canTogglePlaying) p.togglePlaying()
                        }
                    }
                }
            }
        }
    }
}
