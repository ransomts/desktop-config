// The popup cards (inside NotifPopups.qml's window): newest on top, at most five cards.
// Several from one app that come close together share a card: the newest one is shown
// with a count badge; click the badge to see them all. The same message repeated is one
// entry marked ×N (Notif.qml merges repeats). Click a card to open it (its
// default action) or just dismiss it; hovering holds it on screen; critical ones stay
// until dismissed. Right-click (or the ⋯ on hover) for a small menu: snooze 15 min /
// 1 h / tomorrow 08:00, the app's rule (normal / list only / mute), dismiss.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

ColumnLayout {
    id: stack
    spacing: 8
    readonly property int maxCards: 5
    readonly property var groups: Notif.popupGroups.slice(0, maxCards)
    property var expanded: ({})             // group key -> true while its badge is open
    property string menuFor: ""             // the group key whose menu is open
    function toggle(key) { const e = Object.assign({}, expanded); if (e[key]) delete e[key]; else e[key] = true; expanded = e }

    Repeater {
        // keys only, so a card keeps its state (timer, expanded) while others come and go
        model: ScriptModel { values: stack.groups.map(g => g.key) }
        Rectangle {
            id: card
            required property string modelData
            readonly property var g: stack.groups.find(x => x.key === modelData) || null
            readonly property var items: g ? g.items : []
            readonly property int count: items.length
            readonly property var newest: count > 0 ? items[count - 1] : null
            readonly property var n: newest ? newest.n : null
            readonly property bool critical: !!newest && newest.critical
            readonly property bool low: !!newest && newest.low
            readonly property bool open: !!stack.expanded[modelData] && count > 1
            readonly property bool menu: stack.menuFor === modelData
            readonly property string level: critical ? "critical" : low ? "low" : "normal"
            readonly property color ink: Theme.msgInk(level)
            readonly property color faintInk: Theme.msgFaint(level)
            readonly property string summary: n ? n.summary : newest ? newest.summary : ""
            readonly property string bodyText: n ? n.body : newest ? newest.body : ""
            readonly property string app: newest ? newest.app : ""
            readonly property string picture: n ? n.image : newest ? (newest.image || "") : ""
            readonly property string appIcon: {
                const ico = n ? n.appIcon : newest ? (newest.appIcon || "") : ""
                if (ico === "") return ""
                if (ico.startsWith("/") || ico.indexOf("://") !== -1) return ico
                return Quickshell.iconPath(ico, true)
            }
            Layout.fillWidth: true
            implicitHeight: body.implicitHeight + 24
            radius: 10
            color: Theme.msgFill(level, Theme.panelBg)
            border.width: Theme.msgBorder
            border.color: Theme.msgEdge(level)

            Timer {
                id: life
                // expireTimeout arrives in milliseconds; -1 or 0 means "your choice": 6 s, or never for critical
                interval: card.n && card.n.expireTimeout > 0 ? card.n.expireTimeout : 6000
                running: card.count > 0 && !hov.hovered && !card.menu && !card.open
                         && ((card.n && card.n.expireTimeout > 0) || !card.critical)
                onTriggered: Notif.expireGroup(card.modelData)
            }
            onCountChanged: if (life.running) life.restart()          // one more from the app: full time again
            onNewestChanged: if (life.running) life.restart()         // the same one repeated: full time again

            HoverHandler { id: hov }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) { stack.menuFor = card.menu ? "" : card.modelData; return }
                    if (card.n) {
                        const def = (card.n.actions || []).find(a => a.identifier === "default")
                        if (def) { def.invoke(); return }
                    }
                    Notif.dismissGroup(card.modelData)
                }
            }

            RowLayout {
                id: body
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 12

                MsgIcon {
                    image: card.picture
                    icon: card.appIcon
                    Layout.alignment: Qt.AlignTop
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            text: card.summary
                            elide: Text.ElideRight
                            color: card.ink
                            font { family: Theme.font; pixelSize: Theme.msgTitle; bold: true }
                        }
                        Text {              // the same message, this many times
                            objectName: "repeat"
                            visible: !!card.newest && card.newest.repeat > 1
                            text: "×" + (card.newest ? card.newest.repeat : 1)
                            color: card.ink
                            font { family: Theme.font; pixelSize: Theme.msgMeta; bold: true }
                        }
                        Rectangle {         // count badge: click to see them all
                            objectName: "badge"
                            visible: card.count > 1
                            implicitWidth: badgeText.implicitWidth + 12
                            implicitHeight: 18
                            radius: 9
                            color: card.open || badgeTap.containsMouse ? Theme.accentBg : Theme.track
                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: card.count + (card.open ? " ▴" : " ▾")
                                color: card.open || badgeTap.containsMouse ? Theme.accentInk : card.ink
                                font { family: Theme.font; pixelSize: 11; bold: true }
                            }
                            MouseArea { id: badgeTap; anchors.fill: parent; anchors.margins: -3; hoverEnabled: true; onClicked: stack.toggle(card.modelData) }
                        }
                        Text {
                            text: card.app
                            color: card.faintInk
                            font { family: Theme.font; pixelSize: Theme.msgMeta }
                        }
                        Text {              // the menu, on hover
                            text: "⋯"
                            opacity: hov.hovered || card.menu ? 1 : 0
                            color: dotsTap.containsMouse || card.menu ? Theme.accent : card.faintInk
                            font { family: Theme.font; pixelSize: 14; bold: true }
                            MouseArea { id: dotsTap; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true; onClicked: stack.menuFor = card.menu ? "" : card.modelData }
                        }
                    }
                    Text {
                        visible: !!card.newest && card.newest.snoozed
                        text: Icons.clock + " Snoozed"
                        color: card.faintInk
                        font { family: Theme.font; pixelSize: 10 }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: card.bodyText !== ""
                        text: card.bodyText
                        textFormat: Text.StyledText
                        wrapMode: Text.Wrap
                        maximumLineCount: card.open ? 2 : 5
                        elide: Text.ElideRight
                        color: card.ink
                        linkColor: Theme.accent
                        font { family: Theme.font; pixelSize: Theme.msgBody }
                    }
                    Row {
                        visible: buttons.count > 0
                        spacing: 6
                        Layout.topMargin: 4
                        Repeater {
                            id: buttons
                            model: card.n ? (card.n.actions || []).filter(a => a.identifier !== "default" && a.text !== "") : []
                            Rectangle {
                                id: btn
                                required property var modelData
                                width: btnText.implicitWidth + 20; height: 24; radius: 7
                                color: btnTap.containsMouse ? Theme.hover : Theme.track
                                Text { id: btnText; anchors.centerIn: parent; text: btn.modelData.text; color: card.ink; font { family: Theme.font; pixelSize: 12 } }
                                MouseArea { id: btnTap; anchors.fill: parent; hoverEnabled: true; onClicked: btn.modelData.invoke() }
                            }
                        }
                    }
                    // the older ones in this card, newest first, each with its own x
                    ColumnLayout {
                        visible: card.open
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 4
                        Repeater {
                            model: card.open ? card.items.slice(0, -1).reverse().slice(0, 6) : []
                            Rectangle {
                                id: older
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: olderText.implicitHeight + 10
                                radius: 7
                                color: Theme.track
                                Text {
                                    id: olderText
                                    anchors { left: parent.left; right: olderX.left; verticalCenter: parent.verticalCenter; leftMargin: 8; rightMargin: 4 }
                                    textFormat: Text.PlainText
                                    text: (older.modelData.repeat > 1 ? "×" + older.modelData.repeat + "  " : "") + ((older.modelData.n ? older.modelData.n.summary : older.modelData.summary) + "  "
                                           + (older.modelData.n ? older.modelData.n.body : older.modelData.body).replace(/<[^>]*>/g, "")).replace(/\s+/g, " ").trim()
                                    elide: Text.ElideRight
                                    color: card.ink
                                    font { family: Theme.font; pixelSize: 11 }
                                }
                                Text {
                                    id: olderX
                                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                    text: "×"
                                    color: olderTap.containsMouse ? Theme.accent : Theme.faint
                                    font { family: Theme.font; pixelSize: 14 }
                                    MouseArea { id: olderTap; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true; onClicked: Notif.dismissItem(older.modelData) }
                                }
                            }
                        }
                    }
                    // the menu: snooze, the app's rule, dismiss
                    Flow {
                        visible: card.menu
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 5
                        Repeater {
                            model: card.menu ? [
                                { label: Icons.clock + " 15 min", act: () => Notif.snoozeGroup(card.modelData, "15m") },
                                { label: "1 h", act: () => Notif.snoozeGroup(card.modelData, "1h") },
                                { label: "Tomorrow 8:00", act: () => Notif.snoozeGroup(card.modelData, "tomorrow") },
                                { label: "Normal", on: Notif.ruleFor(card.app) === "normal", act: () => Notif.setRule(card.app, "normal") },
                                { label: "List only", on: Notif.ruleFor(card.app) === "list", act: () => Notif.setRule(card.app, "list") },
                                { label: "Mute", on: Notif.ruleFor(card.app) === "mute", act: () => Notif.setRule(card.app, "mute") },
                                { label: "Dismiss", act: () => Notif.dismissGroup(card.modelData) }
                            ] : []
                            Rectangle {
                                id: chip
                                required property var modelData
                                width: chipText.implicitWidth + 14; height: 22; radius: 7
                                color: chip.modelData.on ? Theme.accentBg : chipTap.containsMouse ? Theme.hover : Theme.track
                                Text {
                                    id: chipText
                                    anchors.centerIn: parent
                                    text: chip.modelData.label
                                    color: chip.modelData.on ? Theme.accentInk : card.ink
                                    font { family: Theme.font; pixelSize: 11 }
                                }
                                MouseArea { id: chipTap; anchors.fill: parent; hoverEnabled: true; onClicked: { stack.menuFor = ""; chip.modelData.act() } }
                            }
                        }
                    }
                }
            }
        }
    }
}
