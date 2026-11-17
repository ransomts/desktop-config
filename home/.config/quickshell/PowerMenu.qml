// Lock, suspend, log out, reboot, shut down. The last three ask once more:
// the row changes to "Click again to …" and only the second click does it.
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: power
    signal done()
    property string armed: ""
    spacing: 4
    Caption { text: "Power" }
    Repeater {
        model: [
            { name: "Lock",      cmd: "$HOME/.local/bin/lock-now", confirm: false },
            { name: "Suspend",   cmd: "systemctl suspend",     confirm: false },
            { name: "Log out",   cmd: "$HOME/.local/bin/session-save --if-enabled; uwsm stop", confirm: true },
            { name: "Reboot",    cmd: "$HOME/.local/bin/session-save --if-enabled; systemctl reboot", confirm: true },
            { name: "Shut down", cmd: "$HOME/.local/bin/session-save --if-enabled; systemctl poweroff", confirm: true }
        ]
        MenuRow {
            required property var modelData
            label: power.armed === modelData.name ? "Click again to " + modelData.name.toLowerCase() : modelData.name
            danger: power.armed === modelData.name
            onClicked: {
                if (modelData.confirm && power.armed !== modelData.name) { power.armed = modelData.name; return }
                Sys.run(modelData.cmd)
                power.done()
            }
        }
    }
}
