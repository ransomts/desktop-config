// One setting in the settings window (Settings.qml): its name (and a line under it) on the
// left, the control on the right, or under the name when `below` is set. Every control row
// (SettingsSwitch, SettingsChoice, SettingsStepper, SettingsSlider, SettingsText, SettingsChips,
// SettingsButton, SettingsInfo) is one of these. It takes keyboard focus with Tab; Space or Enter
// is activated(), Left/Right is stepped(-1 | 1). The search (`/`) finds it by label, sub and
// keywords. A row never holds the value itself: it shows what it is given and says what was picked.
import QtQuick
import QtQuick.Layouts

FocusScope {
    id: row
    readonly property bool settingRow: true     // found by Settings.collect() for the search
    property string label: ""
    property string sub: ""
    property string keywords: ""
    property bool below: false                  // control under the label, full width
    property bool takesFocus: true              // false: read-only rows (still searchable)
    default property alias control: slot.data
    readonly property alias controlItem: slot     // (tests: the control fits the row)
    readonly property alias labelItem: text
    signal activated()
    signal stepped(int d)

    Layout.fillWidth: true
    implicitHeight: below ? text.implicitHeight + slot.implicitHeight + 22 : Math.max(text.implicitHeight, slot.implicitHeight, 30) + 12
    activeFocusOnTab: takesFocus && enabled && visible
    opacity: enabled ? 1 : 0.45

    // keyboard focus moving down a long page keeps the row in view (SettingsPage.reveal)
    onActiveFocusChanged: if (activeFocus) { let p = parent; while (p && p.reveal === undefined) p = p.parent; if (p) p.reveal(row) }
    // a short glow when the search jumps here
    function flash() { glow.opacity = 1; fade.restart() }
    Timer { id: fade; interval: 900; onTriggered: glow.opacity = 0 }

    Keys.onPressed: event => {
        if (!row.enabled) return
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { row.activated(); event.accepted = true }
        else if (event.key === Qt.Key_Left) { row.stepped(-1); event.accepted = true }
        else if (event.key === Qt.Key_Right) { row.stepped(1); event.accepted = true }
    }

    Rectangle {
        id: glow
        anchors { fill: parent; leftMargin: -8; rightMargin: -8 }
        radius: 8
        color: Theme.hover
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
    }
    Rectangle {                                 // keyboard focus
        anchors { fill: parent; leftMargin: -8; rightMargin: -8 }
        radius: 8
        color: "transparent"
        border.width: 2
        border.color: Theme.accentBg
        visible: row.activeFocus
    }

    Column {
        id: text
        x: 0
        y: row.below ? 6 : (row.height - implicitHeight) / 2
        width: row.below ? row.width : Math.max(120, row.width - slot.implicitWidth - 16)
        spacing: 2
        Text {
            width: parent.width
            text: row.label
            color: Theme.fg
            elide: Text.ElideRight
            font { family: Theme.font; pixelSize: 13 }
        }
        Text {
            width: parent.width
            visible: row.sub !== ""
            text: row.sub
            color: Theme.faint
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font { family: Theme.font; pixelSize: 11 }
        }
    }
    Item {
        id: slot
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
        width: row.below ? row.width : implicitWidth
        height: implicitHeight
        anchors { right: parent.right }
        y: row.below ? 6 + text.implicitHeight + 8 : (row.height - height) / 2
    }
}
