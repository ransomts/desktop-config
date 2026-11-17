// Ink: vector strokes drawn with the mouse over whatever is under it. Used by the
// lecture draw overlay (LectureDraw.qml) and the screenshot editor.
//
//   tool         pen | marker (wide, translucent) | line | arrow | box | ellipse
//   ink, weight  colour and width (px) of the next stroke; a marker is drawn 3x as wide
//   interactive  false: shows the strokes but ignores the mouse
//   strokes      [{tool, ink, weight, points:[{x,y},...]}]; reassign to change (undoable)
//   undo() redo() clear() add(stroke), signal edited() after any change
// Shapes use points[0] and the last point; Shift while dragging makes lines and
// arrows snap to 45 degrees and boxes and ellipses square / round.
//
// Two canvases: `base` repaints all strokes, only when the list changes; `live` holds
// just the stroke being drawn, so a long drawing costs nothing extra per mouse move.
import QtQuick

Item {
    id: root
    anchors.fill: parent

    property string tool: "pen"
    property color ink: Theme.accentBg
    property real weight: 4
    property bool interactive: true
    property var strokes: []
    readonly property int count: strokes.length
    readonly property bool canRedo: future.length > 0
    readonly property bool canUndo: past.length > 0
    readonly property bool drawing: current !== null
    signal edited()

    property var past: []           // earlier stroke lists, newest last
    property var future: []         // undone lists, newest last
    property var known: []          // the list last seen, so an outside reassignment can be undone
    property bool internal: false
    property var current: null      // the stroke under the mouse now
    readonly property int historyMax: 200
    readonly property var shapes: ["line", "arrow", "box", "ellipse"]

    onStrokesChanged: {
        if (!internal && strokes !== known) {        // reassigned from outside: one undoable step
            past = past.concat([known]).slice(-historyMax)
            future = []
        }
        known = strokes
        base.requestPaint()
        if (!internal) edited()
    }
    function setList(next) { internal = true; strokes = next; internal = false; edited() }
    function commit(next) {
        past = past.concat([strokes]).slice(-historyMax)
        future = []
        setList(next)
    }
    function add(s) {
        if (!s || !s.points || !s.points.length) return
        commit(strokes.concat([{ tool: s.tool || "pen", ink: String(s.ink || ink), weight: Number(s.weight || weight),
                                 points: s.points.map(p => ({ x: Number(p.x), y: Number(p.y) })) }]))
    }
    function undo() {
        if (!past.length) return
        future = future.concat([strokes])
        const prev = past[past.length - 1]
        past = past.slice(0, -1)
        setList(prev)
    }
    function redo() {
        if (!future.length) return
        past = past.concat([strokes])
        const next = future[future.length - 1]
        future = future.slice(0, -1)
        setList(next)
    }
    function clear() { if (strokes.length) commit([]) }

    // Shift: 45-degree steps for lines and arrows, square / circle for boxes and ellipses
    function constrain(kind, a, b) {
        const dx = b.x - a.x, dy = b.y - a.y
        if (kind === "box" || kind === "ellipse") {
            const s = Math.max(Math.abs(dx), Math.abs(dy))
            return { x: a.x + (dx < 0 ? -s : s), y: a.y + (dy < 0 ? -s : s) }
        }
        const len = Math.hypot(dx, dy), step = Math.PI / 4
        const ang = Math.round(Math.atan2(dy, dx) / step) * step
        return { x: a.x + Math.round(len * Math.cos(ang) * 100) / 100, y: a.y + Math.round(len * Math.sin(ang) * 100) / 100 }
    }

    function paintStroke(ctx, s) {
        const p = s.points
        if (!p || !p.length) return
        const marker = s.tool === "marker"
        const w = marker ? s.weight * 3 : s.weight
        ctx.save()
        ctx.strokeStyle = s.ink
        ctx.fillStyle = s.ink
        ctx.globalAlpha = marker ? 0.38 : 1
        ctx.lineWidth = w
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        const a = p[0], b = p[p.length - 1]
        ctx.beginPath()
        if (s.tool === "pen" || marker) {
            if (p.length === 1) {
                ctx.arc(a.x, a.y, w / 2, 0, 2 * Math.PI)
                ctx.fill()
                ctx.restore()
                return
            }
            ctx.moveTo(a.x, a.y)
            for (let i = 1; i < p.length - 1; i++)       // through the midpoints: smooth, no corners
                ctx.quadraticCurveTo(p[i].x, p[i].y, (p[i].x + p[i + 1].x) / 2, (p[i].y + p[i + 1].y) / 2)
            ctx.lineTo(b.x, b.y)
            ctx.stroke()
        } else if (s.tool === "line") {
            ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke()
        } else if (s.tool === "arrow") {
            const len = Math.hypot(b.x - a.x, b.y - a.y)
            const head = Math.min(len * 0.6, Math.max(14, w * 4))
            const ang = Math.atan2(b.y - a.y, b.x - a.x), spread = 0.45
            const bx = b.x - Math.cos(ang) * head * 0.8, by = b.y - Math.sin(ang) * head * 0.8
            ctx.moveTo(a.x, a.y); ctx.lineTo(bx, by); ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(b.x, b.y)
            ctx.lineTo(b.x - Math.cos(ang - spread) * head, b.y - Math.sin(ang - spread) * head)
            ctx.lineTo(b.x - Math.cos(ang + spread) * head, b.y - Math.sin(ang + spread) * head)
            ctx.closePath()
            ctx.lineWidth = Math.max(1, w / 2)
            ctx.fill(); ctx.stroke()
        } else if (s.tool === "box") {
            ctx.rect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y))
            ctx.stroke()
        } else if (s.tool === "ellipse") {
            ctx.ellipse(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y))
            ctx.stroke()
        }
        ctx.restore()
    }

    Canvas {
        id: base
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            for (const s of root.strokes) root.paintStroke(ctx, s)
        }
    }
    Canvas {
        id: live
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (root.current) root.paintStroke(ctx, root.current)
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton
        cursorShape: root.interactive ? Qt.CrossCursor : Qt.ArrowCursor
        preventStealing: true
        onPressed: mouse => {
            const p = { x: mouse.x, y: mouse.y }
            root.current = { tool: root.tool, ink: String(root.ink), weight: root.weight,
                             points: root.shapes.indexOf(root.tool) >= 0 ? [p, { x: p.x, y: p.y }] : [p] }
            live.requestPaint()
        }
        onPositionChanged: mouse => {
            const s = root.current
            if (!s) return
            const pts = s.points
            if (root.shapes.indexOf(s.tool) >= 0) {
                const end = { x: mouse.x, y: mouse.y }
                pts[pts.length - 1] = (mouse.modifiers & Qt.ShiftModifier) ? root.constrain(s.tool, pts[0], end) : end
            } else {
                const last = pts[pts.length - 1]
                if (Math.hypot(mouse.x - last.x, mouse.y - last.y) < 1.5) return
                pts.push({ x: mouse.x, y: mouse.y })
            }
            live.requestPaint()
        }
        onReleased: {
            const s = root.current
            root.current = null
            live.requestPaint()
            if (!s) return
            const a = s.points[0], b = s.points[s.points.length - 1]
            if (root.shapes.indexOf(s.tool) >= 0 && Math.hypot(b.x - a.x, b.y - a.y) < 3) return   // a click, not a shape
            root.add(s)
        }
        onCanceled: { root.current = null; live.requestPaint() }
    }
}
