// One of several values, as a row of chips. `options` is a list of values, or of [value, label]
// pairs; `value` is bound to the real one. A click, or Left/Right, says edited(v).
// `wrapWidth`: chips wrap onto more lines within this width (0: one line); `below` puts them under the label.
import QtQuick

SettingsRow {
    id: ch
    property var options: []
    property var value
    property real wrapWidth: 0
    property real chipWidth: 0
    signal edited(var v)
    readonly property var vals: options.map(o => Array.isArray(o) ? o[0] : o)
    readonly property int index: vals.indexOf(value)
    onStepped: d => { if (vals.length) edited(vals[index < 0 ? 0 : Math.max(0, Math.min(vals.length - 1, index + d))]) }
    onActivated: if (vals.length) edited(vals[(index + 1) % vals.length])
    Flow {
        width: ch.below ? ch.width : ch.wrapWidth > 0 ? Math.min(ch.wrapWidth, implicitW) : implicitW
        readonly property real implicitW: {
            let w = 0
            for (let i = 0; i < rep.count; i++) { const c = rep.itemAt(i); if (c) w += c.implicitWidth + (i ? spacing : 0) }
            return w
        }
        spacing: 6
        Repeater {
            id: rep
            model: ch.options
            SettingsChip {
                required property int index
                readonly property var o: ch.options[index]        // (modelData of a nested list is not a JS array)
                readonly property var v: Array.isArray(o) ? o[0] : o
                label: Array.isArray(o) ? o[1] : String(o)
                on: v === ch.value
                fixedWidth: ch.chipWidth
                onClicked: { ch.forceActiveFocus(); ch.edited(v) }
            }
        }
    }
}
