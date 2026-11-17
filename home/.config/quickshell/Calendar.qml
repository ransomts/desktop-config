// Month calendar, Monday first; today filled in orange. ‹ › change month,
// clicking the month name comes back to today. Click a day to list its events
// (from the Org calendars, via ~/.local/bin/agenda-day) underneath.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: cal
    property date today: new Date()
    property int offset: 0                                   // months from the current one
    property date picked: today                              // the day whose events are listed
    readonly property bool pickedIsToday: picked.toDateString() === today.toDateString()
    property var events: []
    function iso(d) { return Qt.formatDate(d, "yyyy-MM-dd") }
    onPickedChanged: load()
    Component.onCompleted: load()
    function load() {
        // compared here, not via pickedIsToday: inside onPickedChanged that binding
        // can still hold its old value, and the first pick would show today's list
        if (picked.toDateString() === today.toDateString()) { events = Sys.today; return }
        dayProc.command = Sys.clean.concat([Sys.bin + "agenda-day", iso(picked)])
        dayProc.running = true
    }
    Connections { target: Sys; function onTodayChanged() { if (cal.pickedIsToday) cal.events = Sys.today } }
    Process {
        id: dayProc
        stdout: StdioCollector { onStreamFinished: { try { cal.events = JSON.parse(text) } catch (e) { cal.events = [] } } }
    }
    readonly property date first: new Date(today.getFullYear(), today.getMonth() + offset, 1)
    readonly property int lead: (first.getDay() + 6) % 7
    readonly property int days: new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate()
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: Qt.formatDate(cal.first, "MMMM yyyy")
            color: cal.offset === 0 ? Theme.accent : Theme.fg
            font { family: Theme.font; pixelSize: 14; bold: true }
            MouseArea { anchors.fill: parent; onClicked: { cal.offset = 0; cal.picked = cal.today } }
        }
        Repeater {
            model: [{ label: "‹", step: -1 }, { label: "›", step: 1 }]
            Rectangle {
                id: nav
                required property var modelData
                width: 26; height: 24; radius: 7
                color: navTap.containsMouse ? Theme.hover : Theme.track
                Text { anchors.centerIn: parent; text: nav.modelData.label; color: Theme.fg; font { family: Theme.font; pixelSize: 15 } }
                MouseArea { id: navTap; anchors.fill: parent; hoverEnabled: true; onClicked: cal.offset += nav.modelData.step }
            }
        }
    }
    Grid {
        columns: 7
        spacing: 2
        Repeater {
            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
            Text {
                required property string modelData
                width: 36; height: 22
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: modelData
                color: Theme.faint
                font { family: Theme.font; pixelSize: 11 }
            }
        }
        Repeater {
            model: cal.lead + cal.days
            Rectangle {
                id: cell
                required property int index
                readonly property int day: index - cal.lead + 1
                readonly property bool isToday: cal.offset === 0 && day === cal.today.getDate()
                readonly property bool isPicked: day >= 1 && !isToday && cal.picked.getFullYear() === cal.first.getFullYear()
                                                 && cal.picked.getMonth() === cal.first.getMonth() && cal.picked.getDate() === day
                width: 36; height: 28; radius: 7
                color: isToday ? Theme.accentBg : isPicked ? Theme.hover : dayTap.containsMouse && day >= 1 ? Theme.track : "transparent"
                border.width: isPicked ? 1 : 0
                border.color: Theme.accentBg
                MouseArea {
                    id: dayTap
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: if (cell.day >= 1) cal.picked = new Date(cal.first.getFullYear(), cal.first.getMonth(), cell.day)
                }
                Text {
                    anchors.centerIn: parent
                    visible: cell.day >= 1
                    text: cell.day
                    color: cell.isToday ? Theme.accentInk : (cell.index % 7 >= 5 ? Theme.faint : Theme.fg)
                    font { family: Theme.font; pixelSize: 13; bold: cell.isToday }
                }
            }
        }
    }

    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }
    Caption { text: cal.pickedIsToday ? "Today" : Qt.formatDate(cal.picked, "dddd, MMMM d") }
    Caption { visible: cal.events.length === 0; text: "Nothing scheduled"; color: Theme.fg }
    Repeater {
        model: cal.events
        RowLayout {
            id: ev
            required property var modelData
            readonly property bool past: cal.pickedIsToday && !modelData.allday && modelData.end !== "" && modelData.end <= Sys.nowHM
            readonly property bool now: cal.pickedIsToday && !modelData.allday && modelData.start <= Sys.nowHM && modelData.end > Sys.nowHM
            Layout.fillWidth: true
            spacing: 10
            Text {
                Layout.preferredWidth: 84
                Layout.alignment: Qt.AlignTop
                text: ev.modelData.allday ? "all day" : ev.modelData.start + (ev.modelData.end !== "" ? "\u2013" + ev.modelData.end : "")
                color: ev.now ? Theme.accent : ev.past ? Theme.dim : Theme.faint
                font { family: Theme.font; pixelSize: 11; bold: ev.now }
            }
            Text {
                Layout.fillWidth: true
                text: ev.modelData.title
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: ev.past ? Theme.dim : Theme.fg
                font { family: Theme.font; pixelSize: 12; bold: ev.now }
            }
        }
    }
    // "+ Add event": the launcher opens with "event YYYY-MM-DD " typed (see EventQuick.qml)
    function shq(t) { return "'" + String(t).replace(/'/g, "'\\''") + "'" }
    function addEventCommand() { return "qs ipc call launcher openWith " + shq("event " + iso(picked) + " ") }
    Rectangle {
        id: addRow
        objectName: "addEvent"
        Layout.fillWidth: true
        implicitHeight: 26; radius: 7
        color: addTap.containsMouse ? Theme.track : "transparent"
        Text {
            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
            text: "+ Add event"
            color: Theme.accent
            font { family: Theme.font; pixelSize: 12 }
        }
        MouseArea { id: addTap; anchors.fill: parent; hoverEnabled: true; onClicked: Sys.run(cal.addEventCommand()) }
    }
    ClockPanel { Layout.fillWidth: true }                    // timers, alarms, stopwatch, world clock: one line until clicked
}
