// The polkit password prompt itself (AuthPrompt.qml puts it on the focused screen): a dimmed
// backdrop and a centred card saying what is asking (the action's message, its id in small
// text), who is authenticating (a picker when polkit offers several identities), a password
// field drawn as dots, PAM's own info/error lines, Cancel (Esc) and Authenticate (Enter).
//
// `flow` is a Quickshell.Services.Polkit AuthFlow (tests hand it a stand-in with the same API;
// notes in the auth agent's polkit-api.org). The password lives only in `typed`: it is never
// logged or written anywhere, handed to flow.submit() once, and cleared on every way out
// (submitted, wrong, cancelled by Esc or by polkit, another identity, the next request, the
// view going away).
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: view
    property var flow: null
    // Caps Lock, read when a request comes in and a moment after each press of the key (as the
    // lock screen does: the keyboard LEDs, and what Hyprland says of each keyboard)
    property bool caps: false
    readonly property var defaultCapsCmd: ["env", "-u", "LD_LIBRARY_PATH", "-u", "LIBGL_DRIVERS_PATH", "-u", "LIBVA_DRIVERS_PATH",
        "sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null; hyprctl -j devices 2>/dev/null | grep -c '\"capsLock\": true'"]
    property var capsCmd: defaultCapsCmd

    property string typed: ""
    property bool checking: false           // submitted, waiting for PAM's verdict
    property bool wrong: false              // the last try failed; until the next key
    property int fails: 0
    property bool wantSubmit: false         // Enter came before PAM asked; send it when it does
    property bool switching: false          // selecting an identity (the flow reports a spurious failure meanwhile)
    readonly property bool asked: flow !== null && flow.isResponseRequired === true
    readonly property bool echo: asked && flow.responseVisible === true    // PAM said this answer is not secret
    readonly property var ids: flow && flow.identities ? flow.identities : []
    readonly property string user: Quickshell.env("USER") || ""

    function clear() { typed = ""; wantSubmit = false }
    function idName(i) {
        if (!i) return ""
        const n = i.string || String(i.id)
        const d = i.displayName && i.displayName !== n ? i.displayName + "  (" + n + ")" : n
        return i.isGroup ? "group " + d : d
    }
    // the same identity (a Repeater's modelData may be a copy, so compare uid/gid, not objects)
    function same(a, b) { return !!a && !!b && a.id === b.id && a.isGroup === b.isGroup }
    function pick(i) {
        i = ids.find(x => same(x, i)) || null             // always hand the flow one of its own
        if (!flow || !i || same(i, flow.selectedIdentity) || checking) return
        clear(); wrong = false
        switching = true
        flow.selectedIdentity = i
        switching = false
        view.forceActiveFocus()
    }
    function cycle(step) {
        if (ids.length < 2 || !flow) return
        const at = Math.max(0, ids.findIndex(x => same(x, flow.selectedIdentity)))
        pick(ids[(at + step + ids.length) % ids.length])
    }
    function submit() {
        if (!flow || checking || flow.isCompleted || typed === "") return
        if (!flow.isResponseRequired) { wantSubmit = true; return }
        const v = typed
        clear()
        checking = true; wrong = false
        flow.submit(v)
    }
    function cancel() {
        const f = flow
        clear(); checking = false
        if (f && !f.isCompleted) f.cancelAuthenticationRequest()
    }
    function key(event) {
        if (!flow) return
        if (event.key === Qt.Key_Escape) { cancel(); return }
        if (event.key === Qt.Key_CapsLock) { capsSoon.restart(); return }
        if (checking) return
        if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) { cycle(-1); return }
        if (event.key === Qt.Key_Tab) { cycle(1); return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { submit(); return }
        if (event.key === Qt.Key_Backspace) { typed = typed.slice(0, -1); return }
        if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) { clear(); return }
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
        if (event.text.length > 0 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            wrong = false
            typed += event.text
        }
    }

    onFlowChanged: {
        clear(); checking = false; wrong = false; fails = 0
        if (!flow) return
        // polkit offers the identities in its own order; start with the person at the keyboard
        const me = ids.find(i => !i.isGroup && i.string === user)
        if (me && !same(me, flow.selectedIdentity)) pick(me)
        Qt.callLater(view.readCaps)
        view.forceActiveFocus()
    }
    Component.onCompleted: { if (flow) flowChanged(); view.forceActiveFocus() }
    Component.onDestruction: clear()

    Connections {
        target: view.flow
        ignoreUnknownSignals: true
        function onAuthenticationFailed() {
            if (view.switching) return
            view.clear(); view.checking = false; view.wrong = true; view.fails += 1
            shake.restart()
            view.forceActiveFocus()
        }
        function onAuthenticationSucceeded() { view.clear(); view.checking = false }
        function onAuthenticationRequestCancelled() { view.clear(); view.checking = false }
        function onIsCompletedChanged() { if (view.flow && view.flow.isCompleted) { view.clear(); view.checking = false } }
        function onIsResponseRequiredChanged() {
            if (!view.flow || !view.flow.isResponseRequired) return
            view.checking = false                       // a next prompt (a second factor), or a fresh try
            if (view.wantSubmit) view.submit()
        }
    }

    Process {
        id: capsRead
        command: view.capsCmd
        stdout: StdioCollector { onStreamFinished: view.caps = /^\s*[1-9]/m.test(text) }
    }
    function readCaps() { if (view.flow && !capsRead.running) capsRead.running = true }
    Timer { id: capsSoon; interval: 150; onTriggered: view.readCaps() }

    focus: true
    Keys.onPressed: event => { view.key(event); event.accepted = true }

    // ---- what it looks like ----
    Rectangle {                                 // the dimmed desktop (as the overview's backdrop)
        anchors.fill: parent
        color: Theme.dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(1, 1, 1, 0.45)
    }
    MouseArea { anchors.fill: parent; onClicked: view.forceActiveFocus() }   // a click outside does nothing

    Rectangle {
        id: card
        objectName: "card"
        anchors.centerIn: parent
        width: Math.min(460, parent.width - 32)
        height: body.implicitHeight + 48
        radius: 16
        color: Theme.solidBg
        border.width: 1
        border.color: Theme.line

        Column {
            id: body
            x: 24; y: 24
            width: card.width - 48
            spacing: 14

            Row {
                spacing: 14
                width: parent.width
                Rectangle {
                    width: 44; height: 44; radius: 22
                    color: Theme.tint(Theme.accentBg, 0.18)
                    Image {
                        id: icon
                        anchors.centerIn: parent
                        width: 28; height: 28
                        sourceSize: Qt.size(56, 56)
                        source: view.flow && view.flow.iconName ? Quickshell.iconPath(view.flow.iconName, true) : ""
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !icon.visible
                        text: ""
                        color: Theme.accent
                        font { family: Theme.font; pixelSize: 20 }
                    }
                }
                Column {
                    width: parent.width - 58
                    spacing: 3
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "Authentication required"
                        color: Theme.fg
                        font { family: Theme.font; pixelSize: 16; bold: true }
                    }
                    Text {
                        objectName: "actionId"
                        width: parent.width
                        text: view.flow ? view.flow.actionId : ""
                        color: Theme.faint
                        elide: Text.ElideMiddle
                        font { family: Theme.font; pixelSize: 11 }
                    }
                }
            }

            Text {
                objectName: "message"
                width: parent.width
                text: view.flow ? view.flow.message : ""
                color: Theme.fg
                wrapMode: Text.Wrap
                font { family: Theme.font; pixelSize: 13 }
                lineHeight: 1.15
            }

            // who is authenticating: one line, or a row of choices (Tab / Shift+Tab, or a click)
            Column {
                width: parent.width
                spacing: 6
                Text {
                    text: view.ids.length > 1 ? "Authenticate as  (Tab to switch)" : "Authenticating as"
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 11 }
                }
                Text {
                    objectName: "identity"
                    visible: view.ids.length <= 1
                    text: view.flow ? view.idName(view.flow.selectedIdentity) : ""
                    color: Theme.fg
                    font { family: Theme.font; pixelSize: 13; bold: true }
                }
                Flow {
                    visible: view.ids.length > 1
                    width: parent.width
                    spacing: 6
                    Repeater {
                        objectName: "picker"
                        model: view.ids.length > 1 ? view.ids : []
                        Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool on: view.flow !== null && view.same(view.flow.selectedIdentity, modelData)
                            objectName: "chip"
                            width: chipText.implicitWidth + 20; height: 28; radius: 14
                            color: on ? Theme.accentBg : chipMouse.containsMouse ? Theme.hover : Theme.track
                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: view.idName(chip.modelData)
                                color: chip.on ? Theme.accentInk : Theme.fg
                                font { family: Theme.font; pixelSize: 12; bold: chip.on }
                            }
                            MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; onClicked: view.pick(chip.modelData) }
                        }
                    }
                }
            }

            Rectangle {
                id: field
                objectName: "field"
                width: parent.width; height: 52; radius: 12
                color: Theme.track
                border.width: 2
                border.color: view.wrong ? Theme.red : view.checking ? Theme.faint : Theme.accent
                readonly property int count: view.typed.length
                readonly property bool showDots: count > 0 && !view.checking && !view.echo

                Row {
                    objectName: "dots"
                    anchors.centerIn: parent
                    spacing: 9
                    visible: field.showDots
                    Repeater {
                        model: field.showDots ? Math.min(field.count, 28) : 0
                        Rectangle { width: 9; height: 9; radius: 4.5; color: Theme.fg }
                    }
                }
                Text {                          // only for an answer PAM marked as not secret (echo on)
                    anchors.centerIn: parent
                    width: parent.width - 28
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideLeft
                    visible: view.echo && field.count > 0 && !view.checking
                    text: view.echo ? view.typed : ""
                    color: Theme.fg
                    font { family: Theme.font; pixelSize: 14 }
                }
                Text {
                    objectName: "placeholder"
                    anchors.centerIn: parent
                    visible: field.count === 0 || view.checking
                    text: view.checking ? "Authenticating…"
                        : view.asked ? (view.flow.inputPrompt || "Password").replace(/:\s*$/, "")
                        : "Waiting…"
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 14 }
                }
                transform: Translate { id: nudge }
                SequentialAnimation {
                    id: shake
                    NumberAnimation { target: nudge; property: "x"; to: -12; duration: 50 }
                    NumberAnimation { target: nudge; property: "x"; to: 12; duration: 80 }
                    NumberAnimation { target: nudge; property: "x"; to: -8; duration: 70 }
                    NumberAnimation { target: nudge; property: "x"; to: 0; duration: 60 }
                }
            }

            // one line: a wrong password, else PAM's own message, else Caps Lock
            Text {
                objectName: "status"
                width: parent.width
                height: Math.max(implicitHeight, 18)
                wrapMode: Text.Wrap
                readonly property bool pamErr: view.flow && view.flow.supplementaryMessage && view.flow.supplementaryIsError
                text: view.wrong ? "That password didn't match. Try again."
                    : view.flow && view.flow.supplementaryMessage ? view.flow.supplementaryMessage
                    : view.caps ? "Caps Lock is on" : ""
                color: view.wrong || pamErr ? Theme.red : view.caps && !(view.flow && view.flow.supplementaryMessage) ? Theme.warn : Theme.faint
                font { family: Theme.font; pixelSize: 12 }
            }

            Row {
                anchors.right: parent.right
                spacing: 10
                Rectangle {
                    objectName: "cancel"
                    width: cancelText.implicitWidth + 28; height: 34; radius: 10
                    color: cancelMouse.containsMouse ? Theme.hover : "transparent"
                    border.width: 1; border.color: Theme.line
                    Text {
                        id: cancelText
                        anchors.centerIn: parent
                        text: "Cancel  Esc"
                        color: Theme.fg
                        font { family: Theme.font; pixelSize: 12 }
                    }
                    MouseArea { id: cancelMouse; anchors.fill: parent; hoverEnabled: true; onClicked: view.cancel() }
                }
                Rectangle {
                    objectName: "ok"
                    readonly property bool can: view.typed.length > 0 && !view.checking
                    width: okText.implicitWidth + 28; height: 34; radius: 10
                    color: can ? Theme.accentBg : Theme.track
                    Text {
                        id: okText
                        anchors.centerIn: parent
                        text: "Authenticate  ⏎"
                        color: parent.can ? Theme.accentInk : Theme.faint
                        font { family: Theme.font; pixelSize: 12; bold: true }
                    }
                    MouseArea { anchors.fill: parent; onClicked: { view.submit(); view.forceActiveFocus() } }
                }
            }
        }
    }
}
