// One of a long list (a screen's modes, its scales) as ‹ value ›: too many for a row of chips.
// `values` and `labels` side by side; `value` is bound to the real one; edited(v) on a click
// or Left/Right. Space or Enter steps forward.
import QtQuick
import QtQuick.Layouts

SettingsRow {
    id: pk
    property var values: []
    property var labels: []
    property var value
    property real valueWidth: 190
    signal edited(var v)
    readonly property int index: values.indexOf(value)
    function bump(d) {
        if (!values.length) return
        const i = index < 0 ? 0 : Math.max(0, Math.min(values.length - 1, index + d))
        if (values[i] !== value) edited(values[i])
    }
    onStepped: d => bump(d)
    onActivated: bump(index >= values.length - 1 ? -values.length : 1)
    RowLayout {
        spacing: 6
        SettingsChip { label: "‹"; fixedWidth: 30; opacity: pk.index > 0 ? 1 : 0.4; onClicked: { pk.forceActiveFocus(); pk.bump(-1) } }
        Text {
            Layout.preferredWidth: pk.valueWidth
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: pk.index >= 0 ? String(pk.labels[pk.index] || pk.values[pk.index]) : String(pk.value || "")
            color: Theme.fg
            font { family: Theme.font; pixelSize: 13; bold: true }
        }
        SettingsChip { label: "›"; fixedWidth: 30; opacity: pk.index >= 0 && pk.index < pk.values.length - 1 ? 1 : 0.4; onClicked: { pk.forceActiveFocus(); pk.bump(1) } }
    }
}
