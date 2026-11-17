// Recent notifications grouped by app (Notif.groups), newest group first: used by the
// list under the bell pill (NotifList.qml) and the control panel. An app header shows
// the count; click it to see them all (collapsed, only the newest shows). On a header:
// ⋯ sets the app's rule (normal / list only / mute), x forgets the whole group. On an
// entry: click copies its text, the clock snoozes it (15 min / 1 h / tomorrow 08:00),
// x forgets it; its buttons show only while the notification itself is still open.
import QtQuick
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: groupsView
    property int limit: 8                   // groups shown
    property int fresh: 0                   // how many at the top of the history count as new (orange edge)
    signal removing(var indices)            // history indices about to go (forget, forget group, snooze)
    property var open: ({})                 // app -> expanded
    property string menuApp: ""             // the app whose rule menu is open
    property string snoozeFor: ""           // the entry whose snooze choices are open
    function toggle(app) { const o = Object.assign({}, open); if (o[app]) delete o[app]; else o[app] = true; open = o }
    spacing: 6

    Repeater {
        model: Notif.groups.slice(0, groupsView.limit)
        ColumnLayout {
            id: grp
            required property var modelData
            readonly property bool isOpen: !!groupsView.open[modelData.app] && modelData.count > 1
            readonly property bool hasFresh: modelData.entries.some(e => e.index < groupsView.fresh)
            Layout.fillWidth: true
            spacing: 3

            RowLayout {             // the app header
                Layout.fillWidth: true
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    text: (grp.modelData.count > 1 ? (grp.isOpen ? "▾ " : "▸ ") : "") + (grp.modelData.app || "(no name)")
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    color: headTap.containsMouse && grp.modelData.count > 1 ? Theme.accent : Theme.fg
                    font { family: Theme.font; pixelSize: 11; bold: true }
                    MouseArea { id: headTap; anchors.fill: parent; hoverEnabled: true; onClicked: if (grp.modelData.count > 1) groupsView.toggle(grp.modelData.app) }
                }
                Rectangle {
                    objectName: "count"
                    visible: grp.modelData.count > 1
                    implicitWidth: countText.implicitWidth + 10
                    implicitHeight: 16
                    radius: 8
                    color: grp.hasFresh ? Theme.accentBg : Theme.track
                    Text {
                        id: countText
                        anchors.centerIn: parent
                        text: grp.modelData.count
                        color: grp.hasFresh ? Theme.accentInk : Theme.fg
                        font { family: Theme.font; pixelSize: 10; bold: true }
                    }
                    MouseArea { anchors.fill: parent; onClicked: groupsView.toggle(grp.modelData.app) }
                }
                Caption {
                    visible: grp.modelData.rule !== "normal"
                    text: grp.modelData.rule === "mute" ? "muted" : "list only"
                    font.pixelSize: 10
                }
                Text {
                    text: "⋯"
                    color: dotsTap.containsMouse || groupsView.menuApp === grp.modelData.app ? Theme.accent : Theme.faint
                    font { family: Theme.font; pixelSize: 14; bold: true }
                    MouseArea { id: dotsTap; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true
                                onClicked: groupsView.menuApp = groupsView.menuApp === grp.modelData.app ? "" : grp.modelData.app }
                }
                Text {
                    text: "×"
                    color: forgetAllTap.containsMouse ? Theme.accent : Theme.faint
                    font { family: Theme.font; pixelSize: 16 }
                    Layout.rightMargin: 4
                    MouseArea {
                        id: forgetAllTap
                        anchors.fill: parent; anchors.margins: -6; hoverEnabled: true
                        onClicked: { groupsView.removing(grp.modelData.entries.map(e => e.index)); Notif.forgetGroup(grp.modelData.app) }
                    }
                }
            }
            Flow {                  // the app's rule
                visible: groupsView.menuApp === grp.modelData.app
                Layout.fillWidth: true
                spacing: 5
                Repeater {
                    model: groupsView.menuApp === grp.modelData.app ? [
                        { label: "Normal", rule: "normal" },
                        { label: "List only", rule: "list" },
                        { label: "Mute", rule: "mute" }] : []
                    Rectangle {
                        id: ruleChip
                        required property var modelData
                        readonly property bool on: grp.modelData.rule === modelData.rule
                        width: ruleText.implicitWidth + 14; height: 22; radius: 7
                        color: on ? Theme.accentBg : ruleTap.containsMouse ? Theme.hover : Theme.track
                        Text { id: ruleText; anchors.centerIn: parent; text: ruleChip.modelData.label; color: ruleChip.on ? Theme.accentInk : Theme.fg; font { family: Theme.font; pixelSize: 11 } }
                        MouseArea { id: ruleTap; anchors.fill: parent; hoverEnabled: true
                                    onClicked: { Notif.setRule(grp.modelData.app, ruleChip.modelData.rule); groupsView.menuApp = "" } }
                    }
                }
            }

            Repeater {
                model: grp.isOpen ? grp.modelData.entries : grp.modelData.entries.slice(0, 1)
                Rectangle {
                    id: old
                    required property var modelData
                    readonly property string plain: ((modelData.summary || "") + ((modelData.body || "") !== "" ? "\n" + modelData.body.replace(/<[^>]*>/g, "") : "")).trim()
                    readonly property bool isFresh: modelData.index < groupsView.fresh
                    readonly property bool snoozing: groupsView.snoozeFor === modelData.id
                    readonly property var buttons: Notif.isLive(modelData.id) ? (modelData.actions || []).filter(a => a.id !== "default" && a.text !== "") : []
                    property bool copied: false
                    Layout.fillWidth: true
                    implicitHeight: col.implicitHeight + 12
                    radius: 8
                    color: oldTap.containsMouse ? Theme.hover : Theme.track
                    clip: true
                    MouseArea {
                        id: oldTap
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { Quickshell.clipboardText = old.plain; old.copied = true; copiedReset.restart() }
                    }
                    Timer { id: copiedReset; interval: 1200; onTriggered: old.copied = false }
                    Rectangle {     // arrived since the last look
                        visible: old.isFresh
                        width: 3
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        color: Theme.accentBg
                    }
                    ColumnLayout {
                        id: col
                        anchors { left: parent.left; right: snoozeBtn.left; top: parent.top; topMargin: 6; leftMargin: 12; rightMargin: 6 }
                        spacing: 4
                        Text {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: old.copied ? "Copied" : (old.modelData.time || "") + (old.modelData.repeat > 1 ? "  ×" + old.modelData.repeat : "") + (old.modelData.snoozed ? "  (snoozed)" : "") + "\n" + old.plain.replace(/\s+/g, " ")
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            color: old.modelData.critical ? Theme.accent : Theme.fg
                            font { family: Theme.font; pixelSize: 11 }
                        }
                        Flow {
                            visible: old.buttons.length > 0
                            Layout.fillWidth: true
                            spacing: 5
                            Repeater {
                                model: old.buttons
                                Rectangle {
                                    id: act
                                    required property var modelData
                                    width: actText.implicitWidth + 14; height: 22; radius: 7
                                    color: actTap.containsMouse ? Theme.hover : Theme.track
                                    border.width: 1; border.color: Theme.line
                                    Text { id: actText; anchors.centerIn: parent; text: act.modelData.text; color: Theme.fg; font { family: Theme.font; pixelSize: 11 } }
                                    MouseArea { id: actTap; anchors.fill: parent; hoverEnabled: true; onClicked: Notif.invokeAction(old.modelData.id, act.modelData.id) }
                                }
                            }
                        }
                        Flow {
                            visible: old.snoozing
                            Layout.fillWidth: true
                            Layout.bottomMargin: 2
                            spacing: 5
                            Repeater {
                                model: old.snoozing ? [{ label: "15 min", when: "15m" }, { label: "1 h", when: "1h" }, { label: "Tomorrow 8:00", when: "tomorrow" }] : []
                                Rectangle {
                                    id: snz
                                    required property var modelData
                                    width: snzText.implicitWidth + 14; height: 22; radius: 7
                                    color: snzTap.containsMouse ? Theme.accentBg : Theme.panelBg
                                    Text { id: snzText; anchors.centerIn: parent; text: snz.modelData.label; color: snzTap.containsMouse ? Theme.accentInk : Theme.fg; font { family: Theme.font; pixelSize: 11 } }
                                    MouseArea {
                                        id: snzTap; anchors.fill: parent; hoverEnabled: true
                                        onClicked: { groupsView.snoozeFor = ""; groupsView.removing([old.modelData.index]); Notif.snooze(old.modelData.id, snz.modelData.when) }
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        id: snoozeBtn
                        anchors { right: forgetBtn.left; rightMargin: 10; top: parent.top; topMargin: 8 }
                        text: Icons.clock
                        opacity: oldTap.containsMouse || snzOpenTap.containsMouse || old.snoozing ? 1 : 0
                        color: snzOpenTap.containsMouse || old.snoozing ? Theme.accent : Theme.faint
                        font { family: Theme.font; pixelSize: 12 }
                        MouseArea { id: snzOpenTap; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true
                                    onClicked: groupsView.snoozeFor = old.snoozing ? "" : old.modelData.id }
                    }
                    Text {
                        id: forgetBtn
                        anchors { right: parent.right; rightMargin: 10; top: parent.top; topMargin: 5 }
                        text: "×"
                        color: forgetTap.containsMouse ? Theme.accent : Theme.faint
                        font { family: Theme.font; pixelSize: 16 }
                        MouseArea {
                            id: forgetTap
                            anchors.fill: parent; anchors.margins: -6; hoverEnabled: true
                            onClicked: { groupsView.removing([old.modelData.index]); Notif.forget(old.modelData.index) }
                        }
                    }
                }
            }
        }
    }
}
