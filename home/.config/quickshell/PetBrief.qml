// The "What's up?" page of the pet's menu (PetMenu.qml): the briefing PetSay.qml puts
// together, one line per thing, what is wrong first and in red. Long lines wrap rather
// than being cut, except the mail senders and subjects, which are one line each.
// It asks for fresh data only while it is the page being shown.
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: brief
    property bool open: false               // this is the page being shown
    visible: open
    onOpenChanged: if (open) PetSay.refresh()
    Component.onCompleted: if (open) PetSay.refresh()
    Layout.fillWidth: true
    spacing: 6

    Text {
        Layout.fillWidth: true
        text: PetSay.headline
        color: PetSay.worries > 0 ? Theme.red : Theme.accent
        font { family: Theme.font; pixelSize: 13; bold: true }
    }
    Repeater {
        model: brief.open ? PetSay.items : []
        RowLayout {
            id: line
            required property var modelData
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.preferredWidth: 18
                Layout.alignment: Qt.AlignTop
                horizontalAlignment: Text.AlignHCenter
                text: line.modelData.glyph || ""
                color: line.modelData.bad ? Theme.red : Theme.accent
                font { family: Theme.font; pixelSize: 14 }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: line.modelData.text
                    wrapMode: Text.Wrap
                    color: line.modelData.bad ? Theme.red : Theme.fg
                    font { family: Theme.font; pixelSize: 13 }
                }
                Repeater {
                    model: line.modelData.sub || []
                    Text {
                        required property string modelData
                        Layout.fillWidth: true
                        text: modelData
                        elide: Text.ElideRight
                        color: Theme.faint
                        font { family: Theme.font; pixelSize: 11 }
                    }
                }
            }
        }
    }
}
