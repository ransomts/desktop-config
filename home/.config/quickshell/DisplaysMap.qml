// The screens of Settings > Displays as rectangles in proportion (logical pixels), to drag.
// `mons`: [{ label, name, x, y, w, h, focused, primary, transform, sub }]. A drag snaps to the
// neighbours' edges as it goes (displays.js snap) and lands where nothing overlaps and every
// screen still touches another (settle); then moved(i, x, y). Click: picked(i).
// The view's scale is fixed while a drag runs, so the map holds still under the pointer.
import QtQuick
import "displays.js" as Geo

Item {
    id: map
    property var mons: []
    property int sel: 0
    property bool locked: false                 // one screen, or a trial running: nothing to drag
    property real snapPx: 14                    // on screen, whatever the zoom
    signal picked(int i)
    signal moved(int i, real x, real y)

    implicitWidth: 520
    implicitHeight: 250
    readonly property var rects: mons.map(m => ({ x: m.x, y: m.y, w: m.w, h: m.h }))

    // view: logical -> map pixels; frozen during a drag
    property int dragging: -1
    property var frozen: null
    readonly property var box: dragging >= 0 && frozen ? frozen : Geo.bbox(rects)
    readonly property real pad: 18
    readonly property real k: Math.min((width - 2 * pad) / box.w, (height - 2 * pad) / box.h)
    readonly property real ox: (width - box.w * k) / 2 - box.x * k
    readonly property real oy: (height - box.h * k) / 2 - box.y * k

    property real dragX: 0                      // logical, where the dragged one is now
    property real dragY: 0
    readonly property bool dragBad: dragging >= 0 && !Geo.valid(Geo.moved(rects, dragging, dragX, dragY))

    function nudge(dx, dy) {
        if (locked || sel < 0 || sel >= rects.length) return
        const r = rects[sel]
        const p = Geo.settle(rects, sel, r.x + dx, r.y + dy)
        if (p.x !== r.x || p.y !== r.y) moved(sel, p.x, p.y)
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Theme.tint(Theme.fg, Theme.dark ? 0.04 : 0.05)
        border.width: 1
        border.color: Theme.line
    }

    Repeater {
        model: map.mons.length
        Rectangle {
            id: scr
            required property int index
            readonly property var m: map.mons[index] || ({})
            readonly property bool held: map.dragging === index
            readonly property bool picked: map.sel === index
            readonly property real lx: held ? map.dragX : m.x
            readonly property real ly: held ? map.dragY : m.y
            x: map.ox + lx * map.k + 1
            y: map.oy + ly * map.k + 1
            width: Math.max(8, m.w * map.k - 2)
            height: Math.max(8, m.h * map.k - 2)
            z: held ? 2 : picked ? 1 : 0
            radius: 5
            color: picked ? Theme.tint(Theme.accentBg, Theme.dark ? 0.18 : 0.16) : Theme.tint(Theme.fg, Theme.dark ? 0.10 : 0.08)
            border.width: picked || (held && map.dragBad) ? 2 : 1
            border.color: held && map.dragBad ? Theme.red : picked ? Theme.accentBg : Theme.tint(Theme.fg, 0.35)
            opacity: held ? 0.9 : 1

            // which edge is the picture's top: a short bar on that side (rotated screens)
            Rectangle {
                readonly property int t: (scr.m.transform || 0) % 4
                visible: t !== 0
                color: Theme.accentBg
                radius: 1.5
                width: t === 2 ? scr.width * 0.3 : 3
                height: t === 2 ? 3 : scr.height * 0.3
                x: t === 2 ? (scr.width - width) / 2 : t === 1 ? 3 : scr.width - width - 3
                y: t === 2 ? scr.height - height - 3 : (scr.height - height) / 2
            }
            Column {
                anchors.centerIn: parent
                width: parent.width - 10
                spacing: 1
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere      // a portrait tile is narrow but tall
                    maximumLineCount: 2
                    text: (scr.m.primary ? "★ " : "") + (scr.m.label || "")
                    color: Theme.fg
                    font { family: Theme.font; pixelSize: scr.width < 90 ? 10 : 12; bold: true }
                }
                Text {
                    width: parent.width
                    visible: scr.height > 44
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    maximumLineCount: 3
                    text: scr.m.sub || ""
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 10 }
                }
            }
            Rectangle {                         // the focused screen: where the settings window is
                visible: scr.m.focused === true
                anchors { top: parent.top; right: parent.right; margins: 6 }
                width: 7; height: 7; radius: 3.5
                color: Theme.ok
            }
            MouseArea {
                id: grab
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: map.locked ? Qt.PointingHandCursor : held ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real offX: 0
                property real offY: 0
                property bool moving: false
                onPressed: mouse => {
                    map.picked(scr.index)
                    if (map.locked) return
                    const p = mapToItem(map, mouse.x, mouse.y)
                    offX = (p.x - map.ox) / map.k - scr.m.x
                    offY = (p.y - map.oy) / map.k - scr.m.y
                    moving = false
                    map.frozen = map.box
                    map.dragX = scr.m.x; map.dragY = scr.m.y
                    map.dragging = scr.index
                }
                onPositionChanged: mouse => {
                    if (map.dragging !== scr.index) return
                    const p = mapToItem(map, mouse.x, mouse.y)
                    const lx = (p.x - map.ox) / map.k - offX, ly = (p.y - map.oy) / map.k - offY
                    if (!moving && Math.hypot(lx - scr.m.x, ly - scr.m.y) * map.k < 3) return
                    moving = true
                    const s = Geo.snap(map.rects, scr.index, lx, ly, map.snapPx / map.k)
                    map.dragX = s.x; map.dragY = s.y
                }
                onReleased: {
                    if (map.dragging !== scr.index) return
                    const i = scr.index
                    const p = moving ? Geo.settle(map.rects, i, map.dragX, map.dragY) : { x: scr.m.x, y: scr.m.y }
                    map.dragging = -1
                    map.frozen = null
                    if (p.x !== scr.m.x || p.y !== scr.m.y) map.moved(i, p.x, p.y)
                }
                onCanceled: { map.dragging = -1; map.frozen = null }
            }
        }
    }
}
