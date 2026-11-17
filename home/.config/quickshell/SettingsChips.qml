// A list of words as chips: × removes one, the field adds one (Enter). `items` is bound to the
// real list; edited(list) gives the whole new list. Backspace in the empty field removes the last.
// Duplicates (ignoring case) are not added.
import QtQuick

SettingsRow {
    id: cl
    property var items: []
    property string placeholder: "add…"
    property var valid: function(t) { return t !== "" }
    signal edited(var list)
    below: true
    onActivated: add.forceActiveFocus()
    // true when the word is in the list afterwards (added, or there already)
    function addOne(t) {
        t = t.trim()
        if (items.some(x => String(x).toLowerCase() === t.toLowerCase())) return true
        if (!valid(t)) return false
        edited(items.concat([t])); return true
    }
    function removeAt(i) { const l = items.slice(); l.splice(i, 1); edited(l) }
    Flow {
        width: cl.width
        spacing: 6
        Repeater {
            model: cl.items
            Rectangle {
                required property var modelData
                required property int index
                implicitWidth: word.implicitWidth + 40
                implicitHeight: 28
                radius: 14
                color: Theme.track
                border.width: 1
                border.color: Theme.line
                Text {
                    id: word
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: String(modelData)
                    color: Theme.fg
                    font { family: Theme.font; pixelSize: 12 }
                }
                Text {
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "×"
                    color: x_.containsMouse ? Theme.red : Theme.faint
                    font { family: Theme.font; pixelSize: 14; bold: true }
                    MouseArea { id: x_; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: cl.removeAt(index) }
                }
            }
        }
        Rectangle {
            implicitWidth: 150
            implicitHeight: 28
            radius: 14
            color: "transparent"
            border.width: add.activeFocus ? 2 : 1
            border.color: add.activeFocus ? Theme.accentBg : Theme.line
            TextInput {
                id: add
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Theme.fg
                selectionColor: Theme.hover
                font { family: Theme.font; pixelSize: 12 }
                onAccepted: if (cl.addOne(text)) text = ""
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Backspace && text === "" && cl.items.length) { cl.removeAt(cl.items.length - 1); event.accepted = true }
                    else if (event.key === Qt.Key_Escape) { text = ""; cl.forceActiveFocus(); event.accepted = true }
                }
            }
            Text {
                anchors { fill: parent; leftMargin: 12 }
                verticalAlignment: Text.AlignVCenter
                visible: add.text === "" && !add.activeFocus
                text: cl.placeholder
                color: Theme.faint
                font { family: Theme.font; pixelSize: 12; italic: true }
            }
            MouseArea { anchors.fill: parent; visible: !add.activeFocus; onClicked: add.forceActiveFocus() }
        }
    }
    readonly property alias field: add
}
