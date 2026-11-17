// The screensaver's settings in one row, for the wallpaper menu or the control panel:
// on/off, the idle minutes (−/+), and "Try" (the 8 s preview). Self-contained: it reads and
// writes SaverState only, and fills the width it is given (Layout.fillWidth in a ColumnLayout).
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: row
    Layout.fillWidth: true
    spacing: 2
    readonly property bool on: SaverState.cfg.minutes > 0
    property int lastMinutes: 5             // what "on" goes back to

    component Btn: Rectangle {
        id: b
        property string label
        property bool lit: false
        signal clicked()
        Layout.preferredWidth: 38
        implicitHeight: 34
        radius: 8
        color: lit ? Theme.accentBg : (tap.containsMouse ? Theme.hover : Theme.track)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            anchors.centerIn: parent
            text: b.label
            color: b.lit ? Theme.accentInk : Theme.fg
            font { family: Theme.font; pixelSize: 12; bold: b.lit }
        }
        MouseArea { id: tap; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Text {
            Layout.fillWidth: true
            text: "Screensaver"
            color: Theme.fg
            font { family: Theme.font; pixelSize: 12 }
        }
        Btn {
            Layout.preferredWidth: 52
            label: row.on ? "On" : "Off"
            lit: row.on
            onClicked: {
                if (row.on) { row.lastMinutes = SaverState.cfg.minutes; SaverState.setMinutes(0) }
                else SaverState.setMinutes(row.lastMinutes > 0 ? row.lastMinutes : 5)
            }
        }
        Btn {
            label: "−"
            opacity: row.on ? 1 : 0.4
            onClicked: if (row.on) SaverState.setMinutes(Math.max(1, SaverState.cfg.minutes - 1))
        }
        Text {
            Layout.preferredWidth: 30
            horizontalAlignment: Text.AlignHCenter
            text: row.on ? SaverState.cfg.minutes : "–"
            color: Theme.fg
            font { family: Theme.font; pixelSize: 15; bold: true }
        }
        Btn {
            label: "+"
            opacity: row.on ? 1 : 0.4
            onClicked: if (row.on) SaverState.setMinutes(Math.min(14, SaverState.cfg.minutes + 1))
        }
        Btn {
            Layout.preferredWidth: 46
            label: "Try"
            onClicked: SaverState.preview(8000)
        }
    }
    // under the buttons, the whole width: beside them it had 136 px and lost its end (Fit.qml, 2026-11-17)
    Text {
        Layout.fillWidth: true
        elide: Text.ElideRight
        color: Theme.faint
        font { family: Theme.font; pixelSize: 10 }
        text: !row.on ? "off" : SaverState.cfg.minutes * 60 >= SaverState.blankAfter ? "after the screens blank: never shows"
            : "after " + SaverState.cfg.minutes + " min idle" + (SaverState.cfg.battery ? "" : ", on mains")
    }
}
