// The bar's health pill (state and wording; Health.qml has the data). Hidden while every
// background job works and nothing needs a look. Stale: amber text. Failing: red fill. Hover: the
// bad jobs listed. Click: the popup "health" (HealthList.qml), which the bar opens: the owner connects onClicked.
// Notices (updates, a restart, low disk) never colour it: when only an actionable one is waiting
// the pill is a small faint dot, and its tooltip says what. Plain "12 updates" is in the popup only.
import QtQuick

Pill {
    id: pill
    readonly property bool failing: Health.worst === "failed"
    readonly property int count: Health.bad.length
    readonly property bool dot: Health.worst === "ok" && Health.attention
    text: Health.worst !== "ok" ? "⚠ " + count : dot ? "•" : ""
    bold: true
    pad: dot ? 8 : 12
    fill: failing ? Theme.red : Theme.bg
    ink: failing ? Theme.accentInk : dot ? Theme.faint : Theme.warn
    tip: Health.worst !== "ok" ? "<b>" + (failing ? "Something is failing" : "Something is behind") + "</b>\n" + Health.tooltip() + "\nClick: details"
         : dot ? "<b>Worth a look</b>\n" + Health.notices.filter(n => n.actionable).map(n => n.name + ": " + n.why).join("\n") + "\nClick: details" : ""
}
