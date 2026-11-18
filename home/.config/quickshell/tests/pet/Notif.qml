// Test stand-in for Notif.qml (the real one registers as the notification daemon).
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    property bool dnd: false
    property var history: []
    readonly property int unseen: history.filter(e => e.seen === false).length
    function setDnd(on) { dnd = on }
    function arrive(app, summary) { history = [{ app: app, summary: summary, body: "", critical: false, seen: false, time: "" }].concat(history) }
    function markSeen() { history = history.map(e => Object.assign({}, e, { seen: true })) }
}
