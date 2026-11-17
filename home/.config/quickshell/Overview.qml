// Desktops overview (Super+Tab): every desktop as a card with a live miniature
// of each screen and its windows. Click a window to go to it, a card to go to
// that desktop; Escape or a click on the backdrop closes. Number keys 1-9 jump.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: ov
    visible: false
    function toggle() { visible = !visible }
    function go(n) { visible = false; Sys.goDesktop(n) }
    function focusWindow(t) {
        visible = false
        const addr = t.address.startsWith("0x") ? t.address : "0x" + t.address
        Sys.run("hyprctl dispatch 'hl.dsp.focus({ window = \"address:" + addr + "\" })'")
    }
    onVisibleChanged: if (visible) { Hyprland.refreshMonitors(); Hyprland.refreshWorkspaces(); Hyprland.refreshToplevels(); keys.forceActiveFocus() }

    // screens in layout coordinates (a rotated screen swaps width and height)
    readonly property var mons: Hyprland.monitors.values.map(m => {
        const o = m.lastIpcObject || {}
        const turned = (o.transform || 0) % 2 === 1
        const w = (turned ? m.height : m.width) / m.scale, h = (turned ? m.width : m.height) / m.scale
        return { name: m.name, x: m.x, y: m.y, w: w, h: h, slot: Sys.slotOf(m.name) }
    })
    readonly property real minX: Math.min(...mons.map(m => m.x))
    readonly property real minY: Math.min(...mons.map(m => m.y))
    readonly property real spanW: Math.max(1, Math.max(...mons.map(m => m.x + m.w)) - minX)
    readonly property real spanH: Math.max(1, Math.max(...mons.map(m => m.y + m.h)) - minY)
    readonly property var desktops: {
        const seen = {}
        seen[Sys.desktop] = true
        for (const w of Hyprland.workspaces.values) if (w.id >= 11) seen[Math.floor(w.id / 10)] = true
        return Object.keys(seen).map(Number).sort((a, b) => a - b)
    }
    readonly property int cols: mons.length > 1 ? Math.min(2, desktops.length) : Math.min(3, desktops.length)
    readonly property real mapW: Math.min((width - 120 - (cols - 1) * 24) / Math.max(1, cols) - 28, (height - 220) / Math.ceil(desktops.length / Math.max(1, cols)) * spanW / spanH)
    readonly property real k: mapW / spanW

    screen: {
        const m = Hyprland.focusedMonitor
        return Quickshell.screens.find(s => m && s.name === m.name) || Quickshell.screens[0]
    }
    color: Theme.dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(1, 1, 1, 0.45)   // dims and (with the blur rule) frosts the screen behind
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-overview"      // blurred by a layer rule in hyprland.lua
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    MouseArea { anchors.fill: parent; onClicked: ov.visible = false }
    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: ov.visible = false
        Keys.onPressed: event => {
            const n = event.key - Qt.Key_0
            if (n >= 1 && n <= 9) { ov.go(n); event.accepted = true }
        }
    }

    GridLayout {
        anchors.centerIn: parent
        columns: Math.max(1, ov.cols)
        columnSpacing: 24
        rowSpacing: 24

        Repeater {
            model: ov.desktops
            Rectangle {
                id: card
                required property int modelData
                readonly property int desk: modelData
                readonly property bool current: desk === Sys.desktop
                implicitWidth: ov.mapW + 28
                implicitHeight: ov.spanH * ov.k + 28 + 30
                radius: 14
                color: Theme.panelBg
                border.width: 2
                border.color: current ? Theme.accentBg : cardTap.containsMouse ? Theme.accent : Theme.line

                MouseArea { id: cardTap; anchors.fill: parent; hoverEnabled: true; onClicked: ov.go(card.desk) }

                Text {
                    x: 14; y: 10
                    text: "Desktop " + card.desk
                    color: card.current ? Theme.accent : Theme.fg
                    font { family: Theme.font; pixelSize: 14; bold: card.current }
                }
                Item {
                    x: 14; y: 40
                    width: ov.mapW; height: ov.spanH * ov.k

                    Repeater {
                        model: ov.mons
                        Rectangle {
                            id: mon
                            required property var modelData
                            readonly property int wsId: card.desk * 10 + modelData.slot
                            x: (modelData.x - ov.minX) * ov.k
                            y: (modelData.y - ov.minY) * ov.k
                            width: modelData.w * ov.k
                            height: modelData.h * ov.k
                            radius: 6
                            color: Theme.track
                            clip: true

                            Repeater {
                                model: Hyprland.toplevels.values.filter(t => t.workspace && t.workspace.id === mon.wsId)
                                Rectangle {
                                    id: win
                                    required property var modelData
                                    readonly property var geo: modelData.lastIpcObject || {}
                                    readonly property var at: geo.at || [mon.modelData.x, mon.modelData.y]
                                    readonly property var size: geo.size || [mon.modelData.w, mon.modelData.h]
                                    x: (at[0] - mon.modelData.x) * ov.k
                                    y: (at[1] - mon.modelData.y) * ov.k
                                    width: size[0] * ov.k
                                    height: size[1] * ov.k
                                    radius: 4
                                    color: Theme.solidBg
                                    border.width: winTap.containsMouse ? 2 : 1
                                    border.color: winTap.containsMouse ? Theme.accentBg : Theme.line
                                    clip: true

                                    ScreencopyView {
                                        id: shot
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        captureSource: ov.visible ? win.modelData.wayland : null
                                        live: true
                                    }
                                    Text {      // until the first frame arrives (or if capture isn't possible)
                                        visible: !shot.hasContent
                                        anchors { fill: parent; margins: 4 }
                                        text: win.modelData.title
                                        wrapMode: Text.Wrap
                                        elide: Text.ElideRight
                                        color: Theme.faint
                                        font { family: Theme.font; pixelSize: 10 }
                                    }
                                    MouseArea { id: winTap; anchors.fill: parent; hoverEnabled: true; onClicked: ov.focusWindow(win.modelData) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
