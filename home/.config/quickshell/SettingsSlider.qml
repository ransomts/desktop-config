// A value on a slider (Slider.qml), from..to. `value` is bound to the real one; dragging says
// edited(v) (rounded to stepSize). Left/Right step by stepSize.
import QtQuick
import QtQuick.Layouts

SettingsRow {
    id: sl
    property real value: 0
    property real from: 0
    property real to: 1
    property real stepSize: 0.01
    property string text: ""
    signal edited(real v)
    function snap(v) { return Math.max(from, Math.min(to, Math.round(v / stepSize) * stepSize)) }
    onStepped: d => { const v = snap(value + d * stepSize); if (v !== value) edited(v) }
    RowLayout {
        spacing: 10
        Slider {
            Layout.preferredWidth: 200
            value: (sl.value - sl.from) / Math.max(1e-9, sl.to - sl.from)
            onMoved: f => { sl.forceActiveFocus(); const v = sl.snap(sl.from + f * (sl.to - sl.from)); if (v !== sl.value) sl.edited(v) }
        }
        Text {
            Layout.preferredWidth: 64
            horizontalAlignment: Text.AlignRight
            text: sl.text !== "" ? sl.text : String(sl.value)
            color: Theme.fg
            font { family: Theme.font; pixelSize: 13; bold: true }
        }
    }
}
