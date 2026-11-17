// What the lecture timer shows (LectureTimer.qml): a large MM:SS countdown with an
// optional label. Warn colour in the last minute; at zero it plays the "complete"
// sound, flashes, and stays 20 s before going away. One timer at 1 Hz, only while a
// countdown or its 20 s afterglow is on.
import QtQuick

Item {
    id: view
    implicitWidth: box.width
    implicitHeight: box.height
    property int tickMs: 1000               // tests make the clock fast
    readonly property int linger: 20000     // ms shown after zero
    property double nowMs: Lecture.now()
    readonly property bool active: Lecture.timerEnd > 0
    readonly property bool paused: Lecture.timerPaused
    readonly property real remain: !active ? 0 : paused ? Lecture.timerPausedLeft / 1000 : Math.max(0, (Lecture.timerEnd - nowMs) / 1000)
    readonly property bool done: active && !paused && Lecture.timerEnd - nowMs <= 0
    readonly property bool lastMinute: active && !done && remain <= 60
    property bool rang: false
    property bool flash: false
    readonly property bool ticking: ticker.running

    function tick() {
        nowMs = Lecture.now()
        if (!active) return
        if (done) {
            if (!rang) { rang = true; Sys.sound("complete") }
            flash = !flash
            if (nowMs - Lecture.timerEnd >= linger) Lecture.stopTimer()
        }
    }
    Connections {
        target: Lecture
        function onTimerEndChanged() { view.rang = false; view.flash = false; view.nowMs = Lecture.now() }
    }
    Timer {
        id: ticker
        interval: view.tickMs; repeat: true
        running: view.active && !view.paused
        onTriggered: view.tick()
    }

    Rectangle {
        id: box
        width: Math.max(col.implicitWidth + 40, 200)
        height: col.implicitHeight + 24
        radius: 18
        color: view.done && view.flash ? Theme.accentBg : Theme.panelBg
        border.width: 2
        border.color: view.done ? Theme.accentBg : view.paused ? Theme.alt : view.lastMinute ? Theme.warn : Theme.line
        HoverHandler { id: hover }
        TapHandler { onTapped: Lecture.pauseTimer() }
        Column {
            id: col
            anchors.centerIn: parent
            spacing: 0
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Lecture.timerLabel !== ""
                text: Lecture.timerLabel
                color: view.done && view.flash ? Theme.accentInk : Theme.faint
                font { family: Theme.font; pixelSize: 20 }
            }
            Text {
                objectName: "clock"
                anchors.horizontalCenter: parent.horizontalCenter
                text: view.done ? "00:00" : Lecture.clock(view.remain)
                color: view.done && view.flash ? Theme.accentInk : view.done ? Theme.accent : view.paused ? Theme.dim : view.lastMinute ? Theme.warn : Theme.fg
                font { family: Theme.font; pixelSize: 72; bold: true }
            }
            // Pause, reset, stop: shown while the pointer is on the timer (and always while paused).
            // A click on the time itself also pauses and carries on.
            Row {
                id: controls
                objectName: "controls"
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                visible: view.active && (hover.hovered || view.paused)
                bottomPadding: 6
                Repeater {
                    model: [{ act: "pause", label: view.paused ? "Resume" : view.done ? "" : "Pause" }, { act: "reset", label: "Reset" }, { act: "stop", label: "Stop" }]
                    Rectangle {
                        id: btn
                        required property var modelData
                        objectName: "timer-" + modelData.act
                        visible: modelData.label !== ""
                        width: btnText.implicitWidth + 22; height: 26; radius: 8
                        color: btnTap.containsMouse ? Theme.hover : Theme.track
                        Text { id: btnText; anchors.centerIn: parent; text: btn.modelData.label; color: Theme.fg; font { family: Theme.font; pixelSize: 12 } }
                        MouseArea {
                            id: btnTap
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: btn.modelData.act === "pause" ? Lecture.pauseTimer() : btn.modelData.act === "reset" ? Lecture.resetTimer() : Lecture.stopTimer()
                        }
                    }
                }
            }
        }
    }
}
