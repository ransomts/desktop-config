// A box dragged out over a still frame: dims everything else, shows the size, and has
// eight handles to adjust it afterwards. Used by the screenshot editor (ShotEditor.qml)
// and by the share picker's Region tab (SharePick.qml). Fills its parent; the box is in
// the parent's coordinates.
import QtQuick
import "shot.js" as S

Item {
    id: sel
    property real sx: 0
    property real sy: 0
    property real sw: 0
    property real sh: 0
    readonly property bool has: sw >= 2 && sh >= 2
    property bool drawing: true         // a drag on empty space draws a new box
    property bool adjustable: true      // the handles are shown and work
    property bool movable: false        // a drag inside the box moves it
    property real unit: 1               // the size readout is in these (device pixels per px)
    property bool readout: true
    readonly property alias pointerX: area.mouseX
    readonly property alias pointerY: area.mouseY
    readonly property alias hovered: area.containsMouse
    readonly property bool busy: area.pressed || grips.busy
    signal started()                    // a new box was begun
    signal committed()                  // a drag ended with a box
    signal doubleClicked()

    function set(x, y, w, h) {
        const r = S.spanRect(x, y, x + w, y + h, width, height)
        sx = r.x; sy = r.y; sw = r.w; sh = r.h
    }
    function clear() { sx = 0; sy = 0; sw = 0; sh = 0 }

    // dim around the box (the whole frame while there is none)
    readonly property color shade: Theme.tint(Theme.solidBg, 0.55)
    Rectangle { color: sel.shade; x: 0; y: 0; width: parent.width; height: sel.has ? sel.sy : parent.height }
    Rectangle { visible: sel.has; color: sel.shade; x: 0; y: sel.sy + sel.sh; width: parent.width; height: parent.height - y }
    Rectangle { visible: sel.has; color: sel.shade; x: 0; y: sel.sy; width: sel.sx; height: sel.sh }
    Rectangle { visible: sel.has; color: sel.shade; x: sel.sx + sel.sw; y: sel.sy; width: parent.width - x; height: sel.sh }
    Rectangle {
        visible: sel.has
        x: sel.sx - 1; y: sel.sy - 1; width: sel.sw + 2; height: sel.sh + 2
        color: "transparent"
        border.width: 2
        border.color: Theme.accentBg
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: sel.drawing || sel.movable
        hoverEnabled: sel.drawing
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        cursorShape: sel.movable && !sel.drawing ? Qt.SizeAllCursor : Qt.CrossCursor
        property real x0: 0
        property real y0: 0
        property var start: null
        property bool moving: false
        property bool fresh: false
        onPressed: mouse => {
            x0 = mouse.x; y0 = mouse.y
            start = { x: sel.sx, y: sel.sy, w: sel.sw, h: sel.sh }
            moving = sel.movable && sel.has && mouse.x >= sel.sx && mouse.x <= sel.sx + sel.sw && mouse.y >= sel.sy && mouse.y <= sel.sy + sel.sh
            fresh = false
        }
        onPositionChanged: mouse => {
            if (!pressed) return
            if (moving) {
                const nx = Math.max(0, Math.min(sel.width - start.w, start.x + mouse.x - x0))
                const ny = Math.max(0, Math.min(sel.height - start.h, start.y + mouse.y - y0))
                sel.sx = nx; sel.sy = ny
                return
            }
            if (!sel.drawing) return
            if (!fresh && Math.abs(mouse.x - x0) + Math.abs(mouse.y - y0) < 3) return
            if (!fresh) { fresh = true; sel.started() }
            const r = S.spanRect(x0, y0, mouse.x, mouse.y, sel.width, sel.height)
            sel.sx = r.x; sel.sy = r.y; sel.sw = r.w; sel.sh = r.h
        }
        onReleased: if (fresh && sel.has) sel.committed()
        onDoubleClicked: sel.doubleClicked()
    }

    // the eight handles: corners and edge middles; which edges each one moves
    Item {
        id: grips
        anchors.fill: parent
        visible: sel.adjustable && sel.has
        property bool busy: false
        Repeater {
            model: [ [1, 1, 0, 0], [0, 1, 0, 0], [0, 1, 1, 0], [0, 0, 1, 0], [0, 0, 1, 1], [0, 0, 0, 1], [1, 0, 0, 1], [1, 0, 0, 0] ]
            Rectangle {
                id: grip
                required property var modelData        // moves [left, top, right, bottom]
                readonly property real gx: modelData[0] ? sel.sx : modelData[2] ? sel.sx + sel.sw : sel.sx + sel.sw / 2
                readonly property real gy: modelData[1] ? sel.sy : modelData[3] ? sel.sy + sel.sh : sel.sy + sel.sh / 2
                x: gx - 6; y: gy - 6; width: 12; height: 12; radius: 3
                color: Theme.accentBg
                border.width: 1
                border.color: Theme.accentInk
                MouseArea {
                    anchors { fill: parent; margins: -5 }
                    preventStealing: true
                    cursorShape: (grip.modelData[0] || grip.modelData[2]) && (grip.modelData[1] || grip.modelData[3])
                        ? ((grip.modelData[0] === grip.modelData[1]) ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor)
                        : (grip.modelData[0] || grip.modelData[2]) ? Qt.SizeHorCursor : Qt.SizeVerCursor
                    property var start: null
                    onPressed: { start = { l: sel.sx, t: sel.sy, r: sel.sx + sel.sw, b: sel.sy + sel.sh }; grips.busy = true }
                    onReleased: grips.busy = false
                    onPositionChanged: mouse => {
                        if (!pressed) return
                        const p = mapToItem(sel, mouse.x, mouse.y)
                        const m = grip.modelData
                        let l = start.l, t = start.t, r = start.r, b = start.b
                        if (m[0]) l = p.x; if (m[2]) r = p.x
                        if (m[1]) t = p.y; if (m[3]) b = p.y
                        const q = S.spanRect(l, t, r, b, sel.width, sel.height)
                        sel.sx = q.x; sel.sy = q.y; sel.sw = Math.max(2, q.w); sel.sh = Math.max(2, q.h)
                    }
                }
            }
        }
    }

    // size readout, above the box (inside it when there is no room)
    Rectangle {
        visible: sel.readout && sel.has
        x: Math.min(sel.width - width, sel.sx)
        y: sel.sy >= height + 6 ? sel.sy - height - 6 : sel.sy + 6
        width: size.implicitWidth + 14; height: size.implicitHeight + 6; radius: 6
        color: Theme.solidBg
        border.width: 1
        border.color: Theme.line
        Text {
            id: size
            anchors.centerIn: parent
            text: Math.round(sel.sw * sel.unit) + " × " + Math.round(sel.sh * sel.unit)
            color: Theme.fg
            font { family: Theme.font; pixelSize: 12 }
        }
    }
}
