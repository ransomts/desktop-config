// "Lecture" block for the control panel (Panel.qml): one row of small on/off buttons
// in the look of the panel's shortcuts, lit (accent fill) while a tool is on.
//   LecturePanel { Layout.fillWidth: true; onUsed: panel.visible = false }
// `used` fires after a click that should close the panel (drawing needs the screen).
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: block
    signal used()
    spacing: 6

    component Btn: Rectangle {
        id: b
        property string label
        property string tip
        property bool on: false
        property bool closes: true
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 32
        radius: 8
        color: on ? Theme.accentBg : tap.containsMouse ? Theme.hover : Theme.track
        Text {
            anchors.centerIn: parent
            text: b.label
            color: b.on ? Theme.accentInk : Theme.fg
            font { family: Theme.font; pixelSize: 12; bold: b.on }
        }
        MouseArea {
            id: tap
            anchors.fill: parent
            hoverEnabled: true
            onClicked: { b.clicked(); if (b.closes) block.used() }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Caption { text: "Lecture" }
        Item { Layout.fillWidth: true }
        Caption {
            text: Lecture.timerEnd > 0 ? "timer " + Lecture.timerLabel : Lecture.anyOn ? "Super+Z for more" : "Super+Z menu"
            color: Lecture.timerEnd > 0 ? Theme.accent : Theme.faint
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Btn { label: "Draw"; on: Lecture.drawOn; onClicked: Lecture.toggleDraw() }
        Btn { label: "Spot"; on: Lecture.spotOn; closes: false; onClicked: Lecture.toggleSpot() }
        Btn { label: "Keys"; on: Lecture.keysOn; closes: false; onClicked: Lecture.toggleKeys() }
        Btn { label: "−"; closes: false; on: false; Layout.fillWidth: false; implicitWidth: 30; onClicked: Lecture.zoom(-1) }
        Btn { label: Lecture.zoomFactor + "×"; on: Lecture.zoomIndex > 0; closes: false; onClicked: Lecture.zoomReset() }
        Btn { label: "+"; closes: false; Layout.fillWidth: false; implicitWidth: 30; onClicked: Lecture.zoom(1) }
        Btn { label: Lecture.timerEnd <= 0 ? "10 min" : Lecture.timerPaused ? "Resume" : "Pause"; on: Lecture.timerEnd > 0; closes: false
              onClicked: Lecture.timerEnd > 0 ? Lecture.pauseTimer() : Lecture.startTimer(10, "") }
        Btn { visible: Lecture.timerEnd > 0; label: "Stop"; closes: false; onClicked: Lecture.stopTimer() }
        Btn { label: "Off"; closes: false; onClicked: Lecture.allOff() }
    }
}
