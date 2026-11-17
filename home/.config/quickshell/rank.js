// Ranked search shared by the pick list (Picker.qml, qs-pick --rank) and the launcher's
// emoji mode (LaunchView.qml): results are ordered by how well they match instead of by
// their place in the list. A line is "name   keywords" (three spaces); rankWord lists the
// levels, and ties are settled as noted in ranked(). Also the table of other names people
// type for the same thing (alias), which the plain pick lists use too.
.pragma library
.import "fuzzy.js" as Fuzzy

// One line, ready for ranked(): `index` is its place in the list (ties keep that order).
function prep(label, index) {
    const lower = label.toLowerCase(), split = lower.indexOf("   ")
    return { label: label, index: index, lower: lower, plain: split === -1,
             nameToks: Fuzzy.tokens(split === -1 ? lower : lower.slice(0, split)),
             keyToks: split === -1 ? [] : Fuzzy.tokens(lower.slice(split)) }
}

function rankWord(w, it) {
    // 0 whole word of the name, 1 a whole keyword ("us" for a flag, "poop"), 2 start of a
    // name word, 3 inside a name word, 4 start of a keyword, 5 inside a keyword
    let best = 99
    const stem = x => x.length > 4 ? x.replace(/(ing|ed|es|e|s)$/, "") : x       // smile ~ smiling ~ smiles
    const ws = stem(w)
    for (const t of it.nameToks) {
        if (t === w || (ws.length >= 3 && stem(t) === ws)) return 0
        if (t.startsWith(w)) best = Math.min(best, 2)
        else if (t.indexOf(w) !== -1) best = Math.min(best, 3)
    }
    for (const t of it.keyToks) {
        if (t === w) return 1
        if (t.startsWith(w)) best = Math.min(best, 4)
        else if (t.indexOf(w) !== -1) best = Math.min(best, 5)
    }
    if (best < 99) return best
    return (alias[w] || []).some(a => it.lower.indexOf(a) !== -1) ? 6 : -1
}

// The items (from prep) that match every typed word, best first.
function ranked(items, words) {
    const scored = []
    for (const it of items) {
        let total = 0
        for (const w of words) { const s = rankWord(w, it); if (s === -1) { total = -1; break } total += s }
        // a line with no keyword part is a plain symbol (⌣ "smile"), not an emoji: it ranks
        // just after emoji that match equally well, so "smile" leads with the smiling
        // faces while "alpha" still finds the Greek letter before a lion
        if (total !== -1) scored.push({ it: it, d: total + (it.plain ? 0.5 : 0) })
    }
    if (scored.length === 0) {                // nothing as typed: allow slips, names before keywords
        for (const it of items) {
            let d = Fuzzy.score(words, it.nameToks)
            if (d === -1) { d = Fuzzy.score(words, it.nameToks.concat(it.keyToks)); if (d !== -1) d += 10 }
            if (d !== -1) scored.push({ it: it, d: d })
        }
    }
    // equal scores: when every word is a whole word of the name, the shorter name first
    // ("cat" before "grinning cat"); otherwise the list's own order, where recently used
    // and everyday emoji come first
    scored.sort((a, b) => a.d - b.d
        || (a.d === 0 ? a.it.nameToks.length - b.it.nameToks.length : 0) || a.it.index - b.it.index)
    return scored.map(s => s.it)
}

// Other names people type for the same thing, so the lists (keybindings, layouts, displays,
// screenshots...) answer to them. Each group is turned into word -> the rest of its group.
var alias = (function() {
    const groups = [
        ["workspace", "workspaces", "desktop"], ["monitor", "display", "screen", "output"],
        ["color", "colour"], ["center", "centre", "centered", "centred", "middle"],
        ["logout", "log out", "signout", "sign out", "exit"], ["quit", "kill", "close"],
        ["master", "main"], ["tile", "tiled", "tiling", "arrange", "layout"],
        ["spiral", "bsp", "fibonacci", "dwindle"], ["paper", "niri", "scrolling", "scroll"],
        ["max", "maximise", "maximize", "monocle"], ["screenshot", "capture", "prtsc", "print"],
        ["screencast", "record", "recording", "video"], ["area", "selection", "region"],
        ["duplicate", "clone", "mirror"], ["present", "presenting", "projector", "beamer"],
        ["external", "second screen", "extend"], ["sound", "audio", "volume"], ["mic", "microphone"],
        ["emoji", "emoticon", "smiley", "symbol"], ["copy", "clipboard", "paste"],
        ["apps", "applications", "launcher", "run", "start"], ["settings", "control panel", "preferences"],
        ["theme", "dark", "light", "appearance"], ["background", "wallpaper"], ["lock", "lock screen"],
        ["left", "←"], ["right", "→"], ["up", "↑"], ["down", "↓"], ["arrow", "arrows", "←", "→", "↑", "↓"],
        ["enter", "return"], ["win", "windows", "meta", "super"], ["float", "floating"],
        ["switch", "switcher", "alt-tab", "alt tab"], ["shortcuts", "keybindings", "keys", "hotkeys"],
        ["bigger", "larger", "wider", "taller", "resize"], ["smaller", "narrower", "shorter", "resize"],
        ["group", "tab", "tabs", "tabbed", "stack"], ["suspend", "sleep"], ["poweroff", "shutdown", "shut down", "power off"],
    ]
    const m = {}
    for (const g of groups) for (const w of g) m[w] = (m[w] || []).concat(g.filter(o => o !== w))
    return m
})()

// Every typed word appears in the line, as typed or as one of its other names
// (the plain, unranked pick lists).
function has(l, w) { return l.indexOf(w) !== -1 || (alias[w] || []).some(a => l.indexOf(a) !== -1) }
