// What the spotlight shows on one screen (LectureSpot.qml): everything dimmed except a
// soft-edged circle at the pointer. No shader and no blur: a Canvas square with a radial
// gradient and four Rectangles. Screens without the pointer are just dimmed.
import QtQuick

Item {
    id: spot
    property real px: -1e5                  // pointer, in this item's coordinates
    property real py: -1e5
    property real radius: Lecture.spotRadius
    readonly property bool here: px >= 0 && py >= 0 && px < width && py < height
    readonly property real strength: 0.62   // how dark the dimmed part is
    readonly property real feather: Math.max(16, radius * 0.3)
    readonly property color dim: Qt.rgba(0, 0, 0, strength)
    readonly property int half: Math.ceil(radius + feather)          // half the hole square's side
    readonly property int cx: Math.round(px)
    readonly property int cy: Math.round(py)
    readonly property real holeRadius: radius                         // fully clear inside this (tests read it)

    Rectangle {                             // pointer elsewhere: dim the whole screen
        anchors.fill: parent
        visible: !spot.here
        color: spot.dim
    }
    // Around the pointer: one square Canvas holding the soft hole (a radial gradient, painted
    // again only when the radius changes; moving it is free). The rest of the screen: four
    // plain Rectangles on whole-pixel edges, so nothing overlaps and there are no seams.
    Item {
        anchors.fill: parent
        visible: spot.here
        Canvas {
            id: hole
            objectName: "hole"
            x: spot.cx - spot.half; y: spot.cy - spot.half
            width: 2 * spot.half; height: width
            onWidthChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d"), c = width / 2
                ctx.clearRect(0, 0, width, height)
                const g = ctx.createRadialGradient(c, c, spot.radius, c, c, c)
                for (let i = 0; i <= 8; i++) {               // smoothstep: no visible rim
                    const t = i / 8
                    g.addColorStop(t, Qt.rgba(0, 0, 0, spot.strength * t * t * (3 - 2 * t)))
                }
                ctx.fillStyle = g
                ctx.fillRect(0, 0, width, height)
            }
        }
        Rectangle { x: 0; y: 0; width: parent.width; height: Math.max(0, hole.y); color: spot.dim }
        Rectangle { x: 0; y: hole.y + hole.height; width: parent.width; height: Math.max(0, parent.height - y); color: spot.dim }
        Rectangle { x: 0; y: hole.y; width: Math.max(0, hole.x); height: hole.height; color: spot.dim }
        Rectangle { x: hole.x + hole.width; y: hole.y; width: Math.max(0, parent.width - x); height: hole.height; color: spot.dim }
    }
}
