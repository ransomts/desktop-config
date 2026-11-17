// A square glyph button for the screenshot editor's toolbar and the share picker.
// Its tip is shown by the host (host.tipNow) while the pointer is on it.
import QtQuick

Rectangle {
    id: b
    property string glyph: ""
    property string tip: ""
    property bool on: false
    property bool dim: false
    property var host: null
    signal clicked()
    implicitWidth: 30; implicitHeight: 30
    width: implicitWidth; height: implicitHeight
    radius: 8
    color: on ? Theme.accentBg : tap.containsMouse ? Theme.hover : "transparent"
    Text {
        anchors.centerIn: parent
        text: b.glyph
        color: b.on ? Theme.accentInk : b.dim ? Theme.dim : Theme.fg
        font { family: Theme.font; pixelSize: 18 }
    }
    MouseArea {
        id: tap
        anchors.fill: parent
        hoverEnabled: true
        onClicked: b.clicked()
        onContainsMouseChanged: if (b.host) b.host.tipNow = containsMouse ? b.tip : (b.host.tipNow === b.tip ? "" : b.host.tipNow)
    }
}
