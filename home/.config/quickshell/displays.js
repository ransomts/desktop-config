// Geometry for Settings > Displays (SettingsDisplays.qml, DisplaysMap.qml): rectangles in
// Hyprland's logical pixels, {x, y, w, h}. No monitor knowledge here (modes, scales, what may
// change): ~/.local/bin/display-layout has that, and checks the result again before applying.
.pragma library

const MIN_TOUCH = 64            // shared edge the pointer can cross comfortably

function overlaps(a, b) {
    return Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x) > 0
        && Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y) > 0
}

// length of the edge two rectangles share (0 for a corner or a gap)
function touch(a, b) {
    if (a.x + a.w === b.x || b.x + b.w === a.x) return Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y))
    if (a.y + a.h === b.y || b.y + b.h === a.y) return Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x))
    return 0
}

function connected(rs) {
    if (rs.length < 2) return true
    const seen = [0], todo = [0]
    while (todo.length) {
        const i = todo.pop()
        for (let j = 0; j < rs.length; j++)
            if (seen.indexOf(j) < 0 && touch(rs[i], rs[j]) > 0) { seen.push(j); todo.push(j) }
    }
    return seen.length === rs.length
}

function anyOverlap(rs) {
    for (let i = 0; i < rs.length; i++)
        for (let j = i + 1; j < rs.length; j++)
            if (overlaps(rs[i], rs[j])) return true
    return false
}

function valid(rs) { return !anyOverlap(rs) && connected(rs) }

function bbox(rs) {
    if (!rs.length) return { x: 0, y: 0, w: 1, h: 1 }
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
    for (const r of rs) { x0 = Math.min(x0, r.x); y0 = Math.min(y0, r.y); x1 = Math.max(x1, r.x + r.w); y1 = Math.max(y1, r.y + r.h) }
    return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) }
}

function moved(rs, i, x, y) { return rs.map((r, k) => k === i ? { x: x, y: y, w: r.w, h: r.h } : r) }

// While dragging: pull rectangle i to a neighbour's edge (flush against it, or edges lined up)
// when it is within `thr` logical pixels. x and y snap on their own.
function snap(rs, i, x, y, thr) {
    const me = rs[i]
    let bx = x, by = y, dx = thr + 1, dy = thr + 1
    for (let j = 0; j < rs.length; j++) {
        if (j === i) continue
        const o = rs[j]
        for (const cx of [o.x - me.w, o.x + o.w, o.x, o.x + o.w - me.w]) if (Math.abs(cx - x) < dx) { dx = Math.abs(cx - x); bx = cx }
        for (const cy of [o.y, o.y + o.h - me.h, o.y - me.h, o.y + o.h, o.y + Math.round((o.h - me.h) / 2)]) if (Math.abs(cy - y) < dy) { dy = Math.abs(cy - y); by = cy }
    }
    return { x: Math.round(bx), y: Math.round(by) }
}

function clamp(v, lo, hi) { return lo > hi ? (lo + hi) / 2 : Math.max(lo, Math.min(hi, v)) }

// Where rectangle i may go nearest to (x, y): no overlaps, every screen reachable, sharing at
// least MIN_TOUCH px of edge (less only if a side is shorter). Its old place if nothing fits.
function settle(rs, i, x, y) {
    x = Math.round(x); y = Math.round(y)
    const me = rs[i]
    if (rs.length < 2) return { x: x, y: y }
    const ok = (cx, cy) => valid(moved(rs, i, cx, cy))
    function good(cx, cy) {
        if (!ok(cx, cy)) return false
        const r = { x: cx, y: cy, w: me.w, h: me.h }
        for (let j = 0; j < rs.length; j++) if (j !== i && touch(r, rs[j]) >= Math.min(MIN_TOUCH, me.w, me.h, rs[j].w, rs[j].h)) return true
        return false
    }
    if (good(x, y)) return { x: x, y: y }
    const cands = []
    for (let j = 0; j < rs.length; j++) {
        if (j === i) continue
        const o = rs[j]
        const t = Math.min(MIN_TOUCH, me.w, me.h, o.w, o.h)
        const ys = [clamp(y, o.y - me.h + t, o.y + o.h - t), o.y, o.y + o.h - me.h, o.y + Math.round((o.h - me.h) / 2)]
        const xs = [clamp(x, o.x - me.w + t, o.x + o.w - t), o.x, o.x + o.w - me.w, o.x + Math.round((o.w - me.w) / 2)]
        for (const cy of ys) { cands.push({ x: o.x - me.w, y: cy }); cands.push({ x: o.x + o.w, y: cy }) }
        for (const cx of xs) { cands.push({ x: cx, y: o.y - me.h }); cands.push({ x: cx, y: o.y + o.h }) }
    }
    let best = null, bd = Infinity
    for (const c of cands) {
        const cx = Math.round(c.x), cy = Math.round(c.y)
        const d = (cx - x) * (cx - x) + (cy - y) * (cy - y)
        if (d < bd && good(cx, cy)) { bd = d; best = { x: cx, y: cy } }
    }
    return best || { x: me.x, y: me.y }
}

// After rectangle i changed size (mode, scale, rotation): keep its top-left if that still
// works, else move it as little as possible; then pull back any screen it left stranded.
// Returns the new list.
function refit(rs, i) {
    let out = rs.slice()
    if (valid(out)) return out
    const p = settle(out, i, out[i].x, out[i].y)
    out = moved(out, i, p.x, p.y)
    for (let round = 0; round < out.length && !valid(out); round++) {
        for (let j = 0; j < out.length && !valid(out); j++) {
            if (j === i) continue
            const q = settle(out, j, out[j].x, out[j].y)
            out = moved(out, j, q.x, q.y)
        }
    }
    return out
}
