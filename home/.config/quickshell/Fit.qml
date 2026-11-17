// Fit check: finds anything drawn where it gets cut off. Walks every shown window's items and reports
//   - an item that runs past its window's edge (the Wallpaper menu's right column, 2026-11-17)
//   - an item partly cut by a clipping parent (fully outside is a hidden page, not a cut)
//   - a Text whose words run past its own box (no elide, no wrap room)
//   - a window bigger than its screen
// Inside a Flickable / ListView the scroll direction is free; the other direction still counts.
// Text shortened with "…" on purpose is listed apart, as "elided", for a person to judge.
//
//   qs ipc call fit check     what is open now
//   qs ipc call fit sweep     opens each popup in turn on the focused screen, checks it, closes it
//   ~/.local/bin/fit-check    runs the sweep and prints the report (also ~/.local/state/fit-report.txt)
//
// An item that overflows on purpose (a marquee, a slide-out) sets `property bool fitOk: true`;
// the check then skips it and everything inside it.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Scope {
    id: fit
    // the shell's windows and Variants, by id from shell.qml (ShellRoot's own child list can't be read
    // from JavaScript); windows inside them (a bar's popups, one window per screen) are found from these
    property var roots: []
    // [label, open(), close()] for the sweep; shell.qml fills it with its ids
    property var steps: []
    property int settle: 800                 // ms after opening before checking (lists load, animations end)
    readonly property string reportPath: Quickshell.env("HOME") + "/.local/state/fit-report.txt"

    // ---- what kind of object is this ----
    function isItem(o) { return !!o && typeof o.mapToItem === "function" }
    function isWindow(o) { return !!o && !isItem(o) && o.contentItem !== undefined && ("screen" in o) }
    function isFlick(o) { return isItem(o) && ("contentY" in o) && ("flickableDirection" in o) }
    function isText(o) { return isItem(o) && ("elide" in o) && ("truncated" in o) && ("contentWidth" in o) }

    function typeName(o) {
        return String(o).replace(/\(0x[0-9a-f]+.*$/, "").replace(/_QMLTYPE_\d+|_QML_\d+/g, "").replace(/^QQuick/, "").replace(/^Proxy/, "")
    }
    function textOf(o, depth) {
        if (isText(o) && String(o.text || "").trim() !== "") return String(o.text).replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim()
        if (depth <= 0 || !isItem(o)) return ""
        for (let i = 0; i < o.children.length; i++) { const t = textOf(o.children[i], depth - 1); if (t) return t }
        return ""
    }
    function describe(o) {
        let t = textOf(o, 3)
        if (t.length > 48) t = t.slice(0, 47) + "…"
        return typeName(o) + (o.objectName ? "#" + o.objectName : "") + (t ? " \"" + t + "\"" : "")
    }

    // ---- every window reachable from `roots`, shown or not: window data, Variants, LazyLoaders ----
    function windows() {
        const out = [], seen = []
        function visit(o, label, depth) {
            if (!o || depth > 8 || seen.indexOf(o) >= 0) return
            seen.push(o)
            if (isItem(o)) return                                   // windows aren't declared inside items here
            let here = label
            if (isWindow(o)) {
                here = (label ? label + " > " : "") + typeName(o)
                out.push({ win: o, label: here })
            } else if (typeName(o) !== "QObject") {
                here = label || typeName(o)
            }
            for (const k of ["data", "instances"]) {
                try {
                    const l = o[k]
                    if (l && l.length !== undefined) for (let i = 0; i < l.length; i++) visit(l[i], here, depth + 1)
                } catch (e) {}
            }
            let it = null
            try { if ("item" in o && "active" in o) it = o.item } catch (e) {}
            if (it) visit(it, here, depth + 1)
        }
        for (const r of roots) visit(r, "", 0)
        return out
    }
    function shown(w) {
        try { return w.visible && w.contentItem && w.contentItem.width > 0 && w.contentItem.height > 0 } catch (e) { return false }
    }

    // ---- the check for one window ----
    function checkWindow(entry, problems, elided) {
        const w = entry.win, root = w.contentItem
        const scr = w.screen
        const where = entry.label + (scr ? " [" + scr.name + "]" : "")
        if (scr && (root.width > scr.width + 1 || root.height > scr.height + 1))
            problems.push(where + ": window " + Math.round(root.width) + "x" + Math.round(root.height)
                          + " is bigger than the screen " + scr.width + "x" + scr.height)
        const tol = 1
        // bounds: what of the window this item can still show, in window coordinates (Infinity = scrolls that way)
        // `quiet`: inside an item already reported; its own findings are only counted ("and N inside it")
        function walk(it, bounds, path, windowEdge, quiet) {
            let mine = null                                   // this item's own report, when it has one
            function push(msg) {
                if (quiet) {
                    quiet.n++
                    if (isText(it) && quiet.texts.length < 2 && quiet.texts.indexOf(describe(it)) < 0) quiet.texts.push(describe(it))
                    return
                }
                if (!mine) { mine = { i: problems.length, n: 0, texts: [] }; problems.push(msg) } else problems[mine.i] += "\n      also: " + msg.replace(where + ": ", "")
            }
            if (!isItem(it) || !it.visible || it.opacity <= 0.01) return
            if (it.fitOk === true) return
            const r = it.mapToItem(root, 0, 0, it.width, it.height)
            const name = describe(it)
            const here = path + " > " + typeName(it)
            const sized = it.width > 0.5 && it.height > 0.5
            const drawn = typeName(it) !== "MouseArea"         // a hit area reaching past its button is on purpose
            if (sized && drawn && it !== root) {
                // past the window edge (unless inside something that scrolls that way)
                const over = { left: windowEdge.x0 - r.x, right: r.x + r.width - windowEdge.x1,
                               top: windowEdge.y0 - r.y, bottom: r.y + r.height - windowEdge.y1 }
                const cut = Object.keys(over).filter(k => over[k] > tol)
                if (cut.length)
                    push(where + ": " + name + " runs past the window's " + cut.map(k => k + " edge by " + Math.round(over[k]) + " px").join(", ")
                                  + "\n      at " + here)
                // partly cut by a clipping ancestor
                else {
                    const inside = r.x < bounds.x1 && r.x + r.width > bounds.x0 && r.y < bounds.y1 && r.y + r.height > bounds.y0
                    const o2 = { left: bounds.x0 - r.x, right: r.x + r.width - bounds.x1, top: bounds.y0 - r.y, bottom: r.y + r.height - bounds.y1 }
                    const c2 = Object.keys(o2).filter(k => o2[k] > tol)
                    if (inside && c2.length && !isText(it))         // text is judged by its own rule below
                        push(where + ": " + name + " is cut by a clipping parent on the " + c2.map(k => k + " by " + Math.round(o2[k]) + " px").join(", ")
                                      + "\n      at " + here)
                }
            }
            if (isText(it) && sized && String(it.text || "") !== "") {
                const t = describe(it)
                if (it.truncated) elided.push(where + ": " + t + " (" + Math.round(it.width) + " px wide)")
                else if (it.elide === Text.ElideNone && it.contentWidth > it.width + tol && it.wrapMode === Text.NoWrap)
                    push(where + ": " + t + " spills " + Math.round(it.contentWidth - it.width) + " px past its box (no elide, no wrap)\n      at " + here)
                else if (it.contentHeight > it.height + 2 && it.elide === Text.ElideNone && !(it.maximumLineCount < 1000))
                    push(where + ": " + t + " is " + Math.round(it.contentHeight - it.height) + " px taller than its box\n      at " + here)
                // a text cut by a clip is a problem too, unless it is fully hidden
                const o3 = { left: bounds.x0 - r.x, right: r.x + Math.min(r.width, Math.max(it.contentWidth, 0)) - bounds.x1, top: bounds.y0 - r.y, bottom: r.y + r.height - bounds.y1 }
                const inside3 = r.x < bounds.x1 && r.x + r.width > bounds.x0 && r.y < bounds.y1 && r.y + r.height > bounds.y0
                const c3 = Object.keys(o3).filter(k => o3[k] > tol)
                if (inside3 && c3.length && !(windowEdge.x0 - r.x > tol || r.x + r.width - windowEdge.x1 > tol))
                    push(where + ": " + t + " is cut by a clipping parent on the " + c3.map(k => k + " by " + Math.round(o3[k]) + " px").join(", ") + "\n      at " + here)
            }
            // narrow the bounds for the children
            let b = bounds, edge = windowEdge
            if (isFlick(it)) {
                const horizontal = it.orientation === 1 || it.contentWidth > it.width + tol         // ListView.Horizontal = 1
                const vertical = it.orientation !== 1                                                // anything else scrolls down
                b = { x0: horizontal ? -Infinity : Math.max(b.x0, r.x), x1: horizontal ? Infinity : Math.min(b.x1, r.x + r.width),
                      y0: vertical ? -Infinity : Math.max(b.y0, r.y), y1: vertical ? Infinity : Math.min(b.y1, r.y + r.height) }
                edge = { x0: horizontal ? -Infinity : edge.x0, x1: horizontal ? Infinity : edge.x1,
                         y0: vertical ? -Infinity : edge.y0, y1: vertical ? Infinity : edge.y1 }
            } else if (it.clip && sized) {
                b = { x0: Math.max(b.x0, r.x), x1: Math.min(b.x1, r.x + r.width), y0: Math.max(b.y0, r.y), y1: Math.min(b.y1, r.y + r.height) }
            }
            const q = quiet || mine
            for (let i = 0; i < it.children.length; i++) walk(it.children[i], b, here, edge, q)
            if (mine && mine.n > 0) problems[mine.i] += "\n      (and " + mine.n + " finding" + (mine.n === 1 ? "" : "s") + " inside it"
                                                         + (mine.texts.length ? "; text among them: " + mine.texts.join(", ") : "") + ")"
        }
        const all = { x0: 0, y0: 0, x1: root.width, y1: root.height }
        walk(root, all, typeName(w), all, null)
    }

    // ---- what is open now ----
    function checkNow(tag) {
        const problems = [], elided = []
        const ws = windows().filter(e => shown(e.win))
        for (const e of ws) {
            try { checkWindow(e, problems, elided) } catch (err) { problems.push(e.label + ": check failed: " + err) }
        }
        return { tag: tag || "now", windows: ws.map(e => e.label), problems: problems, elided: elided }
    }
    function format(results) {
        let probs = 0, out = []
        const seenP = {}, seenE = {}
        for (const r of results) {
            const ps = r.problems.filter(p => !seenP[p]); ps.forEach(p => seenP[p] = true)
            const es = r.elided.filter(p => !seenE[p]); es.forEach(p => seenE[p] = true)
            probs += ps.length
            if (!ps.length && !es.length) { out.push("ok    " + r.tag); continue }
            out.push((ps.length ? "CUT   " : "ok    ") + r.tag + (ps.length ? "  (" + ps.length + ")" : ""))
            for (const p of ps) out.push("   ✗ " + p)
            for (const e of es) out.push("   … elided: " + e)
        }
        out.push("")
        out.push("FITCHECK RESULT " + (probs ? "cut " + probs : "clean") + "  (" + results.length + " views checked)")
        return out.join("\n")
    }
    function report(results) {
        const text = format(results)
        reportFile.setText(text + "\n")
        console.log(text)
        return text
    }

    // ---- the sweep: open, wait, check, close, next ----
    property bool sweeping: false
    property int stepIndex: -1
    property var results: []
    function sweep() {
        if (sweeping) return "already sweeping"
        results = [checkNow("already open")]
        reportFile.setText("running\n")
        sweeping = true
        stepIndex = -1
        nextStep()
        return "sweeping " + steps.length + " views on " + (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "?") + "; report in " + reportPath
    }
    function nextStep() {
        stepIndex++
        if (stepIndex >= steps.length) { sweeping = false; report(results); return }
        try { steps[stepIndex][1]() } catch (e) { console.log("fit: could not open " + steps[stepIndex][0] + ": " + e) }
        checkTimer.restart()
    }
    Timer {
        id: checkTimer
        interval: fit.settle
        onTriggered: {
            const s = fit.steps[fit.stepIndex]
            const r = fit.checkNow(s[0])
            fit.results = fit.results.concat([r])
            try { s[2]() } catch (e) { console.log("fit: could not close " + s[0] + ": " + e) }
            gapTimer.restart()
        }
    }
    Timer { id: gapTimer; interval: 250; onTriggered: fit.nextStep() }

    FileView { id: reportFile; path: fit.reportPath; blockLoading: true }

    IpcHandler {
        target: "fit"
        function check(): string { return fit.report([fit.checkNow("open now")]) }
        function sweep(): string { return fit.sweep() }
        function status(): string { return fit.sweeping ? "sweeping " + (fit.stepIndex + 1) + "/" + fit.steps.length : "idle" }
        function windows(): string { return fit.windows().map(e => (fit.shown(e.win) ? "shown  " : "hidden ") + e.label).join("\n") }
    }
}
