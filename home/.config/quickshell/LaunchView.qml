// What the launcher window (Launcher.qml) shows: a query line and a list, in one of
// several modes picked by a prefix typed at the start of the query (or by Tab, which
// cycles through them; Backspace on an empty query goes back to apps):
//   (none) apps, as always; arithmetic like "2*(3+4)" also gets a calculator row first
//   =  calculator (qalc); Enter copies the result; the last 10 copied stay as rows
//   :  emoji and symbols (the list emoji-picker builds); Enter types it and copies it
//   v  clipboard history (cliphist); Enter copies it back, Shift+Delete forgets it
//   w  open windows, most recently used first; Enter goes to it
//   /  files under ~ (fd); Enter opens, Ctrl+Enter opens the folder, Alt+Enter copies the path
//   ?  Hyprland keybindings; Enter copies the key combination
//   o  capture the text into Org (emacsclient, template `captureKey` in launcher.json)
//   m  mail (mu find; empty query = unread in the two inboxes); Enter opens it in mu4e; hidden in Do Not Disturb
//   n  org-roam notes by title (index in $XDG_CACHE_HOME/launcher-roam.tsv, rebuilt in the background
//      when older than 10 min by launcher-roam-index); Enter opens the file in Emacs
//   t  open Firefox tabs (tabs-list, kept 30 s); Enter goes to the window showing the tab, or opens its URL
//   v  also: Ctrl+P pins the entry (kept in $XDG_STATE_HOME/clip-pins, survives cliphist pruning and
//      `clip-menu clear`, listed first); Shift+Delete on a pin removes the pin
//   qr TEXT (in apps) shows TEXT as a QR code; Enter copies the picture
// m, n and t are reached by their prefix only (Tab does not cycle through them: they run
// commands as soon as they open).
// Every row is { label, sub, icon, image, glyph, run }; Enter calls the row's run(mods).
// Also: two (label above, sub below), find (text the typed words must match), del (what Shift+Delete
// does), thumbUrl (picture rows), big + bigUrl (the QR row).
// Commands only run while the launcher is open, and only for the mode in use.
//
// Other features can add rows to the app list without editing this file: put functions in
// `providers`, each (query) => [row] with query the trimmed text typed. Their rows follow the apps
// (rows need label, sub and run; close the launcher through view.close() in run if it should go).
// Called on every keystroke in app mode, so they must be cheap and must never throw. In the shell:
//   launcher.view.providers = [q => Sys.nextEvent ? [{ label: "Join next meeting", sub: "", icon: "", run: () => {...} }] : []]
// extraRows(query) is that call, public.
//
// Tests replace the data sources: fakeApps (desktop entries), fakeWindows, fakeRun (every
// command; see LaunchCmd.qml). See tests/launcher.
import QtQuick
import "fuzzy.js" as Fuzzy
import "rank.js" as Rank
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Hyprland

