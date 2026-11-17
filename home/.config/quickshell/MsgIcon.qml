// The icon tile shared by the island (Island.qml) and the notification cards (NotifStack.qml):
// a rounded square that holds a picture (fills it: album art, an avatar), an app icon (drawn
// inside it), or a glyph. Hidden when there is nothing to show.
import QtQuick
import Quickshell.Widgets

Rectangle {
    id: tile
    property string image: ""
    property string icon: ""
    property string glyph: ""
    property color glyphColor: Theme.accent
    // a bare /path would resolve against Quickshell's qs:@/ URL and fail: make it a file URL
    function url(s) { return s.startsWith("/") ? "file://" + s : s }
    // shown once something in it has loaded (a missing icon file leaves no empty tile behind)
    // (from load status, not the children's visible: a hidden parent makes those read false)
    readonly property bool hasArt: image !== "" && art.status === Image.Ready
    readonly property bool hasIcon: !hasArt && icon !== "" && appIcon.status === Image.Ready
    visible: hasArt || hasIcon || glyph !== ""
    implicitWidth: Theme.msgIcon
    implicitHeight: Theme.msgIcon
    width: implicitWidth
    height: implicitHeight
    radius: 8
    color: Theme.track
    clip: true
    Image {
        id: art
        anchors.fill: parent
        source: tile.url(tile.image)
        sourceSize: Qt.size(Theme.msgIcon * 2, Theme.msgIcon * 2)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: tile.hasArt
    }
    IconImage {                                 // synchronous: the image://icon provider fails when asked asynchronously
        id: appIcon
        anchors.centerIn: parent
        implicitSize: 24
        source: tile.hasArt ? "" : tile.url(tile.icon)       // a path, a URL, or Quickshell.iconPath()'s image://icon/...
        visible: tile.hasIcon
    }
    Text {
        anchors.centerIn: parent
        visible: !tile.hasArt && !tile.hasIcon
        text: tile.glyph
        color: tile.glyphColor
        font { family: Theme.font; pixelSize: 17 }
    }
}
