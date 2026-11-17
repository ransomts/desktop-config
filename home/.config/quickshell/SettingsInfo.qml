// A read-only value: name on the left, the value on the right (selectable, so it can be copied).
import QtQuick

SettingsRow {
    id: info
    property string value: ""
    property bool mono: false
    takesFocus: false
    TextEdit {
        width: Math.min(implicitWidth, Math.max(160, info.width * 0.6))
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.Wrap
        horizontalAlignment: Text.AlignRight
        text: info.value
        color: Theme.fg
        selectionColor: Theme.hover
        font { family: Theme.font; pixelSize: 12 }
    }
}
