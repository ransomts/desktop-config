// A number with − and +. `value` is bound to the real one; edited(v) with v kept in from..to.
// `text` shows something other than the number (e.g. "off" for 0).
import QtQuick
import QtQuick.Layouts

SettingsRow {
    id: st
    property real value: 0
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property string suffix: ""
    property string text: ""
    signal edited(real v)
    function bump(d) { const v = Math.max(from, Math.min(to, Math.round((value + d * stepSize) * 1000) / 1000)); if (v !== value) edited(v) }
    onStepped: d => bump(d)
    onActivated: bump(1)
    RowLayout {
        spacing: 6
        SettingsChip { label: "−"; fixedWidth: 34; onClicked: { st.forceActiveFocus(); st.bump(-1) } }
        Text {
            Layout.preferredWidth: Math.max(64, implicitWidth)
            horizontalAlignment: Text.AlignHCenter
            text: st.text !== "" ? st.text : st.value + st.suffix
            color: Theme.fg
            font { family: Theme.font; pixelSize: 14; bold: true }
        }
        SettingsChip { label: "+"; fixedWidth: 34; onClicked: { st.forceActiveFocus(); st.bump(1) } }
    }
}
