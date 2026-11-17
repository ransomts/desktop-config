// An action. With `confirm` set (what it will do, e.g. "reloads Hyprland and the shell") the first
// click only arms it: the button says so and waits 4 s for a second click; then clicked().
import QtQuick

SettingsRow {
    id: bt
    property string text: ""
    property string confirm: ""
    property bool armed: false
    property bool lit: false
    signal clicked()
    function press() {
        if (confirm === "" || armed) { armed = false; disarm.stop(); clicked() }
        else { armed = true; disarm.restart() }
    }
    onActivated: press()
    Timer { id: disarm; interval: 4000; onTriggered: bt.armed = false }
    SettingsChip {
        label: bt.armed ? "Click again: " + bt.confirm : bt.text
        on: bt.lit || bt.armed
        tone: bt.armed ? Theme.warn : "transparent"
        onClicked: { bt.forceActiveFocus(); bt.press() }
    }
}
