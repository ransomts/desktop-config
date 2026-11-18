// Test stand-in for the lecture feature's Ink.qml, written to the interface in the round's
// RULES.md only (tests/shot uses it; the real Ink.qml replaces it in the shell).
import QtQuick

Item {
    id: ink
    property string tool: "pen"
    property color ink: Theme.accentBg
    property real weight: 4
    property bool interactive: true
    property var strokes: []
    readonly property int count: strokes.length
    property var undone: []
    readonly property bool canRedo: undone.length > 0
    signal edited()

    function undo() { if (!strokes.length) return; undone = undone.concat([strokes[strokes.length - 1]]); strokes = strokes.slice(0, -1); edited() }
    function redo() { if (!undone.length) return; strokes = strokes.concat([undone[undone.length - 1]]); undone = undone.slice(0, -1); edited() }
    function clear() { strokes = []; edited() }
    function add(s) { strokes = strokes.concat([s]); undone = []; edited() }
    onStrokesChanged: canvas.requestPaint()

    property var live: null
    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const c = getContext("2d")
            c.reset()
            const all = ink.live ? ink.strokes.concat([ink.live]) : ink.strokes
            for (const s of all) {
                const p = s.points
                if (!p.length) continue
                c.strokeStyle = s.ink
                c.globalAlpha = s.tool === "marker" ? 0.4 : 1
                c.lineWidth = s.tool === "marker" ? s.weight * 4 : s.weight
                c.lineCap = "round"; c.lineJoin = "round"
                c.beginPath()
                const a = p[0], b = p[p.length - 1]
                if (s.tool === "box") c.rect(a.x, a.y, b.x - a.x, b.y - a.y)
                else if (s.tool === "ellipse") c.ellipse(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y))
                else if (s.tool === "line" || s.tool === "arrow") {
                    c.moveTo(a.x, a.y); c.lineTo(b.x, b.y)
                    if (s.tool === "arrow") {
                        const t = Math.atan2(b.y - a.y, b.x - a.x), h = 6 + s.weight * 3
                        c.moveTo(b.x, b.y); c.lineTo(b.x - h * Math.cos(t - 0.5), b.y - h * Math.sin(t - 0.5))
                        c.moveTo(b.x, b.y); c.lineTo(b.x - h * Math.cos(t + 0.5), b.y - h * Math.sin(t + 0.5))
                    }
                } else { c.moveTo(a.x, a.y); for (const q of p) c.lineTo(q.x, q.y) }
                c.stroke()
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        enabled: ink.interactive
        onPressed: mouse => { ink.live = { tool: ink.tool, ink: String(ink.ink), weight: ink.weight, points: [{ x: mouse.x, y: mouse.y }] } }
        onPositionChanged: mouse => { if (ink.live) { ink.live.points.push({ x: mouse.x, y: mouse.y }); canvas.requestPaint() } }
        onReleased: mouse => { const s = ink.live; ink.live = null; if (s) { s.points.push({ x: mouse.x, y: mouse.y }); ink.add(s) } }
    }
}
