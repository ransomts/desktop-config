// Timers, alarms, stopwatch and world clock for the calendar popup (Calendar.qml puts it under the
// agenda). Collapsed it is one line ("2 timers · next alarm 07:30") until clicked. All state is in
// Clocks (ClocksCore.qml); this only shows it and calls its functions. A 1 Hz ticker runs only while
// it is open with something counting; the world clock asks bin/tz-now once when it opens.
import QtQuick
import QtQuick.Layouts
import "clocks.js" as C

ColumnLayout {
    id: panel
    objectName: "clockPanel"
    property bool open: false
    readonly property bool counting: open && (Clocks.runningCount > 0 || Clocks.stopwatch.running)
    readonly property var core: Clocks.core
    property string timerError: ""
    property string alarmError: ""
    spacing: 8
    onCountingChanged: Clocks.watch("panel", counting)
    onOpenChanged: Clocks.worldWatch("panel", open)
    Component.onDestruction: { Clocks.watch("panel", false); Clocks.worldWatch("panel", false) }

    component Btn: Rectangle {
        id: b
        property string label: ""
        property bool on: false
        property bool warn: false
        signal clicked()
        implicitWidth: Math.max(26, t.implicitWidth + 14)
        implicitHeight: 24
        radius: 7
        color: on ? Theme.accentBg : tap.containsMouse ? Theme.hover : Theme.track
        Text { id: t; anchors.centerIn: parent; text: b.label; color: b.on ? Theme.accentInk : b.warn ? Theme.red : Theme.fg; font { family: Theme.font; pixelSize: 11 } }
        MouseArea { id: tap; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
    }
    component Field: Rectangle {
        id: f
        property alias text: input.text
        property string placeholder: ""
        readonly property alias input: input
        signal accepted()
        implicitHeight: 26
        radius: 7
        color: Theme.track
        border.width: input.activeFocus ? 2 : 1
        border.color: input.activeFocus ? Theme.accentBg : Theme.line
        TextInput {
            id: input
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: Theme.fg
            selectionColor: Theme.hover
            font { family: Theme.font; pixelSize: 12 }
            onAccepted: f.accepted()
            Keys.onEscapePressed: event => { text = ""; event.accepted = true }
        }
        Text {
            anchors { fill: parent; leftMargin: 8 }
            verticalAlignment: Text.AlignVCenter
            visible: input.text === "" && !input.activeFocus
            text: f.placeholder
            color: Theme.faint
            font { family: Theme.font; pixelSize: 11; italic: true }
        }
    }
    component Head: Text { Layout.topMargin: 4; color: Theme.faint; font { family: Theme.font; pixelSize: 11; bold: true; letterSpacing: 1 } }

    // ---- the one collapsed line ----
    Rectangle {
        id: header
        objectName: "clockHeader"
        Layout.fillWidth: true
        implicitHeight: 30
        radius: 8
        color: headTap.containsMouse ? Theme.hover : Theme.track
        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            Text {
                objectName: "clockSummary"
                Layout.fillWidth: true
                text: Clocks.summary
                elide: Text.ElideRight
                color: Clocks.ringing.length > 0 ? Theme.accent : Theme.fg
                font { family: Theme.font; pixelSize: 12; bold: Clocks.ringing.length > 0 }
            }
            Text { text: panel.open ? "▾" : "▸"; color: Theme.faint; font { family: Theme.font; pixelSize: 12 } }
        }
        MouseArea { id: headTap; anchors.fill: parent; hoverEnabled: true; onClicked: panel.open = !panel.open }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: panel.open
        spacing: 6

        // ---- going off now ----
        Repeater {
            model: Clocks.ringing
            RowLayout {
                id: ringRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 6
                Text { Layout.fillWidth: true; text: ringRow.modelData.title; elide: Text.ElideRight; color: Theme.accent; font { family: Theme.font; pixelSize: 12; bold: true } }
                Btn { visible: ringRow.modelData.alarm; label: "Snooze " + panel.core.snoozeMinutes; onClicked: panel.core.snoozeRing(ringRow.modelData.rid) }
                Btn { label: "Dismiss"; onClicked: panel.core.dismissRing(ringRow.modelData.rid) }
            }
        }

        // ---- timers ----
        Head { text: "TIMERS" }
        Text { visible: Clocks.timers.length === 0; text: "None running"; color: Theme.faint; font { family: Theme.font; pixelSize: 11 } }
        Repeater {
            model: Clocks.timers
            ColumnLayout {
                id: tm
                required property var modelData
                readonly property bool paused: modelData.pausedLeft > 0
                readonly property double leftMs: C.timerLeftMs(modelData, Clocks.nowMs)
                Layout.fillWidth: true
                spacing: 3
                RowLayout {
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; text: tm.modelData.label || C.fmtDuration(tm.modelData.total / 1000); elide: Text.ElideRight; color: tm.modelData.done ? Theme.accent : Theme.fg; font { family: Theme.font; pixelSize: 12 } }
                    Text {
                        objectName: "timerLeft"
                        text: tm.modelData.done ? "done" : C.fmtLeft(tm.leftMs / 1000) + (tm.paused ? " ‖" : "")
                        color: tm.modelData.done ? Theme.accent : tm.paused ? Theme.faint : Theme.fg
                        font { family: Theme.font; pixelSize: 13; bold: true }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 6; radius: 3; color: Theme.track
                        Rectangle { width: parent.width * (tm.modelData.done ? 1 : Math.max(0, Math.min(1, 1 - tm.leftMs / tm.modelData.total))); height: parent.height; radius: 3; color: tm.paused ? Theme.faint : Theme.accentBg }
                    }
                    Btn { visible: !tm.modelData.done; objectName: "pauseBtn"; label: tm.paused ? "Resume" : "Pause"; onClicked: panel.core.togglePause(tm.modelData.id) }
                    Btn { objectName: "resetBtn"; label: "Reset"; onClicked: panel.core.resetTimer(tm.modelData.id) }
                    Btn { objectName: "cancelBtn"; label: "×"; warn: true; onClicked: panel.core.removeTimer(tm.modelData.id) }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Field { id: timerIn; objectName: "timerInput"; Layout.fillWidth: true; placeholder: "10m tea, 1h30, 25"; onAccepted: addTimer.clicked() }
            Btn { id: addTimer; objectName: "timerAdd"; label: "Start"; onClicked: { const r = panel.core.timerSpec(timerIn.text); panel.timerError = r.startsWith("error: ") ? r.slice(7) : ""; if (panel.timerError === "") timerIn.text = "" } }
        }
        Text { visible: panel.timerError !== ""; Layout.fillWidth: true; text: panel.timerError; wrapMode: Text.Wrap; color: Theme.red; font { family: Theme.font; pixelSize: 11 } }

        // ---- alarms ----
        Head { text: "ALARMS" }
        Text { visible: Clocks.alarms.length === 0; text: "None set"; color: Theme.faint; font { family: Theme.font; pixelSize: 11 } }
        Repeater {
            model: Clocks.alarms
            RowLayout {
                id: al
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                Text { text: al.modelData.time; color: al.modelData.enabled ? Theme.fg : Theme.dim; font { family: Theme.font; pixelSize: 15; bold: true } }
                Text {
                    Layout.fillWidth: true
                    text: [al.modelData.label, C.whenText(al.modelData, Clocks.nowMs)].filter(s => s !== "").join("  ·  ")
                    elide: Text.ElideRight
                    color: al.modelData.enabled ? Theme.faint : Theme.dim
                    font { family: Theme.font; pixelSize: 11 }
                }
                Rectangle {
                    id: sw
                    objectName: "alarmSwitch"
                    width: 34; height: 18; radius: 9
                    color: al.modelData.enabled ? Theme.accentBg : Theme.track
                    border.width: 1; border.color: al.modelData.enabled ? Theme.accentBg : Theme.line
                    Rectangle { width: 12; height: 12; radius: 6; y: 3; x: al.modelData.enabled ? parent.width - width - 3 : 3; color: al.modelData.enabled ? Theme.accentInk : Theme.fg }
                    MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: panel.core.setAlarmEnabled(al.modelData.id, !al.modelData.enabled) }
                }
                Btn { objectName: "alarmDelete"; label: "×"; warn: true; onClicked: panel.core.removeAlarm(al.modelData.id) }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Field { id: alarmIn; objectName: "alarmInput"; Layout.fillWidth: true; placeholder: "7:30 weekdays stand-up"; onAccepted: addAlarm.clicked() }
            Btn { id: addAlarm; objectName: "alarmAdd"; label: "Add"; onClicked: { const r = panel.core.alarmSpec(alarmIn.text); panel.alarmError = r.startsWith("error: ") ? r.slice(7) : ""; if (panel.alarmError === "") alarmIn.text = "" } }
        }
        Text { visible: panel.alarmError !== ""; Layout.fillWidth: true; text: panel.alarmError; wrapMode: Text.Wrap; color: Theme.red; font { family: Theme.font; pixelSize: 11 } }

        // ---- stopwatch ----
        Head { text: "STOPWATCH" }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text { objectName: "swElapsed"; Layout.fillWidth: true; text: C.fmtElapsed(Clocks.stopwatch.elapsed); color: Clocks.stopwatch.running ? Theme.fg : Theme.faint; font { family: Theme.font; pixelSize: 20; bold: true } }
            Btn { objectName: "swToggle"; label: Clocks.stopwatch.running ? "Stop" : (Clocks.stopwatch.elapsed > 0 ? "Resume" : "Start"); on: !Clocks.stopwatch.running && Clocks.stopwatch.elapsed === 0; onClicked: panel.core.stopwatchAction("toggle") }
            Btn { objectName: "swLap"; visible: Clocks.stopwatch.running; label: "Lap"; onClicked: panel.core.stopwatchAction("lap") }
            Btn { objectName: "swReset"; visible: Clocks.stopwatch.elapsed > 0; label: "Reset"; onClicked: panel.core.stopwatchAction("reset") }
        }
        Repeater {
            model: Clocks.stopwatch.laps.slice(-3).reverse()
            Text {
                required property var modelData
                required property int index
                readonly property int n: Clocks.stopwatch.laps.length - index
                readonly property double before: n >= 2 ? Clocks.stopwatch.laps[n - 2] : 0
                text: "Lap " + n + "   " + C.fmtElapsed(modelData) + "   (+" + C.fmtElapsed(modelData - before) + ")"
                color: Theme.faint
                font { family: Theme.font; pixelSize: 11 }
            }
        }

        // ---- world clock ----
        Head { visible: Clocks.worldLines.length > 0; text: "WORLD CLOCK" }
        Repeater {
            model: Clocks.worldLines
            RowLayout {
                id: wl
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                Text { Layout.fillWidth: true; text: wl.modelData.name; elide: Text.ElideRight; color: Theme.fg; font { family: Theme.font; pixelSize: 12 } }
                Text { text: wl.modelData.ok ? [wl.modelData.note, wl.modelData.diff].filter(s => s !== "").join("  ·  ") : wl.modelData.note; color: Theme.faint; font { family: Theme.font; pixelSize: 11 } }
                Text { Layout.minimumWidth: 44; horizontalAlignment: Text.AlignRight; text: wl.modelData.time; color: Theme.fg; font { family: Theme.font; pixelSize: 13; bold: true } }
            }
        }
    }
}
