// The popup under the health pill: one row per background job. The ones that are failing
// or stale come first, each with why and when it last worked, and buttons: Log (the job's
// log in a terminal), Run now (when the job has a way to run it), Ignore (until it works
// again). Then the ones recovering by themselves (Health.healing), each with what it waits for.
// Jobs that are fine are listed compactly below. Under them "Worth knowing": updates, a
// restart, low disk (Health.notices), each with a button that opens its command in a terminal.
// Data and actions: Health.qml.
import QtQuick
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: list
    signal done()
    spacing: 8

    component Btn: Rectangle {
        id: btn
        property string label: ""
        signal clicked()
        implicitWidth: lbl.implicitWidth + 18
        implicitHeight: 24
        radius: 8
        color: tap.containsMouse ? Theme.hover : Theme.track
        Text {
            id: lbl
            anchors.centerIn: parent
            text: btn.label
            color: tap.containsMouse ? Theme.accent : Theme.fg
            font { family: Theme.font; pixelSize: 11 }
        }
        MouseArea { id: tap; anchors.fill: parent; hoverEnabled: true; onClicked: btn.clicked() }
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: "Background jobs"
            color: Theme.fg
            font { family: Theme.font; pixelSize: 14; bold: true }
        }
        Caption {
            text: Health.busy ? "Checking…" : "Check now"
            color: checkTap.containsMouse ? Theme.accent : Theme.faint
            MouseArea { id: checkTap; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: Health.refresh(true) }
        }
    }

    Caption {
        visible: !Health.loaded
        text: "Checking…"
    }
    Caption {
        visible: Health.loaded && Health.bad.length === 0
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: "Everything is working."
    }

    // what is wrong, worst first
    Repeater {
        model: Health.bad
        Rectangle {
            id: row
            required property var modelData
            readonly property bool failed: modelData.state === "failed"
            Layout.fillWidth: true
            implicitHeight: col.implicitHeight + 16
            radius: 8
            color: Theme.track
            Rectangle {
                width: 3
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                color: row.failed ? Theme.red : Theme.warn
            }
            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 10 }
                spacing: 3
                Text {
                    Layout.fillWidth: true
                    text: row.modelData.name + (row.failed ? " is failing" : " is behind")
                    elide: Text.ElideRight
                    color: row.failed ? Theme.red : Theme.warn
                    font { family: Theme.font; pixelSize: 12; bold: true }
                }
                Text {
                    Layout.fillWidth: true
                    text: row.modelData.why
                    wrapMode: Text.Wrap
                    color: Theme.fg
                    font { family: Theme.font; pixelSize: 11 }
                }
                Caption { text: "Last worked " + Health.ago(row.modelData.since) }
                RowLayout {
                    spacing: 6
                    Btn { label: "Log"; visible: row.modelData.log !== ""; onClicked: { Health.openLog(row.modelData); list.done() } }
                    Btn { label: "Run now"; visible: row.modelData.run !== ""; onClicked: Health.runNow(row.modelData) }
                    Btn { label: "Ignore"; onClicked: Health.ignore(row.modelData.id) }
                }
            }
        }
    }

    // ignored ones, to be watched again
    Repeater {
        model: Health.ignoredBad
        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            Caption { Layout.fillWidth: true; elide: Text.ElideRight; text: "Ignored: " + modelData.name + " (" + modelData.why + ")" }
            Caption {
                text: "Watch"
                color: watchTap.containsMouse ? Theme.accent : Theme.faint
                MouseArea { id: watchTap; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: Health.unignore(modelData.id) }
            }
        }
    }

    // on their way back by themselves: what each waits for, and its log
    Repeater {
        model: Health.healing
        RowLayout {
            id: hrow
            required property var modelData
            Layout.fillWidth: true
            spacing: 6
            Text { text: "↻"; color: Theme.accent; font { family: Theme.font; pixelSize: 12; bold: true } }
            Text {
                Layout.fillWidth: true
                text: "<b>" + hrow.modelData.name + "</b>  " + hrow.modelData.why
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                color: Theme.fg
                font { family: Theme.font; pixelSize: 11 }
            }
            Caption {
                text: "Log"
                visible: hrow.modelData.log !== ""
                color: hlogTap.containsMouse ? Theme.accent : Theme.faint
                MouseArea { id: hlogTap; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: { Health.openLog(hrow.modelData); list.done() } }
            }
        }
    }

    // the healthy ones, one line each
    Repeater {
        model: Health.good
        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 6
            Rectangle { Layout.preferredWidth: 7; Layout.preferredHeight: 7; radius: 4; color: Theme.ok }
            Text {
                Layout.fillWidth: true
                text: modelData.name + "  " + modelData.why
                elide: Text.ElideRight
                color: Theme.faint
                font { family: Theme.font; pixelSize: 11 }
            }
        }
    }

    // informational: never red or amber
    Text {
        visible: Health.notices.length > 0
        Layout.topMargin: 6
        text: "Worth knowing"
        color: Theme.fg
        font { family: Theme.font; pixelSize: 14; bold: true }
    }
    Repeater {
        model: Health.notices
        Rectangle {
            id: nrow
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: ncol.implicitHeight + 16
            radius: 8
            color: Theme.track
            ColumnLayout {
                id: ncol
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 10 }
                spacing: 3
                Text {
                    Layout.fillWidth: true
                    text: nrow.modelData.name
                    elide: Text.ElideRight
                    color: Theme.fg
                    font { family: Theme.font; pixelSize: 12; bold: true }
                }
                Text {
                    Layout.fillWidth: true
                    text: nrow.modelData.why
                    wrapMode: Text.Wrap
                    color: Theme.fg
                    font { family: Theme.font; pixelSize: 11 }
                }
                RowLayout {
                    spacing: 6
                    Btn { label: "Open terminal"; visible: nrow.modelData.cmd !== ""; onClicked: { Health.openTerminal(nrow.modelData); list.done() } }
                }
            }
        }
    }
}