Item {
    id: view
    signal closeRequested()
    property var fakeApps: null
    property var fakeWindows: null     // [{ address, title, cls, ws (workspace id), focus (focusHistoryID) }]
    property var fakeRun: null
    property var providers: []         // functions (query) => [row], appended in app mode; see the top of the file
    function extraRows(q) {
        let rows = []
        for (const f of providers) {
            try { rows = rows.concat(f(q) || []) } catch (e) { console.log("LaunchView: a provider failed: " + e) }
        }
        return rows
    }

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || home + "/.cache"
    readonly property string clipDir: cacheHome + "/launcher-clip"
    readonly property string pinDir: stateHome + "/clip-pins"
    readonly property string roamDir: home + "/.emacs.d/org/roam"
    readonly property string roamIndex: cacheHome + "/launcher-roam.tsv"

    // ---- modes ----
    readonly property var modes: [
        { id: "apps",  prefix: "",   chip: "",      hint: "Search apps",             one: "app",     many: "apps" },
        { id: "calc",  prefix: "=",  chip: "calc",  hint: "Calculate (qalc)",        one: "result",  many: "results" },
        { id: "emoji", prefix: ":",  chip: "emoji", hint: "Emoji and symbols",       one: "symbol",  many: "symbols" },
        { id: "clip",  prefix: "v ", chip: "clip",  hint: "Clipboard history",       one: "entry",   many: "entries",
          keys: "<b>Ctrl+P</b> pin or unpin &nbsp; <b>Shift+Delete</b> forget it (or unpin)" },
        { id: "win",   prefix: "w ", chip: "win",   hint: "Switch window",           one: "window",  many: "windows" },
        { id: "files", prefix: "/",  chip: "files", hint: "Find files in your home", one: "file",    many: "files" },
        { id: "keys",  prefix: "?",  chip: "keys",  hint: "Keybindings",             one: "binding", many: "bindings" },
        { id: "org",   prefix: "o ", chip: "org",   hint: "Capture a note to Org",   one: "",        many: "" },
        { id: "mail",  prefix: "m ", chip: "mail",  hint: "Search mail (empty: unread)", one: "message", many: "messages", cyc: false,
          keys: "Type to search (mu syntax, e.g. from:name) &nbsp; <b>Enter</b> opens in mu4e" },
        { id: "notes", prefix: "n ", chip: "notes", hint: "Search your notes",       one: "note",    many: "notes",    cyc: false,
          keys: "Titles of your org-roam notes &nbsp; <b>Enter</b> opens in Emacs" },
        { id: "tabs",  prefix: "t ", chip: "tabs",  hint: "Switch Firefox tab",      one: "tab",     many: "tabs",     cyc: false,
          keys: "Open Firefox tabs &nbsp; <b>Enter</b> goes to the window, or opens the page again" },
    ]
    property string mode: "apps"
    readonly property var modeInfo: modes.find(m => m.id === mode) || modes[0]
    property alias queryText: query.text
    property alias currentIndex: list.currentIndex
    readonly property var current: results[list.currentIndex] || null

    // "=", ":", "v", "v ", "w", "/", "?", "o", a mode's name, or "" for apps
    function modeOf(prefix) {
        const p = String(prefix || "").trim()
        if (p === "") return "apps"
        const m = modes.find(m => m.id !== "apps" && (m.prefix.trim() === p || m.id === p))
        return m ? m.id : "apps"
    }
    property var loaded: ({})           // modes whose data was read since the launcher opened
    function setMode(m) {
        if (mode !== m) { mode = m; list.currentIndex = 0 }
        if (!loaded[m]) { loaded[m] = true; enter(m) }
        changed()
    }
    function cycle(d) {
        const ms = modes.filter(m => m.cyc !== false)
        const i = ms.findIndex(m => m.id === mode)
        setMode(ms[(i + d + ms.length) % ms.length].id)
    }
    // the launcher opened (or was asked for another mode while open)
    function begin(m) {
        loaded = {}
        mode = "apps"
        query.text = ""
        list.currentIndex = 0
        setMode(m)
        query.forceActiveFocus()
    }
    // the launcher closed: stop everything, forget the clipboard
    function end() {
        calcDelay.stop(); filesDelay.stop(); mailDelay.stop(); qrDelay.stop()
        calcCmd.stop(); clipCmd.stop(); thumbCmd.stop(); filesCmd.stop(); keysCmd.stop(); mailCmd.stop(); pinCmd.stop(); qrCmd.stop()
        clipRows = []; thumbs = ({}); thumbQueue = []
        fileRows = []; keyRows = []
        notesCmd.stop(); tabsCmd.stop(); noticeTimer.stop()
        mailRows = []; mailAsked = null; mailDone = null; noteRows = []         // mail subjects and clipboard pins are not kept
        pins = []; pinPending = null; notice = ""
        if (qrFile !== "") Sys.launch(["rm", "-f", qrFile])
        qrFile = ""; qrDone = null
        loaded = {}
        mode = "apps"
    }
    function close() { closeRequested() }

    function enter(m) {
        if (m === "emoji") loadEmoji()
        else if (m === "clip") {
            Sys.launch(["find", clipDir, "-type", "f", "-mmin", "+1440", "-delete"])     // thumbnails older than a day
            loadPins()
            clipCmd.run(["cliphist", "list"])
        }
        else if (m === "mail") mailNow()
        else if (m === "notes") notesEnter()
        else if (m === "tabs") tabsEnter()
        else if (m === "win") { if (!fakeWindows) Hyprland.refreshToplevels() }
        else if (m === "keys") keysCmd.run(["hyprctl", "binds", "-j"])
        else if (m === "org") {
            try { captureKey = String(JSON.parse(readFile(settings, settingsPath)).captureKey || "") } catch (e) { captureKey = "" }
        }
    }
    // the query changed: start what this mode runs in the background
    function changed() {
        const q = query.text.trim()
        if (mode === "calc" || (mode === "apps" && isArith(q))) calcDelay.restart()
        else { calcDelay.stop(); calcCmd.stop() }
        if (mode === "files") filesDelay.restart()
        else { filesDelay.stop(); filesCmd.stop() }
        if (mode === "mail") { if (q !== mailAsked) mailDelay.restart() }       // entering the mode already asked
        else { mailDelay.stop(); mailCmd.stop() }
        if (mode === "apps" && qrText(q) !== "") qrDelay.restart()
        else { qrDelay.stop(); qrCmd.stop(); qrFile = "" }
    }
    function typed() {
        if (mode === "apps") {                          // a prefix at the start switches the mode
            for (const m of modes) {
                if (m.prefix !== "" && query.text.startsWith(m.prefix)) {
                    const rest = query.text.slice(m.prefix.length)
                    setMode(m.id)
                    query.text = rest                   // comes back here, now in that mode
                    return
                }
            }
        }
        list.currentIndex = 0
        changed()
    }

    // ---- apps (unchanged from the plain launcher) ----
    readonly property var all: fakeApps || DesktopEntries.applications.values.filter(e => !e.noDisplay && e.name !== "")
    // lower is better; -1 = no match
    function score(e, q) {
        const name = e.name.toLowerCase()
        if (name.startsWith(q)) return 0
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 1
        if (name.indexOf(q) !== -1) return 2
        const more = (e.genericName + " " + String(e.keywords) + " " + e.comment).toLowerCase()
        return more.indexOf(q) !== -1 ? 3 : -1
    }
    // How often and how recently each app was started from here, so favourites
    // float to the top: { "<id>": { n: launches, t: last launch (ms) } }
    property var usage: ({})
    FileView {
        id: usageFile
        path: view.stateHome + "/launcher-usage.json"
        printErrors: false
        onLoaded: { try { view.usage = JSON.parse(text()) } catch (e) { view.usage = {} } }
    }
    function weight(e) {
        const u = usage[e.id]
        if (!u) return 0
        const days = (Date.now() - u.t) / 86400000
        return u.n * (days < 1 ? 4 : days < 7 ? 2 : days < 30 ? 1 : 0.5)
    }
    function appResults(q) {
        let list = all.map(e => ({ e: e, s: q === "" ? 0 : score(e, q), w: weight(e) })).filter(x => x.s >= 0)
        if (list.length === 0 && q !== "") {
            // nothing matched as typed: allow a slip or two per word (fuzzy.js); the name counts before the description
            const words = q.split(/\s+/)
            for (const e of all) {
                let d = Fuzzy.score(words, Fuzzy.tokens(e.name))
                if (d === -1) {
                    d = Fuzzy.score(words, Fuzzy.tokens(e.name + " " + e.genericName + " " + String(e.keywords) + " " + e.comment))
                    if (d !== -1) d += 10
                }
                if (d !== -1) list.push({ e: e, s: d, w: weight(e) })
            }
        }
        list.sort((a, b) => a.s - b.s || b.w - a.w || a.e.name.localeCompare(b.e.name))
        return list.map(x => x.e)
    }
    function appRow(e) {
        return { label: e.name, sub: e.comment || e.genericName, icon: e.icon || "", entry: e, run: () => view.launchApp(e) }
    }
    function launchApp(e) {
        close()
        const u = Object.assign({}, usage)
        u[e.id] = { n: (u[e.id] ? u[e.id].n : 0) + 1, t: Date.now() }
        usage = u
        usageFile.setText(JSON.stringify(u))
        const id = e.id.endsWith(".desktop") ? e.id : e.id + ".desktop"
        Sys.run("uwsm app -- '" + id.replace(/'/g, "") + "'")
    }

    // ---- calculator ----
    // digits and operators only, with at least one operator between numbers ("2*(3+4)", "2^10")
    function isArith(q) { return /^[\d\s.,+\-*\/^%()]+$/.test(q) && /\d\s*[-+*\/^%]\s*[\d(.]/.test(q) }
    property string calcAsked: ""       // the expression qalc is working on
    property string calcExpr: ""        // ...and the one it last answered
    property string calcResult: ""
    property var calcHistory: []        // [{ expr, result }] newest first, kept while the shell runs
    Timer { id: calcDelay; interval: 150; onTriggered: view.calcNow() }
    function calcNow() {
        const q = query.text.trim()
        if (q === "") { calcCmd.stop(); calcExpr = ""; calcResult = ""; return }
        calcAsked = q
        calcCmd.run(["qalc", "-t", q])
    }
    LaunchCmd {
        id: calcCmd
        fake: view.fakeRun
        onFinished: (out, ok) => { view.calcExpr = view.calcAsked; view.calcResult = ok ? out.trim().split("\n").pop() : "" }
    }
    function calcRow(expr, result, fromHistory) {
        return { label: result, sub: expr + (fromHistory ? "" : "   Enter copies"), icon: "accessories-calculator",
                 run: () => view.copyResult(expr, result) }
    }
    function copyResult(expr, result) {
        close()
        Sys.launch(["wl-copy", "--", result])
        calcHistory = [{ expr: expr, result: result }].concat(calcHistory.filter(h => h.expr !== expr)).slice(0, 10)
    }
    readonly property var calcNowRow: {
        const q = query.text.trim()
        return q !== "" && calcExpr === q && calcResult !== "" ? calcRow(q, calcResult, false) : null
    }

    // ---- emoji (the list and recents file that emoji-picker writes) ----
    property var emojiRows: []
    property var emojiRecent: []        // lines of the recents file, newest first
    readonly property string emojiPath: cacheHome + "/emoji-picker.txt"
    readonly property string emojiRecentPath: stateHome + "/emoji-recent"
    FileView { id: emojiFile; blockLoading: true; printErrors: false }
    FileView { id: emojiRecentFile; blockLoading: true; printErrors: false }
    function readFile(fv, path) {
        fv.path = ""                    // a file that was missing last time is read again too
        fv.path = path
        return fv.text()
    }
    function lines(t) { return t.split("\n").filter(l => l !== "") }
    function loadEmoji() {
        const recent = lines(readFile(emojiRecentFile, emojiRecentPath))
        const listed = lines(readFile(emojiFile, emojiPath))
        const seen = new Set(recent)
        emojiRecent = recent
        // as emoji-picker lists them: recently used first, then the list without those
        emojiRows = (listed.length ? recent : []).concat(listed.filter(l => !seen.has(l))).map((l, i) => {
            const it = Rank.prep(l, i)
            const cut = l.indexOf("  "), rest = cut === -1 ? "" : l.slice(cut + 2), kw = rest.indexOf("   ")
            it.glyph = cut === -1 ? l : l.slice(0, cut)
            it.label = kw === -1 ? rest : rest.slice(0, kw)
            it.sub = kw === -1 ? "" : rest.slice(kw + 3)
            it.line = l
            it.run = () => view.typeEmoji(l)
            return it
        })
    }
    function typeEmoji(line) {
        const ch = line.split("  ")[0]
        if (ch === "") return
        close()
        emojiRecent = [line].concat(emojiRecent.filter(l => l !== line)).slice(0, 24)
        emojiRecentFile.setText(emojiRecent.join("\n") + "\n")
        // as emoji-picker does: on the clipboard, and typed once focus is back in the window
        Sys.launch(["sh", "-c", 'printf %s "$1" | wl-copy; sleep 0.25; wtype "$1"', "sh", ch])
    }
    readonly property var emojiMissing: [{ label: "No emoji list yet", sub: "Enter builds it (emoji-picker)", icon: "face-smile",
                                           run: () => { view.close(); Sys.run(Sys.bin + "emoji-picker") } }]

    // ---- clipboard (cliphist) ----
    property var clipRows: []
    property var thumbs: ({})           // cliphist id -> picture url, once decoded
    property var thumbQueue: []
    LaunchCmd {
        id: clipCmd
        fake: view.fakeRun
        onFinished: (out, ok) => { view.clipRows = ok ? view.parseClip(out) : [] }
    }
    function parseClip(out) {
        const rows = []
        for (const l of out.split("\n")) {
            const tab = l.indexOf("\t")
            if (tab <= 0) continue
            const id = l.slice(0, tab)
            if (!/^\d+$/.test(id)) continue
            const preview = l.slice(tab + 1)
            const bin = /^\[\[ binary data (.*?) (png|jpe?g|gif|bmp|webp|tiff?) (\d+x\d+) \]\]$/.exec(preview)
            const row = { id: id, sub: "", run: () => view.copyClip(id), del: () => view.deleteClip(id) }
            if (bin) {
                row.image = true
                row.label = "Image " + bin[3]
                row.sub = bin[2] + ", " + bin[1]
                row.find = "image picture " + bin[2]
            } else {
                row.icon = /^\[\[ binary data/.test(preview) ? "application-octet-stream" : "edit-paste"
                row.label = preview.split("\n")[0].trim()
                row.find = row.label.toLowerCase()
            }
            rows.push(row)
        }
        return rows
    }
    function copyClip(id) {
        close()
        Sys.launch(["sh", "-c", 'printf "%s\\t\\n" "$1" | cliphist decode | wl-copy', "sh", id])
    }
    function deleteClip(id) {
        Sys.launch(["sh", "-c", 'printf "%s\\t\\n" "$1" | cliphist delete', "sh", id])
        const i = list.currentIndex
        clipRows = clipRows.filter(r => r.id !== id)
        list.currentIndex = Math.min(i, Math.max(0, results.length - 1))
    }
    // image rows: decoded to clipDir/ID.png the first time the row is on screen, one at a time
    function wantThumb(id) {
        if (thumbs[id] !== undefined || thumbQueue.indexOf(id) !== -1) return
        thumbQueue = thumbQueue.concat([id])
        if (!thumbCmd.busy) nextThumb()
    }
    property string thumbId: ""
    function nextThumb() {
        if (thumbQueue.length === 0) return
        thumbId = thumbQueue[0]
        thumbQueue = thumbQueue.slice(1)
        thumbCmd.run(["sh", "-c", 'f="$1/$2.png"; [ -s "$f" ] && exit 0; mkdir -p "$1" && printf "%s\\t\\n" "$2" | cliphist decode > "$f.part" && mv "$f.part" "$f"',
                      "sh", clipDir, thumbId])
    }
    LaunchCmd {
        id: thumbCmd
        fake: view.fakeRun
        timeout: 4000
        onFinished: (out, ok) => {
            const t = Object.assign({}, view.thumbs)
            t[view.thumbId] = ok ? "file://" + view.clipDir + "/" + view.thumbId + ".png" : ""
            view.thumbs = t
            view.nextThumb()
        }
    }

    // ---- windows ----
    function wsLabel(id) { return id < 0 ? "scratch" : id >= 11 ? "Desktop " + Math.floor(id / 10) : "ws " + id }
    function toplevelList() {
        let ws = fakeWindows
        if (!ws) {
            ws = []
            for (const t of Hyprland.toplevels.values) {
                const o = t.lastIpcObject || {}
                if (o.mapped === false) continue
                const wid = o.workspace ? o.workspace.id : t.workspace ? t.workspace.id : 0
                if (wid === 0) continue
                ws.push({ address: t.address, title: t.title, cls: o.class || "", ws: wid, focus: o.focusHistoryID ?? 99 })
            }
        }
        return ws
    }
    readonly property var windows: {
        if (mode !== "win") return []
        let ws = toplevelList()
        ws = ws.slice().sort((a, b) => a.focus - b.focus)
        // most recently used first, the current window last: Enter goes back to the previous one
        // (as the Alt+Tab list does)
        return ws.slice(1).concat(ws.slice(0, 1)).map(w => {
            const e = DesktopEntries.heuristicLookup(w.cls)
            const label = w.title.split(/\s+/).join(" ")
            return { label: label, sub: w.cls + "  " + wsLabel(w.ws), icon: e ? e.icon : w.cls.toLowerCase(),
                     find: (label + " " + w.cls + " " + wsLabel(w.ws)).toLowerCase(),
                     run: () => view.focusWindow(w.address) }
        })
    }
    function focusWindow(address) {
        close()
        const a = "0x" + String(address).replace(/^0x/, "").replace(/[^0-9a-fA-F]/g, "")
        // after the launcher has gone: closing it hands focus back to the window it took it from
        Sys.run("sleep 0.05; hyprctl dispatch 'hl.dsp.focus({ window = \"address:" + a + "\" })'")
    }

    // ---- files ----
    property var fileRows: []
    property string filesAsked: ""
    Timer { id: filesDelay; interval: 150; onTriggered: view.filesNow() }
    function fdArgv(q) {
        // the words in order, anything between ("rep pdf" finds "report-final.pdf")
        const pattern = q.split(/\s+/).filter(w => w !== "").map(w => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*")
        return ["sh", "-c", 'f=$1; shift; [ -x "$f" ] || f=$(command -v fd || command -v fdfind) || exit 127; exec "$f" "$@"',
                "sh", home + "/.local/bin/fd", "--max-results", "60", "--base-directory", home, "--color", "never",
                "--exclude", "node_modules", "--exclude", "__pycache__", "--exclude", "venv", "--exclude", "site-packages",
                "--exclude", "*.pyc", "--exclude", "*.o", "--exclude", "snap", "--", pattern]
    }
    function filesNow() {
        const q = query.text.trim()
        if (q.length < 2) { filesCmd.stop(); fileRows = []; return }
        filesAsked = q
        filesCmd.run(fdArgv(q))
    }
    LaunchCmd {
        id: filesCmd
        fake: view.fakeRun
        onFinished: (out, ok) => { if (view.filesAsked === query.text.trim()) view.fileRows = ok ? view.parseFiles(out) : [] }
    }
    function fileIcon(p) {
        if (p.endsWith("/")) return "folder"
        const ext = (/\.([a-z0-9]+)$/i.exec(p) || ["", ""])[1].toLowerCase()
        const m = { pdf: "application-pdf", png: "image-x-generic", jpg: "image-x-generic", jpeg: "image-x-generic", svg: "image-svg+xml",
                    gif: "image-x-generic", webp: "image-x-generic", mp4: "video-x-generic", mkv: "video-x-generic", webm: "video-x-generic",
                    mp3: "audio-x-generic", flac: "audio-x-generic", ogg: "audio-x-generic", org: "text-x-generic", md: "text-x-generic",
                    txt: "text-x-generic", tex: "text-x-tex", py: "text-x-python", sh: "text-x-script", qml: "text-x-generic",
                    html: "text-html", csv: "text-csv", zip: "package-x-generic", gz: "package-x-generic", tar: "package-x-generic",
                    docx: "x-office-document", pptx: "x-office-presentation", xlsx: "x-office-spreadsheet" }
        return m[ext] || "text-x-generic"
    }
    function parseFiles(out) {
        const ps = out.split("\n").filter(l => l !== "")
        // fd answers in no particular order: shallow paths first, then by name
        ps.sort((a, b) => a.split("/").length - b.split("/").length || a.localeCompare(b))
        return ps.map(p => {
            const bare = p.replace(/\/$/, ""), cut = bare.lastIndexOf("/")
            const full = home + "/" + bare
            return { label: bare.slice(cut + 1) + (p.endsWith("/") ? "/" : ""),
                     sub: "~/" + (cut === -1 ? "" : bare.slice(0, cut + 1)), icon: fileIcon(p), path: full,
                     run: mods => view.openFile(full, mods) }
        })
    }
    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function openFile(path, mods) {
        close()
        if (mods & Qt.AltModifier) Sys.launch(["wl-copy", "--", path])
        else if (mods & Qt.ControlModifier) Sys.run("xdg-open " + shq(path.replace(/\/[^/]*$/, "") || "/"))
        else Sys.run("xdg-open " + shq(path))
    }

    // ---- keybindings (hyprctl binds -j, as keybind-help shows them) ----
    property var keyRows: []
    LaunchCmd {
        id: keysCmd
        fake: view.fakeRun
        onFinished: (out, ok) => { view.keyRows = ok ? view.parseBinds(out) : [] }
    }
    function parseBinds(out) {
        let bs = []
        try { bs = JSON.parse(out) } catch (e) { return [] }
        const mods = [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"]]
        const names = { "Return": "Enter", "slash": "/", "bracketleft": "[", "bracketright": "]",
                        "left": "←", "right": "→", "up": "↑", "down": "↓", "Print": "PrtSc",
                        "mouse_down": "scroll down", "mouse_up": "scroll up",
                        "mouse:272": "left-drag", "mouse:273": "right-drag" }
        const rows = []
        for (const b of bs) {
            if (!b.description) continue
            let key = String(b.key || "")
            if (key.startsWith("XF86")) key = "Fn key"
            else if (key.startsWith("switch:")) key = "Lid"
            else key = names[key] || key
            // a key inside a submap is pressed after the key that enters it (hyprland.lua)
            const lead = { lecture: "Super + Z, then " }[b.submap || ""] || ""
            const combo = lead + mods.filter(m => (b.modmask & m[0]) !== 0).map(m => m[1]).concat([key]).join(" + ")
            rows.push({ label: combo, sub: b.description, icon: "input-keyboard", find: (combo + "   " + b.description).toLowerCase(),
                        run: () => { view.close(); Sys.launch(["wl-copy", "--", combo]) } })
        }
        return rows
    }

    // ---- org capture ----
    // $XDG_STATE_HOME/launcher.json { "captureKey": "j" }: the org-capture template; read when
    // the mode is entered, never written from here
    readonly property string settingsPath: stateHome + "/launcher.json"
    property string captureKey: ""
    FileView { id: settings; blockLoading: true; printErrors: false }
    // an Emacs Lisp string literal: backslashes and quotes escaped, newlines as \n
    function elispString(s) {
        return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\r/g, "\\r") + '"'
    }
    function captureArgv(textIn, key) {
        return ["timeout", "5", "emacsclient", "-n", "-e", "(org-capture-string " + elispString(textIn) + " " + elispString(key) + ")"]
    }
    readonly property var orgRow: {
        const t = query.text.trim(), key = captureKey
        if (key === "") return { label: "Set a capture template first", sub: "captureKey in launcher.json", icon: "dialog-information", run: null }
        if (t === "") return { label: "Type a note to capture", sub: "template " + key, icon: "emacs", run: null }
        return { label: t, sub: "Org capture, template " + key, icon: "emacs",
                 run: () => { view.close(); Sys.launch(view.captureArgv(t, key)) } }
    }

    // ---- mail (mu find; Enter opens the message in mu4e) ----
    // Subjects and senders are shown, never logged, and dropped when the launcher closes. While
    // Do Not Disturb is on the mode shows a notice instead and runs no query.
    readonly property string mailUnread: 'flag:unread AND NOT flag:trashed AND (maildir:"/work/INBOX" OR maildir:"/personal/INBOX")'
    property var mailRows: []
    property var mailAsked: null            // the query mu is working on, or null
    property var mailDone: null             // the query whose answer mailRows holds
    Timer { id: mailDelay; interval: 250; onTriggered: view.mailNow() }
    function mailArgv(q) {
        // the query goes in parentheses so a leading "-" is never taken for an option
        return [home + "/.local/bin/mu", "find", "--fields", "d\tf\ts\ti", "--sortfield=date", "--reverse", "--maxnum=40",
                q === "" ? mailUnread : "(" + q + ")"]
    }
    function mailNow() {
        if (Notif.dnd) { mailCmd.stop(); return }
        const q = query.text.trim()
        mailAsked = q
        mailCmd.run(mailArgv(q))
    }
    LaunchCmd {
        id: mailCmd
        fake: view.fakeRun
        timeout: 8000
        onFinished: (out, ok) => { view.mailRows = ok ? view.parseMail(out) : []; view.mailDone = view.mailAsked }
    }
    Connections {
        target: Notif
        function onDndChanged() { if (view.mode === "mail") { if (Notif.dnd) { view.mailRows = []; view.mailDone = null } view.mailNow() } }
    }
    // "d <tab> from <tab> subject <tab> message-id" lines
    function parseMail(out) {
        const rows = []
        for (const l of out.split("\n")) {
            const f = l.split("\t")
            if (f.length < 4) continue
            const id = f[f.length - 1].trim(), subject = f.slice(2, -1).join(" ").trim()
            if (id === "") continue
            const from = f[1].trim(), nameEnd = from.indexOf("<")
            const sender = (nameEnd > 0 ? from.slice(0, nameEnd) : from.replace(/[<>]/g, "")).trim().replace(/^"|"$/g, "")
            rows.push({ label: subject || "(no subject)", sub: (sender || "(unknown sender)") + "   " + f[0].trim(), two: true,
                        icon: "mail-unread", find: "", run: () => view.openMail(id) })
        }
        return rows
    }
    function openMail(id) {
        close()
        // mu4e is started in the background first when it is not running yet
        Sys.launch(["timeout", "5", "emacsclient", "-n", "-e",
                    "(progn (unless (mu4e-running-p) (mu4e t)) (mu4e-view-message-with-message-id " + elispString(id) + "))"])
        Sys.focusEmacs()
    }
    readonly property var mailList: {
        if (Notif.dnd) return [{ label: "Mail is hidden while Do Not Disturb is on", sub: "", icon: "notifications-disabled", info: true, run: null }]
        const q = query.text.trim()
        if (mailRows.length === 0)
            return [{ label: mailDone === q ? (q === "" ? "No unread mail" : "No messages found") : "Searching…", sub: "", icon: "mail-message", info: true, run: null }]
        return mailRows
    }

    // ---- notes (org-roam titles) ----
    // The index is a tab-separated file (path, title, modified epoch); launcher-roam-index rebuilds it
    // in the background when it is older than 10 minutes, and the list reads whatever is there at once.
    property var noteRows: []
    property bool notesLoaded: false
    FileView { id: roamFile; blockLoading: true; printErrors: false }
    LaunchCmd {
        id: notesCmd
        fake: view.fakeRun
        timeout: 30000
        onFinished: (out, ok) => view.loadNotes()
    }
    function notesEnter() {
        loadNotes()
        notesCmd.run([Sys.bin + "launcher-roam-index", roamDir, roamIndex])
    }
    function dayOf(epoch) { return Qt.formatDateTime(new Date(epoch * 1000), "yyyy-MM-dd") }
    function loadNotes() {
        const recs = []
        for (const l of lines(readFile(roamFile, roamIndex))) {
            const f = l.split("\t")
            if (f.length < 3 || f[1] === "") continue
            recs.push({ path: f[0], title: f[1], mt: Number(f[2]) || 0 })
        }
        recs.sort((a, b) => b.mt - a.mt)                // newest first: the order for an empty query and for ties
        noteRows = recs.map((r, i) => {
            const cut = r.path.lastIndexOf("/"), stem = r.path.slice(cut + 1).replace(/\.org$/, "")
            const it = Rank.prep(r.title + "   " + stem, i)
            it.label = r.title
            it.sub = "Modified " + dayOf(r.mt) + "   " + stem
            it.two = true
            it.icon = "text-x-generic"
            it.path = r.path
            it.run = () => view.openNote(r.path)
            return it
        })
        notesLoaded = true
    }
    function openNote(path) {
        close()
        Sys.launch(["timeout", "5", "emacsclient", "-n", path])
        Sys.focusEmacs()
    }
    readonly property var noteList: {
        const ws = words(query.text.trim())
        if (noteRows.length === 0)
            return [{ label: notesCmd.busy ? "Indexing notes…" : "No notes found", sub: roamDir.replace(home, "~"), icon: "text-x-generic", info: true, run: null }]
        return (ws.length === 0 ? noteRows : Rank.ranked(noteRows, ws)).slice(0, 200)
    }

    // ---- Firefox tabs (tabs-list: the sessionstore; kept 30 s) ----
    // Firefox has no way to be told "show this tab" from outside. A tab that is the one its window
    // is showing is found by the window's title (Hyprland) and the window is focused. Any other
    // tab is opened again with `firefox URL`, which makes a new tab; the second line says which.
    property var tabRaw: []
    property double tabsAt: 0
    property bool tabsFailed: false
    function tabsEnter() {
        if (tabsAt > 0 && Date.now() - tabsAt < 30000) return
        if (!fakeWindows) Hyprland.refreshToplevels()
        tabsCmd.run([Sys.bin + "tabs-list"])
    }
    LaunchCmd {
        id: tabsCmd
        fake: view.fakeRun
        timeout: 10000
        onFinished: (out, ok) => {
            let a = []
            try { a = ok ? JSON.parse(out) : [] } catch (e) { a = []; ok = false }
            view.tabRaw = a
            view.tabsFailed = !ok
            view.tabsAt = ok ? Date.now() : 0
        }
    }
    function normSpace(s) { return String(s).replace(/\s+/g, " ").trim() }
    // the Firefox window whose title is this tab's (its window title is "PAGE TITLE — Mozilla Firefox")
    function firefoxWindowFor(tab, wins) {
        if (!tab.active || !tab.title) return null
        const t = normSpace(tab.title)
        return wins.find(w => { const wt = normSpace(w.title); return wt === t || wt.startsWith(t + " — ") || wt.startsWith(t + " - ") }) || null
    }
    readonly property var tabList: {
        if (mode !== "tabs") return []
        if (tabRaw.length === 0)
            return [{ label: tabsFailed ? "Could not read the Firefox tabs" : tabsCmd.busy ? "Reading Firefox tabs…" : "No open tabs", sub: tabsFailed ? "is Firefox running?" : "",
                      icon: "firefox", info: true, run: null }]
        const wins = toplevelList().filter(w => /firefox/i.test(w.cls)).sort((a, b) => a.focus - b.focus)
        return tabRaw.map(t => {
            const w = firefoxWindowFor(t, wins)
            const title = normSpace(t.title || t.url)
            return { label: title, sub: t.host + "   " + (w ? "goes to its window" : "opens it again in a new tab"), two: true, icon: "firefox",
                     find: (title + " " + t.host + " " + t.url).toLowerCase(),
                     run: () => view.openTab(t.url, w, wins) }
        })
    }
    function openTab(url, win, wins) {
        if (win) { focusWindow(win.address); return }
        close()
        Sys.launch(["firefox", url])
        if (wins.length > 0) focusWindow(wins[0].address)
    }

    // ---- clipboard pins ----
    // $XDG_STATE_HOME/clip-pins/: index.json [{ id, kind: "text"|"image", file, label, src (the cliphist id), t }],
    // newest first, and one file per pin (ID.txt up to 64 KB, ID.png). Outside cliphist's own store, so
    // neither its pruning nor `clip-menu clear` touches them; Enter copies from the file.
    property var pins: []
    property var pinPending: null
    property string notice: ""
    FileView { id: pinsFile; blockLoading: true; printErrors: false }
    Timer { id: noticeTimer; interval: 3500; onTriggered: view.notice = "" }
    function say(text) { notice = text; noticeTimer.restart() }
    function loadPins() {
        let a = []
        try { a = JSON.parse(readFile(pinsFile, pinDir + "/index.json")) } catch (e) { a = [] }
        // a file name from the index is used in a path: only the names this code writes
        pins = (Array.isArray(a) ? a : []).filter(p => p && /^[0-9]+\.(txt|png)$/.test(String(p.file)) && (p.kind === "text" || p.kind === "image"))
    }
    function savePins() { pinsFile.setText(JSON.stringify(pins)) }
    function pinRow(p) {
        const img = p.kind === "image"
        const row = { id: "pin:" + p.id, pin: p, glyph: "", sub: img ? "pinned image" : "pinned", label: p.label,
                      find: (p.label + " pinned").toLowerCase(), run: () => view.copyPin(p), del: () => view.unpin(p.id) }
        if (img) { row.image = true; row.thumbUrl = "file://" + pinDir + "/" + p.file }
        return row
    }
    readonly property var clipList: {
        const srcs = new Set(pins.map(p => p.src)), texts = new Set(pins.filter(p => p.kind === "text").map(p => p.label))
        return pins.map(pinRow).concat(clipRows.filter(r => !srcs.has(r.id) && !(r.image !== true && texts.has(r.label))))
    }
    function togglePin() {
        const r = current
        if (!r || mode !== "clip") return
        if (r.pin) unpin(r.pin.id)
        else if (r.id && !pinCmd.busy) {
            const img = r.image === true, stamp = String(Date.now())
            pinPending = { id: stamp, kind: img ? "image" : "text", file: stamp + (img ? ".png" : ".txt"), label: r.label, src: r.id, t: Date.now() }
            pinCmd.run([Sys.bin + "clip-pin", pinDir, pinPending.file, r.id, pinPending.kind])
        }
    }
    LaunchCmd {
        id: pinCmd
        fake: view.fakeRun
        timeout: 6000
        onFinished: (out, ok) => {
            const p = view.pinPending
            view.pinPending = null
            if (!p) return
            if (!ok) { view.say("Could not pin it (text is kept up to 64 KB)"); return }
            view.pins = [p].concat(view.pins.filter(q => q.src !== p.src))
            view.savePins()
            list.currentIndex = 0
            view.say("Pinned")
        }
    }
    function unpin(id) {
        const p = pins.find(q => q.id === id)
        if (!p) return
        const i = list.currentIndex
        pins = pins.filter(q => q.id !== id)
        savePins()
        Sys.launch(["rm", "-f", pinDir + "/" + p.file])
        list.currentIndex = Math.min(i, Math.max(0, results.length - 1))
        say("Unpinned")
    }
    function copyPin(p) {
        close()
        const f = pinDir + "/" + p.file
        Sys.launch(p.kind === "image" ? ["sh", "-c", 'wl-copy --type image/png < "$1"', "sh", f] : ["sh", "-c", 'wl-copy < "$1"', "sh", f])
    }

    // ---- QR code ("qr TEXT" in the app list) ----
    readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    property string qrFile: ""              // the picture for qrDone, once made
    property string qrAsked: ""
    property var qrDone: null               // the text the last run was for ("" -> none), and how it went:
    property bool qrOk: false
    property int qrGen: 0
    Timer { id: qrDelay; interval: 200; onTriggered: view.qrNow() }
    function qrText(q) { const m = /^qr\s+(\S[\s\S]*)$/i.exec(q); return m ? m[1] : "" }
    function qrNow() {
        const t = qrText(query.text.trim())
        if (t === "") return
        qrAsked = t
        qrGen++
        qrCmd.run(["sh", "-c", 'd=$1; mkdir -p "$d"; rm -f "$d"/launcher-qr-*.png; qrencode -o "$d/launcher-qr-$2.png" -s 8 -m 2 -- "$3"',
                   "sh", runDir, String(qrGen), t])
    }
    LaunchCmd {
        id: qrCmd
        fake: view.fakeRun
        timeout: 4000
        onFinished: (out, ok) => { view.qrOk = ok; view.qrFile = ok ? view.runDir + "/launcher-qr-" + view.qrGen + ".png" : ""; view.qrDone = view.qrAsked }
    }
    function copyQr() {
        const f = qrFile
        if (f === "") return
        qrFile = ""
        close()
        Sys.launch(["sh", "-c", 'wl-copy --type image/png < "$1"; rm -f "$1"', "sh", f])
    }
    readonly property var qrRow: {
        const t = qrText(query.text.trim())
        if (mode !== "apps" || t === "" || qrDone !== t) return null
        if (!qrOk || qrFile === "") return { label: "Too much text for one QR code", sub: "", icon: "dialog-warning", info: true, run: null }
        return { label: t.length > 60 ? t.slice(0, 59) + "…" : t, sub: "QR code   Enter copies the picture", big: true, bigUrl: "file://" + qrFile, run: () => view.copyQr() }
    }

    // ---- the list for the current mode ----
    function words(q) { return q.toLowerCase().split(/\s+/).filter(w => w !== "") }
    function filterRows(rows, ws) {
        if (ws.length === 0) return rows
        const hits = rows.filter(r => ws.every(w => Rank.has(r.find, w)))
        if (hits.length > 0) return hits
        const near = []                     // nothing as typed: allow a slip or two (fuzzy.js)
        for (const r of rows) {
            const d = Fuzzy.score(ws, Fuzzy.tokens(r.find), w => Rank.has(r.find, w))
            if (d !== -1) near.push({ r: r, d: d })
        }
        near.sort((a, b) => a.d - b.d)
        return near.map(c => c.r)
    }
    readonly property var results: {
        const q = query.text.trim()
        switch (mode) {
        case "apps": {
            const rows = appResults(q.toLowerCase()).map(appRow).concat(extraRows(q))
            return (calcNowRow ? [calcNowRow] : []).concat(qrRow ? [qrRow] : [], rows)
        }
        case "calc":
            return (calcNowRow ? [calcNowRow] : []).concat(calcHistory.map(h => calcRow(h.expr, h.result, true)))
        case "emoji": {
            if (emojiRows.length === 0) return emojiMissing
            const ws = words(q)
            return ws.length === 0 ? emojiRows : Rank.ranked(emojiRows, ws)
        }
        case "clip": return filterRows(clipList, words(q))
        case "win": return filterRows(windows, words(q))
        case "files": return fileRows
        case "keys": return filterRows(keyRows, words(q))
        case "org": return [orgRow]
        case "mail": return mailList
        case "notes": return noteList
        case "tabs": {
            const ws = words(q)
            return ws.length === 0 || tabRaw.length === 0 ? tabList : filterRows(tabList, ws)
        }
        }
        return []
    }
    function launch(mods) {
        const r = results[list.currentIndex]
        if (r && r.run) r.run(mods || 0)
    }
    readonly property string countText: {
        if (notice !== "") return notice
        if (mode === "org" || (mode === "mail" && Notif.dnd)) return ""
        const n = results.filter(r => r.info !== true).length - (mode === "apps" ? (calcNowRow ? 1 : 0) + (qrRow && qrRow.big ? 1 : 0) : 0)
        if (mode === "emoji" && emojiRows.length === 0) return ""
        return n + " " + (n === 1 ? modeInfo.one : modeInfo.many)
    }

    // ---- looks (as the plain launcher) ----
    ColumnLayout {
        anchors { fill: parent; margins: 14 }
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text { text: "›"; color: Theme.accent; font { family: Theme.font; pixelSize: 22; bold: true } }
            Rectangle {                         // which mode, when it is not apps
                visible: view.mode !== "apps"
                implicitWidth: chipText.implicitWidth + 14
                implicitHeight: 22
                radius: 6
                color: Theme.accentBg
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: view.modeInfo.chip
                    color: Theme.accentInk
                    font { family: Theme.font; pixelSize: 12; bold: true }
                }
            }
            TextInput {
                id: query
                Layout.fillWidth: true
                color: Theme.fg
                selectionColor: Theme.accentBg
                selectedTextColor: Theme.accentInk
                font { family: Theme.font; pixelSize: 17 }
                clip: true
                onTextChanged: view.typed()
                Keys.onPressed: event => {
                    const k = event.key, mods = event.modifiers
                    if (k === Qt.Key_Escape) view.close()
                    else if (k === Qt.Key_Tab) view.cycle(1)
                    else if (k === Qt.Key_Backtab) view.cycle(-1)
                    else if (k === Qt.Key_Down) list.incrementCurrentIndex()
                    else if (k === Qt.Key_Up) list.decrementCurrentIndex()
                    else if (k === Qt.Key_PageDown) list.page(1)
                    else if (k === Qt.Key_PageUp) list.page(-1)
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter) view.launch(mods)
                    else if (k === Qt.Key_Backspace && query.text === "" && view.mode !== "apps") view.setMode("apps")
                    else if (k === Qt.Key_P && (mods & Qt.ControlModifier) && view.mode === "clip") view.togglePin()
                    else if (k === Qt.Key_Delete && (mods & Qt.ShiftModifier) && view.mode === "clip") {
                        const r = view.current
                        if (r && r.del) r.del()
                    }
                    else return
                    event.accepted = true
                }
                Text {
                    visible: query.text === ""
                    text: view.modeInfo.hint
                    color: Theme.faint
                    font: query.font
                }
            }
            Caption { text: view.countText }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }
        Caption {                               // the prefixes, while nothing is typed
            // a letter prefix needs its space (v, w and o alone still search apps): say so once the letter is typed
            readonly property var letterMode: view.mode === "apps" ? (view.modes.find(m => m.prefix.length === 2 && m.prefix.charAt(0) === query.text) || null) : null
            visible: view.mode === "apps" ? (query.text === "" || letterMode !== null) : (query.text === "" && view.modeInfo.keys !== undefined)
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            textFormat: Text.StyledText
            text: view.mode !== "apps" ? (view.modeInfo.keys || "")
                : letterMode
                ? "<font color='" + Theme.accent + "'><b>Space</b></font> " + letterMode.hint.charAt(0).toLowerCase() + letterMode.hint.slice(1)
                  + "&nbsp; (or keep typing to search apps)"
                : [["=", "calc"], [":", "emoji"], ["v ␣", "clip"], ["w ␣", "windows"], ["/", "files"], ["?", "keys"], ["o ␣", "org"], ["m ␣", "mail"], ["n ␣", "notes"], ["t ␣", "tabs"], ["qr ␣", "QR code"], ["Tab", "next"]]
                    .map(p => "<font color='" + Theme.accent + "'><b>" + p[0].replace(" ", "&nbsp;") + "</b></font>&nbsp;" + p[1]).join("&nbsp; ")
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: view.results
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0
            keyNavigationWraps: true          // Down on the last row goes to the first, Up on the first to the last
            cacheBuffer: 0                    // clipboard pictures are decoded only for rows on screen
            function page(d) {
                const n = Math.max(1, Math.floor(height / 42) - 1)
                currentIndex = Math.max(0, Math.min(count - 1, currentIndex + d * n))
            }
            delegate: Rectangle {
                id: item
                required property var modelData
                required property int index
                readonly property bool sel: ListView.isCurrentItem
                readonly property bool pic: item.modelData.image === true
                readonly property bool big: item.modelData.big === true       // the QR code
                readonly property bool stack: item.modelData.two === true || big     // label above, sub below
                width: list.width
                height: big ? 236 : pic ? 92 : stack ? 54 : 42
                radius: 8
                color: sel ? Theme.accentBg : "transparent"
                Component.onCompleted: if (pic && !item.modelData.thumbUrl) view.wantThumb(item.modelData.id)
                RowLayout {
                    id: rowL
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    spacing: 12
                    IconImage {
                        visible: item.modelData.icon !== undefined
                        implicitSize: 26
                        // "" when the theme has no such icon: an empty slot, not a placeholder
                        source: item.modelData.icon ? Quickshell.iconPath(item.modelData.icon, true) : ""
                    }
                    Text {                          // an emoji or symbol
                        visible: item.modelData.glyph !== undefined
                        Layout.preferredWidth: 26
                        horizontalAlignment: Text.AlignHCenter
                        text: item.modelData.glyph || ""
                        textFormat: Text.PlainText
                        color: item.sel ? Theme.accentInk : Theme.fg
                        font { family: Theme.font; pixelSize: 22 }
                    }
                    Item {                          // a picture on the clipboard
                        visible: item.pic
                        Layout.preferredWidth: 120
                        Layout.preferredHeight: 76
                        Rectangle { anchors.fill: parent; radius: 4; color: Theme.track; visible: thumb.status !== Image.Ready }
                        Image {
                            id: thumb
                            anchors.fill: parent
                            source: item.pic ? (item.modelData.thumbUrl || view.thumbs[item.modelData.id] || "") : ""
                            asynchronous: true
                            cache: false
                            fillMode: Image.PreserveAspectFit
                            sourceSize { width: 240; height: 152 }
                        }
                    }
                    Rectangle {                     // the QR code: black on white, whatever the theme
                        visible: item.big
                        Layout.preferredWidth: 212
                        Layout.preferredHeight: 212
                        radius: 4
                        color: "white"
                        Image {
                            anchors { fill: parent; margins: 4 }
                            source: item.big ? item.modelData.bigUrl : ""
                            cache: false
                            smooth: false
                            fillMode: Image.PreserveAspectFit
                        }
                    }
                    ColumnLayout {                  // two lines: label above, sub below
                        visible: item.stack
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: item.modelData.label
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: item.sel ? Theme.accentInk : Theme.fg
                            font { family: Theme.font; pixelSize: 14 }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: item.modelData.sub || ""
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: item.sel ? Theme.accentInk : Theme.faint
                            font { family: Theme.font; pixelSize: 11 }
                        }
                    }
                    Text {
                        visible: !item.stack
                        Layout.preferredWidth: Math.min(implicitWidth, rowL.width * 0.62)
                        Layout.fillWidth: item.modelData.sub === ""
                        text: item.modelData.label
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: item.sel ? Theme.accentInk : Theme.fg
                        font { family: Theme.font; pixelSize: 14 }
                    }
                    Text {
                        visible: item.modelData.sub !== "" && !item.stack
                        Layout.fillWidth: true
                        text: item.modelData.sub || ""
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        horizontalAlignment: Text.AlignRight
                        color: item.sel ? Theme.accentInk : Theme.faint
                        font { family: Theme.font; pixelSize: 11 }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: list.currentIndex = item.index
                    onClicked: { list.currentIndex = item.index; view.launch(0) }
                }
            }
        }
    }
}
