// Window switcher (Alt+Tab): every open window on every desktop, most recently used
// first, as a row of live thumbnails on the focused screen. Hold Alt and press Tab
// (Shift+Tab goes back) to move along; letting go of Alt goes to the picked window.
// Enter or a click also picks, Escape cancels. Opens on the previous window, so a
// quick Alt+Tab flips between the last two.
// Driven by `qs ipc call switcher next` / `prev` from the ALT + Tab binds in hyprland.lua.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

PanelWindow {
    id: sw
    visible: false
    property var wins: []           // [{ address, title, cls, ws, toplevel }] most recent first
    property int sel: 0
    property int pending: 0         // Tab presses that arrived before the list did

    function step(d) {
        if (!visible) {
            pending = d
            commitWaiting = false
            wins = []
            Hyprland.refreshToplevels()
            list.running = true
            visible = true
            return
        }
        if (wins.length === 0) { pending += d; return }
        sel = ((sel + d) % wins.length + wins.length) % wins.length
    }
    property bool commitWaiting: false   // Alt let go before the list arrived
    function commit() {
        if (!visible) return
        if (wins.length === 0) { commitWaiting = true; return }
        pick(sel)
    }
    function pick(i) {
        commitWaiting = false
        visible = false
        const w = wins[i]
        if (!w) return
        // after the overlay has gone: closing it hands focus back to the window it took it from
        Sys.run("sleep 0.05; hyprctl dispatch 'hl.dsp.focus({ window = \"address:" + w.address + "\" })'")
    }
    onVisibleChanged: if (visible) keys.forceActiveFocus()

    Process {
        id: list
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let cs = []
                try { cs = JSON.parse(text) } catch (e) {}
                cs = cs.filter(c => c.mapped && c.workspace && c.workspace.id !== 0)
                cs.sort((a, b) => (a.focusHistoryID ?? 99) - (b.focusHistoryID ?? 99))
                const tls = Hyprland.toplevels.values
                sw.wins = cs.map(c => {
                    const bare = c.address.replace(/^0x/, "")
                    return {
                        address: c.address, title: c.title, cls: c.class,
                        ws: c.workspace.id < 0 ? "scratch" : c.workspace.id >= 11 ? "Desktop " + Math.floor(c.workspace.id / 10) : "ws " + c.workspace.id,
                        toplevel: tls.find(t => t.address.replace(/^0x/, "") === bare) || null
                    }
                })
                if (sw.wins.length === 0) { sw.visible = false; return }
                const start = sw.pending > 0 ? sw.pending : sw.wins.length + sw.pending
                sw.sel = Math.min(sw.wins.length - 1, Math.max(0, start % sw.wins.length))
                sw.pending = 0
                if (sw.commitWaiting) sw.pick(sw.sel)
            }
        }
    }

    screen: {
        const m = Hyprland.focusedMonitor
        return Quickshell.screens.find(s => m && s.name === m.name) || Quickshell.screens[0]
    }
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-switcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    MouseArea { anchors.fill: parent; onClicked: sw.visible = false }
    Item {
        id: keys
        focus: true
        Keys.onReleased: event => {
            if (event.key === Qt.Key_Alt || event.key === Qt.Key_Meta) { sw.pick(sw.sel); event.accepted = true }
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) sw.visible = false
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) sw.pick(sw.sel)
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) sw.step(1)
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) sw.step(-1)
            else return
            event.accepted = true
        }
    }

    readonly property real thumbH: 150
    readonly property real cardW: 240

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, row.implicitWidth + 32)
        height: row.implicitHeight + 32
        radius: 16
        color: Theme.panelBg
        border.width: 1
        border.color: Theme.line
        visible: sw.wins.length > 0

        Flickable {
            id: flick
            anchors { fill: parent; margins: 16 }
            contentWidth: row.implicitWidth
            clip: true
            interactive: false
            // keep the picked card in view when there are more windows than fit
            contentX: {
                const c = cards.itemAt(sw.sel)
                if (!c || row.implicitWidth <= width) return 0
                return Math.max(0, Math.min(row.implicitWidth - width, c.x + c.width / 2 - width / 2))
            }
            Behavior on contentX { NumberAnimation { duration: 120 } }

            Row {
                id: row
                spacing: 12
                Repeater {
                    id: cards
                    model: sw.wins
                    Rectangle {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property bool picked: index === sw.sel
                        width: sw.cardW
                        height: sw.thumbH + 58
                        radius: 12
                        color: picked ? Theme.hover : tap.containsMouse ? Theme.track : "transparent"
                        border.width: 2
                        border.color: picked ? Theme.accentBg : "transparent"

                        MouseArea { id: tap; anchors.fill: parent; hoverEnabled: true; onClicked: sw.pick(card.index) }

                        Rectangle {
                            id: frame
                            x: 8; y: 8
                            width: parent.width - 16; height: sw.thumbH
                            radius: 6
                            color: Theme.track
                            clip: true
                            ScreencopyView {
                                id: shot
                                anchors.centerIn: parent
                                // fit the window's shape inside the frame
                                readonly property real ar: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : frame.width / frame.height
                                width: Math.min(frame.width, frame.height * ar)
                                height: Math.min(frame.height, frame.width / ar)
                                captureSource: sw.visible && card.modelData.toplevel ? card.modelData.toplevel.wayland : null
                                live: true
                            }
                            IconImage {     // until the first frame arrives (or if capture isn't possible)
                                visible: !shot.hasContent
                                anchors.centerIn: parent
                                implicitSize: 64
                                source: icon.source
                            }
                        }
                        RowLayout {
                            x: 10; y: sw.thumbH + 16
                            width: parent.width - 20
                            spacing: 8
                            IconImage {
                                id: icon
                                implicitSize: 22
                                source: {
                                    const e = DesktopEntries.heuristicLookup(card.modelData.cls)
                                    return Quickshell.iconPath(e && e.icon ? e.icon : card.modelData.cls.toLowerCase(), true)
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: card.modelData.title || card.modelData.cls
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    color: card.picked ? Theme.accent : Theme.fg
                                    font { family: Theme.font; pixelSize: 12; bold: card.picked }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: card.modelData.ws
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: Theme.faint
                                    font { family: Theme.font; pixelSize: 10 }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
