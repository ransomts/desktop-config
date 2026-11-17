// An on/off setting. `checked` is bound to the real value; a click or Space says edited(!checked)
// and the page writes it (the switch moves when the value does).
import QtQuick

SettingsRow {
    id: sw
    property bool checked: false
    signal edited(bool on)
    onActivated: edited(!checked)
    onStepped: d => { if ((d > 0) !== checked) edited(d > 0) }
    Rectangle {
        id: track
        width: 46; height: 26; radius: 13
        color: sw.checked ? Theme.accentBg : Theme.track
        border.width: 1
        border.color: sw.checked ? Theme.accentBg : Theme.line
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            width: 20; height: 20; radius: 10
            y: 3
            x: sw.checked ? parent.width - width - 3 : 3
            color: sw.checked ? Theme.accentInk : Theme.fg
            Behavior on x { NumberAnimation { duration: 120 } }
        }
        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: { sw.forceActiveFocus(); sw.edited(!sw.checked) } }
    }
}
