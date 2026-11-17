// Small pure helpers for the screenshot editor (Shot*.qml) and the share picker
// (SharePick.qml). No QML types here, so tests/shot can call them with made-up data.
.pragma library

// Nerd Font glyphs (Material Design range), by code point.
function glyph(cp) { return String.fromCodePoint(cp) }
var G = {
    pen: 0xF03EB, marker: 0xF0E31, line: 0xF055E, arrow: 0xF005C, box: 0xF0763, ellipse: 0xF0EA1,
    text: 0xF0284, step: 0xF0CA0, pixel: 0xF013A, crop: 0xF019E,
    undo: 0xF054C, copy: 0xF018F, save: 0xF0193, close: 0xF0156,
    check: 0xF012C, unchecked: 0xF0131, checked: 0xF0132, monitor: 0xF0379, window: 0xF05AF, region: 0xF0A6D
}

// The windows on `screenName`'s visible workspace, in that screen's own coordinates.
// toplevels: HyprlandToplevel-like objects ({ title, workspace: { active }, monitor: { name },
// lastIpcObject: { at: [x, y], size: [w, h], floating } }); sx, sy: the screen's layout position.
function windowRects(toplevels, screenName, sx, sy) {
    const out = []
    for (const t of toplevels) {
        const o = t.lastIpcObject || {}
        if (!t.workspace || !t.workspace.active || !t.monitor || t.monitor.name !== screenName) continue
        if (!o.at || !o.size || o.hidden || o.mapped === false) continue
        out.push({ x: o.at[0] - sx, y: o.at[1] - sy, w: o.size[0], h: o.size[1], title: t.title || "", floating: !!o.floating })
    }
    return out
}

// The window under (px, py): a floating one wins (it is drawn on top), then the smallest.
function windowAt(rects, px, py) {
    let best = null
    for (const r of rects) {
        if (px < r.x || py < r.y || px >= r.x + r.w || py >= r.y + r.h) continue
        if (!best || (r.floating && !best.floating) || (r.floating === best.floating && r.w * r.h < best.w * best.h)) best = r
    }
    return best
}

// Same file name as ~/.local/bin/screenshot: $(date +%Y-%m-%d_%H-%M-%S).png
function stamp(d) {
    const p = n => (n < 10 ? "0" : "") + n
    return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) + "_" + p(d.getHours()) + "-" + p(d.getMinutes()) + "-" + p(d.getSeconds())
}

// A rectangle from two corners, kept inside 0..bw x 0..bh.
function spanRect(x0, y0, x1, y1, bw, bh) {
    const cx = v => Math.max(0, Math.min(bw, v)), cy = v => Math.max(0, Math.min(bh, v))
    const a = cx(Math.min(x0, x1)), b = cy(Math.min(y0, y1))
    return { x: a, y: b, w: cx(Math.max(x0, x1)) - a, h: cy(Math.max(y0, y1)) - b }
}

// Perceived lightness 0..1 of a QML color (for text on a fill of that colour).
function lum(c) { return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }

// ---- share picker ----
// The line xdg-desktop-portal-hyprland 1.5.0 reads back (src/shared/ScreencopyShared.cpp,
// parsePickerSelection; hyprland-share-picker/PickerData.cpp formatSelection):
//   [SELECTION]<flags>/screen:<output name>
//   [SELECTION]<flags>/window:<handle, the low 32 bits, decimal, from XDPH_WINDOW_SHARING_LIST>
//   [SELECTION]<flags>/region:<output>@<x>,<y>,<w>,<h>     (logical px, relative to the output)
//   [SELECTION]<flags>/workspace-id:<tracker id>
// flags: "r" = allow a restore token, "" = not.
function replyFor(sel, allowToken) {
    const head = "[SELECTION]" + (allowToken ? "r" : "") + "/"
    if (!sel) return ""
    if (sel.type === "screen" && sel.output) return head + "screen:" + sel.output
    if (sel.type === "window" && sel.id > 0) return head + "window:" + sel.id
    if (sel.type === "workspace" && sel.id > 0) return head + "workspace-id:" + sel.id
    if (sel.type === "region" && sel.output && sel.w >= 1 && sel.h >= 1)
        return head + "region:" + sel.output + "@" + Math.max(0, Math.round(sel.x)) + "," + Math.max(0, Math.round(sel.y)) + ","
               + Math.max(1, Math.round(sel.w)) + "," + Math.max(1, Math.round(sel.h))
    return ""
}
