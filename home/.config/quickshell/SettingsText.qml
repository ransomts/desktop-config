// A line of text, applied on Enter. Shows the real value (`value`) whenever it is not being
// edited; typing starts an edit, Enter says edited(text), Esc puts the real value back.
// `valid(text)` may refuse what was typed (the field turns red and nothing is written).
import QtQuick

SettingsRow {
    id: tf
    property string value: ""
    property string placeholder: ""
    property real fieldWidth: 200
    property var valid: function(t) { return true }
    readonly property bool editing: input.activeFocus && input.text !== value
    readonly property alias input: input
    signal edited(string text)
    onActivated: input.forceActiveFocus()
    onValueChanged: if (!input.activeFocus) input.text = value
    Component.onCompleted: input.text = value
    function commit() {
        const t = input.text.trim()
        if (!valid(t)) { bad.restart(); return }
        if (t !== value) edited(t)
        tf.forceActiveFocus()
    }
    Rectangle {
        width: tf.below ? tf.width : tf.fieldWidth
        height: 30
        radius: 8
        color: Theme.track
        border.width: input.activeFocus || bad.running ? 2 : 1
        border.color: bad.running ? Theme.red : input.activeFocus ? Theme.accentBg : Theme.line
        Timer { id: bad; interval: 1200 }
        TextInput {
            id: input
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: Theme.fg
            selectionColor: Theme.hover
            font { family: Theme.font; pixelSize: 13 }
            activeFocusOnTab: false
            onAccepted: tf.commit()
            onActiveFocusChanged: if (!activeFocus && !tf.editing) text = tf.value
            Keys.onEscapePressed: event => { text = tf.value; tf.forceActiveFocus(); event.accepted = true }
            Keys.onTabPressed: event => { tf.commit(); event.accepted = false }
        }
        Text {
            anchors { fill: parent; leftMargin: 10 }
            verticalAlignment: Text.AlignVCenter
            visible: input.text === "" && !input.activeFocus
            text: tf.placeholder
            color: Theme.faint
            font { family: Theme.font; pixelSize: 12; italic: true }
        }
        MouseArea { anchors.fill: parent; visible: !input.activeFocus; onClicked: input.forceActiveFocus() }
    }
}
