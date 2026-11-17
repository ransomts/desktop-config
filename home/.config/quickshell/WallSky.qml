// The real sky over a place (lat/lng), right now: the Yale
// bright stars, constellation figures, the Milky Way, planets and the moon with its true
// phase and tilt, facing south, in the same projection as the new-tab page (sky.js).
// One sky spans the whole monitor layout; each screen draws its own window onto it.
// Redrawn every 20 s while the wallpaper is moving and every 5 min on battery: the sky
// turns a quarter of a degree a minute. The backdrop is shaders/skybg.frag.
// Everything it needs comes in as properties (Wallpaper.qml passes WallState's), so the lock
// screen, a separate Quickshell instance that must not load WallState, can draw it too.
import QtQuick
import "sky.js" as Sky

Item {
    id: sky
    property point origin
    property bool dark: true

    // frame: the horizon sits 8% above the bottom of the layout; the top of the layout is
    // about 80 degrees up, and the width takes whatever azimuth fits (to 120 degrees each side)
    property rect box: Qt.rect(0, 0, 1920, 1080)    // the whole monitor layout
    property real sunAlt: -30               // degrees
    property real lat: 0
    property real lng: 0
    property var when: null                 // a Date to draw the sky of; null: now
    property bool live: true                // false: no redraw timer (test frames, the lock screen)
    property bool moving: false
    function sstep(a, b, x) { const t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t) }
    readonly property real horizonY: box.y + box.height * 0.92
    readonly property real scale0: Math.max((box.height * 0.92) / 1.7, box.width / 2 / (2 * Math.tan(Math.PI / 3)))
    readonly property real cx: box.x + box.width / 2

    // how much of the night shows: real darkness, but dark mode always shows the stars
    readonly property real night: Math.max(sstep(-3, -12, sunAlt), dark ? 0.75 : 0)
    onNightChanged: canvas.requestPaint()
    onVisibleChanged: if (visible) canvas.requestPaint()
    onBoxChanged: canvas.requestPaint()

    Timer {
        interval: sky.moving ? 20000 : 300000
        running: sky.visible && sky.live; repeat: true
        onTriggered: canvas.requestPaint()
    }
    onWhenChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!sky.visible) return
            const DEG = Sky.deg(), date = sky.when || new Date()
            const lat = sky.lat * DEG, lst = Sky.localSiderealDeg(date, sky.lng)
            const W = width, H = height, night = sky.night
            const place = (ra, dec) => {
                const h = Sky.toAltAz(ra, dec, lst, lat)
                if (h.alt < -0.02) return null
                const p = Sky.projectSky(h.alt, h.az)
                return { x: sky.cx + p.x * sky.scale0 - sky.origin.x, y: sky.horizonY - p.y * sky.scale0 - sky.origin.y, k: p.k, alt: h.alt }
            }
            const seen = p => p && p.x > -40 && p.x < W + 40 && p.y > -40 && p.y < H + 40
            const low = p => Math.min(1, p.alt / (5 * DEG))          // dimming into the horizon haze

            if (night > 0.02) {
                // Milky Way: soft blobs along the galactic plane
                for (const b of Sky.milkyWay()) {
                    const p = place(b.ra, b.dec)
                    if (!p) continue
                    const r = b.radiusDeg * DEG * sky.scale0 * p.k * 0.5
                    if (p.x < -r || p.x > W + r || p.y < -r || p.y > H + r) continue
                    const g = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, r)
                    g.addColorStop(0, Qt.rgba(0.80, 0.78, 0.95, 0.050 * b.intensity * night * low(p)))
                    g.addColorStop(1, Qt.rgba(0.80, 0.78, 0.95, 0))
                    ctx.fillStyle = g
                    ctx.fillRect(p.x - r, p.y - r, 2 * r, 2 * r)
                }
                // constellation figures
                ctx.lineWidth = 1
                ctx.strokeStyle = Qt.rgba(0.80, 0.74, 0.95, 0.13 * night)
                ctx.beginPath()
                for (const f of Sky.figures()) for (const line of f.lines) {
                    let prev = null
                    for (const v of line) {
                        const p = place(v.ra, v.dec)
                        if (p && prev && (seen(p) || seen(prev)) && Math.abs(p.x - prev.x) < W) { ctx.moveTo(prev.x, prev.y); ctx.lineTo(p.x, p.y) }
                        prev = p
                    }
                }
                ctx.stroke()
                // stars, brightest first
                for (const s of Sky.stars()) {
                    const p = place(s.ra, s.dec)
                    if (!seen(p)) continue
                    const a = Math.max(0, Math.min(1, 1.08 - s.mag * 0.15)) * night * low(p)
                    if (a < 0.03) continue
                    const r = Math.max(0.55, 2.7 - 0.42 * s.mag)
                    const col = Qt.color(Sky.starColor(s.bv))
                    if (s.mag < 1.6) {
                        const g = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, r * 4.5)
                        g.addColorStop(0, Qt.rgba(col.r, col.g, col.b, 0.30 * a)); g.addColorStop(1, Qt.rgba(col.r, col.g, col.b, 0))
                        ctx.fillStyle = g; ctx.fillRect(p.x - r * 5, p.y - r * 5, r * 10, r * 10)
                    }
                    ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, a)
                    ctx.beginPath(); ctx.arc(p.x, p.y, r, 0, 2 * Math.PI); ctx.fill()
                }
                // planets, with their names
                ctx.font = "11px '" + Theme.font + "'"
                for (const pl of Sky.planetStates(date)) {
                    const p = place(pl.ra, pl.dec)
                    if (!seen(p)) continue
                    const r = Math.max(1.6, 3.0 - 0.35 * pl.mag), col = Qt.color(pl.color), a = night * low(p)
                    const g = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, r * 4)
                    g.addColorStop(0, Qt.rgba(col.r, col.g, col.b, 0.35 * a)); g.addColorStop(1, Qt.rgba(col.r, col.g, col.b, 0))
                    ctx.fillStyle = g; ctx.fillRect(p.x - r * 4, p.y - r * 4, r * 8, r * 8)
                    ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, a)
                    ctx.beginPath(); ctx.arc(p.x, p.y, r, 0, 2 * Math.PI); ctx.fill()
                    ctx.fillStyle = Qt.rgba(0.90, 0.88, 0.86, 0.45 * a)
                    ctx.fillText(pl.name, p.x + r + 5, p.y + 4)
                }
            }

            // the sun, by day in light mode
            const sun = Sky.sunState(date), sp = place(sun.raDeg, sun.decDeg)
            if (sp && night < 0.6 && seen(sp)) {
                const g = ctx.createRadialGradient(sp.x, sp.y, 0, sp.x, sp.y, 120)
                g.addColorStop(0, Qt.rgba(1, 0.86, 0.62, 0.95 * (1 - night))); g.addColorStop(0.12, Qt.rgba(1, 0.74, 0.42, 0.55 * (1 - night)))
                g.addColorStop(1, Qt.rgba(1, 0.56, 0.18, 0))
                ctx.fillStyle = g; ctx.fillRect(sp.x - 120, sp.y - 120, 240, 240)
            }

            // the moon: three times true size so the phase reads; lit side turned toward the sun
            const moon = Sky.moonState(date), mp = place(moon.raDeg, moon.decDeg)
            if (seen(mp)) {
                const R = Math.max(9, 0.26 * DEG * sky.scale0 * mp.k * 3)
                const t = Sky.towardSun(date, moon), tp0 = Sky.toAltAz(t.raDeg, t.decDeg, lst, lat), tp = Sky.projectSky(tp0.alt, tp0.az)
                const tx = sky.cx + tp.x * sky.scale0 - sky.origin.x, ty = sky.horizonY - tp.y * sky.scale0 - sky.origin.y
                const bearing = Math.atan2(ty - mp.y, tx - mp.x)
                const k = Math.cos(2 * Math.PI * moon.phase)       // +1 new .. -1 full
                const vis = Math.max(night, 0.35) * low(mp)
                const halo = ctx.createRadialGradient(mp.x, mp.y, R, mp.x, mp.y, R * 5)
                halo.addColorStop(0, Qt.rgba(0.93, 0.90, 0.84, 0.16 * vis * (1 - k) / 2)); halo.addColorStop(1, Qt.rgba(0.93, 0.90, 0.84, 0))
                ctx.fillStyle = halo; ctx.fillRect(mp.x - R * 5, mp.y - R * 5, R * 10, R * 10)
                ctx.save(); ctx.translate(mp.x, mp.y); ctx.rotate(bearing)
                ctx.fillStyle = Qt.rgba(0.30, 0.28, 0.36, 0.55 * vis)         // the unlit disc, earthshine
                ctx.beginPath(); ctx.arc(0, 0, R, 0, 2 * Math.PI); ctx.fill()
                ctx.fillStyle = Qt.rgba(0.95, 0.92, 0.86, vis)
                ctx.beginPath(); ctx.arc(0, 0, R, -Math.PI / 2, Math.PI / 2)  // the limb facing the sun
                ctx.save(); ctx.scale(Math.max(0.001, Math.abs(k)), 1)        // the terminator, an ellipse
                ctx.arc(0, 0, R, Math.PI / 2, -Math.PI / 2, k > 0)            // crescent: back the same side; gibbous: the far side
                ctx.restore(); ctx.closePath(); ctx.fill()
                ctx.restore()
            }
        }
    }
}
