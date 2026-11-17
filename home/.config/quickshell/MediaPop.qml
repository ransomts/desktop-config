// Player card that drops from the bar's music pill (right-click the pill):
// cover, title / artist / album, a seek bar, previous / play-pause / next,
// the player's own volume, and which player the pill follows when several run.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

ColumnLayout {
    id: card
    readonly property var player: Sys.player
    spacing: 12

    function clock(s) {
        s = Math.max(0, Math.floor(s))
        return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 14
        Rectangle {
            implicitWidth: 96; implicitHeight: 96
            radius: 10
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
                font { family: Theme.font; pixelSize: 34 }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3
            Text {
                Layout.fillWidth: true
                text: card.player ? (card.player.trackTitle || "Nothing playing") : "Nothing playing"
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Theme.fg
                font { family: Theme.font; pixelSize: 14; bold: true }
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.player ? (card.player.trackArtist || "") : ""
                elide: Text.ElideRight
                color: Theme.accent
                font { family: Theme.font; pixelSize: 12 }
            }
            Caption {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.player ? (card.player.trackAlbum || "") : ""
                elide: Text.ElideRight
            }
        }
    }

    // seek
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        visible: card.player !== null && card.player.lengthSupported && card.player.length > 0
        Slider {
            Layout.fillWidth: true
            value: card.player && card.player.length > 0 ? Math.min(1, card.player.position / card.player.length) : 0
            onMoved: v => { if (card.player && card.player.canSeek) card.player.position = v * card.player.length }
        }
        RowLayout {
            Layout.fillWidth: true
            Caption { text: card.player ? card.clock(card.player.position) : "" }
            Item { Layout.fillWidth: true }
            Caption { text: card.player ? card.clock(card.player.length) : "" }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: ["prev", "toggle", "next"]
            Rectangle {
                id: b
                required property string modelData
                Layout.fillWidth: true
                Layout.preferredWidth: modelData === "toggle" ? 2 : 1
                implicitHeight: 34
                radius: 8
                color: modelData === "toggle" ? (tap.containsMouse ? Qt.lighter(Theme.accentBg, 1.1) : Theme.accentBg)
                                              : (tap.containsMouse ? Theme.hover : Theme.track)
                Text {
                    anchors.centerIn: parent
                    text: b.modelData === "toggle" ? (card.player && card.player.isPlaying ? Icons.paused : Icons.playing)
                        : b.modelData === "prev" ? "◀◀" : "▶▶"
                    color: b.modelData === "toggle" ? Theme.accentInk : Theme.fg
                    font { family: Theme.font; pixelSize: b.modelData === "toggle" ? 16 : 10 }
                }
                MouseArea {
                    id: tap
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        const p = card.player
                        if (!p) return
                        if (b.modelData === "prev" && p.canGoPrevious) p.previous()
                        else if (b.modelData === "next" && p.canGoNext) p.next()
                        else if (b.modelData === "toggle" && p.canTogglePlaying) p.togglePlaying()
                    }
                }
            }
        }
    }

    // the player's own volume (not the system's)
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: card.player !== null && card.player.volumeSupported
        RowLayout {
            Layout.fillWidth: true
            Caption { text: card.player ? card.player.identity + " volume" : "" }
            Item { Layout.fillWidth: true }
            Caption { color: Theme.fg; text: card.player ? Math.round(card.player.volume * 100) + "%" : "" }
        }
        Slider {
            Layout.fillWidth: true
            value: card.player ? Math.min(1, card.player.volume) : 0
            onMoved: v => { if (card.player && card.player.canControl) card.player.volume = v }
        }
    }

    // the pill's live bars keep the audio analyser running and the bar redrawing while music plays
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28; radius: 7
        readonly property bool on: WallState.cfg.pillbars
        color: on ? Theme.accentBg : (barsTap.containsMouse ? Theme.hover : Theme.track)
        Text {
            anchors.centerIn: parent
            text: parent.on ? "Live bars in the pill: on" : "Live bars in the pill: off"
            color: parent.on ? Theme.accentInk : Theme.fg
            font { family: Theme.font; pixelSize: 11; bold: parent.on }
        }
        MouseArea { id: barsTap; anchors.fill: parent; hoverEnabled: true; onClicked: WallState.setEffect("pillbars", !WallState.cfg.pillbars) }
    }

    // which player the pill follows
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: Sys.realPlayers.length > 1
        Caption { text: "Follow" }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [""].concat(Sys.realPlayers.map(p => p.identity))
                Rectangle {
                    id: chip
                    required property string modelData
                    readonly property bool on: Sys.playerPin === modelData
                    width: chipText.implicitWidth + 20; height: 26; radius: 7
                    color: on ? Theme.accentBg : (chipTap.containsMouse ? Theme.hover : Theme.track)
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: chip.modelData === "" ? "Automatic" : chip.modelData
                        color: chip.on ? Theme.accentInk : Theme.fg
                        font { family: Theme.font; pixelSize: 11; bold: chip.on }
                    }
                    MouseArea { id: chipTap; anchors.fill: parent; hoverEnabled: true; onClicked: Sys.playerPin = chip.modelData }
                }
            }
        }
    }
}
