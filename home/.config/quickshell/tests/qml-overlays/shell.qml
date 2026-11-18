// Tests for the full-screen overlays: Overview.qml (Super+Tab), Switcher.qml (Alt+Tab),
// Dashboard.qml (Super+I), CursorFind.qml, DropPreview.qml, ShotButton.qml, WallSeason.qml (with the
// real WallState's season and game-day rules), and the pet pieces no other suite reaches: PetBrief.qml
// with the real PetSay.qml, PetJournal.qml, PetSky.qml, PetAntics.qml.
// NOT part of the shell: ~/.local/bin/qml-overlays-test copies the real files next to the stubs here
// (Sys, Hyprland, Notif, Pet, PetArc, PetFocus, PetSecrets, FakeSprite), turns the layer-shell windows
// into plain windows and takes `import Quickshell.Hyprland` out, so `Hyprland` is the stub. Commands
// the overlays run are stand-ins in tests/qml-overlays/bin that answer from fixtures and record.
// Each check logs QTEST PASS or FAIL; the last line is "QTEST RESULT pass N fail M".
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    settings.watchFiles: false
    property int passed: 0
    property int failed: 0
    function check(what, ok, detail) {
        if (ok) passed++; else failed++
        console.log("QTEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
    }
    readonly property string home: Quickshell.env("HOME")
    readonly property string fix: Quickshell.env("QO_FIX")
    readonly property string callsPath: Quickshell.env("QO_CALLS")

    // ---- the things under test ----
    Overview { id: overview; implicitWidth: 1920; implicitHeight: 1080 }
    Switcher { id: switcher; implicitWidth: 1920; implicitHeight: 1080 }
    Dashboard { id: dashboard; implicitWidth: 1920; implicitHeight: 1080 }
    CursorFind { id: cursorFind; enabled: false }
    DropPreview { id: dropPreview; enabled: false }
    Fit { id: fit; roots: [overview, switcher, dashboard, petWin, journalWin, briefWin] }

    FloatingWindow {
        id: petWin
        visible: false
        implicitWidth: 600; implicitHeight: 200
        color: Theme.solidBg
        ShotButton { id: shotBtn; x: 20; y: 20; glyph: "U"; tip: "Undo  Ctrl+Z"; host: tipHost; onClicked: root.shotClicks++ }
        ShotButton { id: shotOn; x: 60; y: 20; glyph: "S"; tip: "Save"; on: true; host: tipHost }
        ShotButton { id: shotDim; x: 100; y: 20; glyph: "D"; tip: "Dim"; dim: true; host: tipHost }
        FakeSprite { id: sprite; x: 200; y: 100 }
        Item { id: skyBox; x: 0; y: 0; width: 600; height: 200; PetSky { id: petSky; anchors.fill: parent } }
    }
    QtObject { id: tipHost; property string tipNow: "" }
    property int shotClicks: 0

    FloatingWindow {
        id: journalWin
        visible: false
        implicitWidth: 290; implicitHeight: 420
        color: Theme.solidBg
        PetJournal { id: journal; width: 290; visible: false }
    }
    FloatingWindow {
        id: briefWin
        visible: false
        implicitWidth: 290; implicitHeight: 520
        color: Theme.solidBg
        PetBrief { id: brief; width: 270; x: 10 }
    }
    FloatingWindow {
        id: seasonWin
        visible: false
        implicitWidth: 1280; implicitHeight: 720
        color: "#202028"
        WallSeason { id: season; anchors.fill: parent; time: 12.5; dark: Theme.dark }
    }

    TestEvent { id: ev }

    // files the cases change behind the overlays' backs (fixtures, the theme switch)
    FileView { id: handFile; printErrors: false; blockLoading: true; blockWrites: true }
    function writeFile(path, text) { handFile.path = path; handFile.setText(text) }
    // the full fixtures, read once (the cases switch the live files between these and empty ones)
    FileView { id: fullClients; path: root.fix + "/clients.full.json"; blockLoading: true }
    FileView { id: fullFeeds; path: root.fix + "/feeds.full.json"; blockLoading: true }
    FileView { id: fullSys; path: root.fix + "/sys.full.json"; blockLoading: true }
    function readFile(path) { return path.endsWith("clients.full.json") ? fullClients.text() : path.endsWith("feeds.full.json") ? fullFeeds.text() : fullSys.text() }
    // a fresh read every time (a long-lived FileView can hand back what it read before)
    function calls() {
        const f = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', root)
        f.path = callsPath
        const t = f.text()
        f.destroy()
        return t.split("\n").filter(l => l !== "")
    }
    function setDark(d) { writeFile(home + "/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark", d ? "true\n" : "false\n"); Theme.reload(); Theme.dark = d }

    // ---- helpers ----
    function walk(item, f) {
        if (!item) return
        f(item)
        const kids = item.children || []
        for (let i = 0; i < kids.length; i++) walk(kids[i], f)
    }
    function isText(o) { return o && ("elide" in o) && ("truncated" in o) && ("contentWidth" in o) }
    // every Text shown (visible counts its parents) under an item
    function texts(item) { const out = []; walk(item, o => { if (isText(o) && o.visible && String(o.text) !== "") out.push(String(o.text)) }); return out }
    function textItem(item, pred) { let r = null; walk(item, o => { if (!r && isText(o) && o.visible && pred(String(o.text))) r = o }); return r }
    function has(list, s) { return list.some(t => t.indexOf(s) >= 0) }
    function body(w) { return w.contentItem }
    function qwin(w) { return w.contentItem ? w.contentItem.Window.window : w }
    function activate(w) { const q = qwin(w); if (q && !q.active) q.requestActivate() }
    function resize(w, width, height) {      // a shown window keeps its size unless its limits move
        w.implicitWidth = width; w.implicitHeight = height
        const q = qwin(w), z = Qt.size(width, height)
        if (q) { q.maximumWidth = 9999; q.maximumHeight = 9999; q.minimumWidth = width; q.minimumHeight = height; q.maximumWidth = width; q.maximumHeight = height }
    }
    function key(w, k, mods) { activate(w); ev.keyClick(k, mods || Qt.NoModifier, -1) }
    function click(item, x, y) {
        const w = item.Window.window
        if (w && !w.active) w.requestActivate()
        ev.mouseClick(item, x === undefined ? item.width / 2 : x, y === undefined ? item.height / 2 : y, Qt.LeftButton, Qt.NoModifier, -1)
    }
    function runs() { return Sys.calls.filter(c => c.indexOf("run ") === 0) }
    function last(list) { return list.length ? list[list.length - 1] : "" }
    function cut(win, label) {
        const r = fit.checkNow(label)
        return r.problems
    }
    property var errs: []

    // ---- fixtures for the Hyprland stub ----
    readonly property var monFix: [
        { name: "eDP-1", x: 0, y: 0, width: 1920, height: 1080, scale: 1, lastIpcObject: { transform: 0 } },
        { name: "DP-3", x: 1920, y: 0, width: 2560, height: 1440, scale: 1.25, lastIpcObject: { transform: 1 } }       // turned: 1152 x 2048
    ]
    readonly property var tlFix: [
        { address: "5600000000a0", title: "Course page — Mozilla Firefox", workspace: { id: 11 }, wayland: null, lastIpcObject: { at: [0, 0], size: [1920, 1080] } },
        { address: "0x5600000000b0", title: "lecture-07.org - Emacs", workspace: { id: 12 }, wayland: null, lastIpcObject: { at: [1920, 0], size: [1152, 1000] } },
        { address: "5600000000c0", title: "~/Code: ghostty", workspace: { id: 21 }, wayland: null, lastIpcObject: { at: [10, 10], size: [900, 1000] } },
        { address: "5600000000d0", title: "Zoom Meeting", workspace: { id: -98 }, wayland: null, lastIpcObject: { at: [100, 100], size: [800, 600] } }
    ]
    function hyprFull() {
        Hyprland.monitors.values = monFix
        Hyprland.workspaces.values = [{ id: 11 }, { id: 12 }, { id: 21 }, { id: 31 }, { id: -98 }]
        Hyprland.toplevels.values = tlFix
        Hyprland.focusedMonitor = monFix[0]
        Sys.desktop = 1
    }
    function hyprEmpty() {
        Hyprland.monitors.values = [monFix[0]]
        Hyprland.workspaces.values = []
        Hyprland.toplevels.values = []
        Hyprland.focusedMonitor = monFix[0]
        Sys.desktop = 1
    }
    function cardTitles() { return texts(body(overview)).filter(t => /^Desktop \d+$/.test(t)) }
    function cardOf(n) {
        const t = textItem(body(overview), s => s === "Desktop " + n)
        return t ? t.parent : null
    }
    function winOf(title) {
        const t = textItem(body(overview), s => s === title)
        return t ? t.parent : null
    }

    // ---- cases that draw something, run once per theme ----
    function themed(dark) {
        const tag = dark ? " (dark)" : " (light)"
        return [
            { name: "theme" + tag, run: function() { setDark(dark); return 150 } },
            { name: "overview: shows the fixture" + tag, run: function() {
                check("theme is " + (dark ? "dark" : "light") + tag, Theme.dark === dark)
                hyprFull(); Hyprland.calls = []
                overview.visible = true
                return 300
            } },
            { name: "overview: cards" + tag, run: function() {
                check("overview: open" + tag, overview.visible)
                check("overview: asks Hyprland for fresh monitors, workspaces, windows" + tag,
                      ["refreshMonitors", "refreshWorkspaces", "refreshToplevels"].every(c => Hyprland.calls.indexOf(c) >= 0), Hyprland.calls.join(","))
                check("overview: one card per desktop in use, in order" + tag, JSON.stringify(cardTitles()) === JSON.stringify(["Desktop 1", "Desktop 2", "Desktop 3"]), cardTitles().join(","))
                const t = texts(body(overview))
                check("overview: window titles shown until a frame arrives" + tag,
                      has(t, "Course page") && has(t, "lecture-07.org") && has(t, "~/Code: ghostty"), t.join(" | "))
                check("overview: the scratchpad window is on no card" + tag, !has(t, "Zoom Meeting"))
                const c1 = cardOf(1), c2 = cardOf(2)
                check("overview: the current desktop's card is outlined in the accent" + tag, c1 && Qt.colorEqual(c1.border.color, Theme.accentBg) && !Qt.colorEqual(c2.border.color, Theme.accentBg))
                // the turned DP-3 is drawn taller than wide, eDP-1 wider than tall
                const ff = winOf("Course page — Mozilla Firefox"), em = winOf("lecture-07.org - Emacs")
                const monE = ff ? ff.parent : null, monD = em ? em.parent : null
                check("overview: each window is drawn on its own screen's miniature" + tag, monE && monD && monE !== monD)
                check("overview: a turned screen is drawn upright (taller than wide)" + tag, monD && monD.height > monD.width && monE.width > monE.height,
                      monD ? monD.width + "x" + monD.height : "none")
                check("overview: a full-screen window fills its screen's miniature" + tag, ff && Math.abs(ff.width - monE.width) < 1 && Math.abs(ff.height - monE.height) < 1)
                const p = cut(overview, "overview")
                check("overview: nothing cut off at 1920x1080" + tag, p.length === 0, p.join(" ;; "))
                return 50
            } },
            { name: "overview: empty" + tag, run: function() {
                overview.visible = false
                hyprEmpty()
                overview.visible = true
                return 200
            } },
            { name: "overview: empty state" + tag, run: function() {
                check("overview: no workspaces still shows the current desktop" + tag, JSON.stringify(cardTitles()) === JSON.stringify(["Desktop 1"]), cardTitles().join(","))
                const p = cut(overview, "overview empty")
                check("overview: empty state not cut off" + tag, p.length === 0, p.join(" ;; "))
                overview.visible = false
                return 50
            } },

            { name: "switcher: open" + tag, run: function() {
                hyprFull()
                writeFile(fix + "/clients.json", readFile(fix + "/clients.full.json"))
                switcher.step(1)
                return { until: () => switcher.wins.length > 0, max: 3000 }
            } },
            { name: "switcher: cards" + tag, run: function() {
                const t = texts(body(switcher))
                check("switcher: the list is mapped windows, most recent first" + tag,
                      JSON.stringify(switcher.wins.map(w => w.address)) === JSON.stringify(["0x5600000000a0", "0x5600000000b0", "0x5600000000c0", "0x5600000000d0"]),
                      switcher.wins.map(w => w.address).join(","))
                check("switcher: desktop and scratchpad labels" + tag, JSON.stringify(switcher.wins.map(w => w.ws)) === JSON.stringify(["Desktop 1", "Desktop 1", "Desktop 2", "scratch"]),
                      switcher.wins.map(w => w.ws).join(","))
                check("switcher: titles shown" + tag, has(t, "Course page") && has(t, "lecture-07.org") && has(t, "Zoom Meeting"), t.join(" | "))
                check("switcher: each window paired with its Hyprland toplevel" + tag, switcher.wins.every(w => w.toplevel !== null))
                check("switcher: opens on the previous window" + tag, switcher.sel === 1, switcher.sel)
                const picked = textItem(body(switcher), s => s === "lecture-07.org - Emacs")
                check("switcher: the picked card's title is bold, in the accent" + tag, picked && picked.font.bold && Qt.colorEqual(picked.color, Theme.accent))
                const p = cut(switcher, "switcher")
                check("switcher: nothing cut off" + tag, p.length === 0, p.join(" ;; "))
                key(switcher, Qt.Key_Escape)
                return 100
            } },
            { name: "switcher: escape" + tag, run: function() {
                check("switcher: Escape closes without going anywhere" + tag, !switcher.visible && runs().length === 0, runs().join(" | "))
                return 20
            } },

            { name: "dashboard: open" + tag, run: function() {
                Sys.reset()
                Sys.player = Sys.fakePlayer
                Sys.today = [{ start: "08:00", end: "09:00", title: "Office hours" }, { start: "10:00", end: "11:15", title: "CPSC 2120 lecture" },
                             { start: "14:00", end: "15:00", title: "Faculty meeting" }, { allday: true, title: "Reading day" }]
                Sys.currentEvent = Sys.today[1]; Sys.nextEvent = Sys.today[2]; Sys.nowHM = "10:30"
                Notif.dnd = false
                Notif.history = [{ summary: "Build finished", app: "ghostty", body: "make: all\n done", time: "10:12", repeat: 3 },
                                 { summary: "Low disk", app: "health", critical: true, time: "09:40" }]
                writeFile(fix + "/feeds.json", readFile(fix + "/feeds.full.json"))
                writeFile(fix + "/sys.json", readFile(fix + "/sys.full.json"))
                dashboard.feeds = ({}); dashboard.sysState = ({})     // as when the shell has just started
                dashboard.visible = true
                root.loadingSeen = has(texts(body(dashboard)), "Loading...")
                return { until: () => dashboard.feeds.weather !== undefined && dashboard.sysState.cpu !== undefined, max: 3000 }
            } },
            { name: "dashboard: fixture shown" + tag, run: function() {
                const t = texts(body(dashboard))
                check("dashboard: 'Loading...' until the feeds arrive" + tag, root.loadingSeen)
                check("dashboard: three columns at 1920 px" + tag, dashboard.wide)
                check("dashboard: what is on now" + tag, has(t, "Now: CPSC 2120 lecture (until 11:15)"), t.filter(x => x.indexOf("Now") >= 0).join("|"))
                check("dashboard: weather from the feed" + tag, has(t, "64°  Clear sky") && has(t, "Sun 07:12 to 17:24") && has(t, "80% rain"))
                check("dashboard: today's events, with how many are left" + tag, has(t, "Office hours") && has(t, "Faculty meeting") && has(t, "all day") && has(t, "3 OF 4 LEFT") === false && has(t, "3 of 4 left"),
                      t.filter(x => /left|done/.test(x)).join("|"))
                const cur = textItem(body(dashboard), s => s === "CPSC 2120 lecture")
                check("dashboard: the event going on now is bold" + tag, cur && cur.font.bold)
                check("dashboard: tomorrow's card takes its name and events from the feed" + tag, has(t, "THURSDAY") && has(t, "CPSC 1010 lecture") && has(t, "2 events"))
                check("dashboard: unread counts per inbox" + tag, has(t, "Clemson") && has(t, "Gmail") && t.indexOf("3") >= 0)
                check("dashboard: newest senders and subjects (DND off)" + tag, has(t, "Dean's Office") && has(t, "Spring schedule review") && has(t, "Library"))
                check("dashboard: the machine card" + tag, has(t, "up 3h 12m   load 0.42") && has(t, "37%") && has(t, "61 °C") && has(t, "root disk") && has(t, "130 GB free"))
                check("dashboard: network and desktop line" + tag, has(t, "Wi-Fi eduroam   Desktop 1"))
                check("dashboard: notifications, repeats counted, body on one line" + tag, has(t, "Build finished  ×3") && has(t, "make: all done") && has(t, "2 recent"))
                const crit = textItem(body(dashboard), s => s === "Low disk")
                check("dashboard: a critical notification in red" + tag, crit && Qt.colorEqual(crit.color, Theme.red))
                check("dashboard: the pet card" + tag, has(t, "CUB") && has(t, "bond 3") && has(t, "Cub is watching the bar"))
                check("dashboard: the playing card" + tag, has(t, "PLAYING") && has(t, "Blue in Green") && has(t, "Miles Davis"))
                const cs = calls()
                check("dashboard: asks dashboard-data for sys and feeds" + tag, cs.indexOf("dashboard-data sys") >= 0 && cs.indexOf("dashboard-data feeds") >= 0, cs.join(","))
                check("dashboard: reads the brightness when opened" + tag, Sys.calls.indexOf("readBrightness") >= 0)
                const p = cut(dashboard, "dashboard")
                check("dashboard: nothing cut off at 1920x1080" + tag, p.length === 0, p.join(" ;; "))
                Notif.dnd = true
                return 80
            } },
            { name: "dashboard: do not disturb" + tag, run: function() {
                const t = texts(body(dashboard))
                check("dashboard: DND hides senders and subjects, keeps the counts" + tag,
                      !has(t, "Dean's Office") && !has(t, "Spring schedule review") && has(t, "Senders and subjects hidden while Do Not Disturb is on") && has(t, "Clemson"))
                check("dashboard: DND named on the machine line" + tag, has(t, "Do Not Disturb"))
                Notif.dnd = false
                resize(dashboard, 1080, 1920)
                // after it is shown: the offscreen platform puts a window being shown on the first screen
                Hyprland.focusedMonitor = monFix[1]         // the turned screen, 1152 x 2048
                return 300
            } },
            { name: "dashboard: portrait" + tag, run: function() {
                check("dashboard: one column on a portrait screen" + tag, !dashboard.wide, dashboard.width)
                const p = cut(dashboard, "dashboard portrait")
                check("dashboard: nothing cut off at 1080x1920" + tag, p.length === 0, p.join(" ;; "))
                dashboard.visible = false
                Hyprland.focusedMonitor = monFix[0]
                resize(dashboard, 1920, 1080)
                return 150
            } },
            { name: "dashboard: empty" + tag, run: function() {
                Sys.player = null
                Sys.today = []; Sys.currentEvent = null; Sys.nextEvent = null
                Notif.history = []
                writeFile(fix + "/feeds.json", JSON.stringify({ weather: { ok: false }, mail: { boxes: [], latest: [] }, tomorrow: { name: "Thursday", events: [] } }))
                writeFile(fix + "/sys.json", "{}")
                dashboard.feeds = ({}); dashboard.sysState = ({})
                dashboard.visible = true
                return { until: () => dashboard.feeds.mail !== undefined, max: 3000 }
            } },
            { name: "dashboard: empty states" + tag, run: function() {
                const t = texts(body(dashboard))
                check("dashboard: nothing on the calendar today" + tag, has(t, "Nothing else on the calendar today") && has(t, "Nothing on the calendar"))
                check("dashboard: no weather" + tag, has(t, "No weather (offline?)"))
                check("dashboard: no mail index" + tag, has(t, "No mail index"))
                check("dashboard: no notifications card, no playing card" + tag, !has(t, "NOTIFICATIONS") && !has(t, "PLAYING"))
                check("dashboard: no counts in the today/tomorrow notes" + tag, !has(t, "left") && !has(t, "events"))
                check("dashboard: empty machine data reads 0, not NaN or undefined" + tag, !has(t, "NaN") && !has(t, "undefined"), t.filter(x => /NaN|undefined/.test(x)).join("|"))
                const p = cut(dashboard, "dashboard empty")
                check("dashboard: empty state not cut off" + tag, p.length === 0, p.join(" ;; "))
                dashboard.visible = false
                return 50
            } },

            { name: "journal" + tag, run: function() {
                PetArc.calls = []
                PetArc.entries = [1, 2, 3, 4, 5, 6, 7, 8].map(i => ({ d: "2026-11-1" + i, t: "Diary line " + i + (i === 2 ? ": a long day of naps, two games of ball, and a fox at the window who would not leave" : "") }))
                PetArc.hats = []; PetFocus.doneToday = 0; PetFocus.cycle = false; PetSecrets.count = 0
                journalWin.visible = true; journal.visible = true
                return 200
            } },
            { name: "journal: shown" + tag, run: function() {
                const t = texts(journal)
                check("journal: marks the diary seen when shown" + tag, PetArc.calls.indexOf("markSeen") >= 0)
                check("journal: together, counts, tricks" + tag, has(t, "12 days, since 6 Nov") && has(t, "41, 17, 9") && has(t, "5, 3"))
                check("journal: the next milestone" + tag, has(t, "Next: a month together") && has(t, "in 18 days"))
                check("journal: six newest diary lines only" + tag, has(t, "Diary line 6") && !has(t, "Diary line 7") && has(t, "Nov 11"))
                check("journal: no focus, hats or secrets lines when there are none" + tag, !has(t, "Focus today") && !has(t, "Hats earned") && !has(t, "Secrets found"))
                PetFocus.doneToday = 2; PetFocus.cycle = true; PetFocus.round = 3
                PetArc.hats = ["crown", "grad"]; PetSecrets.count = 2; PetSecrets.summary = "2 of 12"
                return 80
            } },
            { name: "journal: optional lines" + tag, run: function() {
                const t = texts(journal)
                check("journal: focus today, round of four" + tag, has(t, "2, round 3 of 4"))
                check("journal: hats and secrets" + tag, has(t, "crown, grad") && has(t, "2 of 12"))
                const p = cut(journalWin, "journal")
                check("journal: nothing cut off at 290 px" + tag, p.length === 0, p.join(" ;; "))
                journalWin.visible = false; journal.visible = false
                return 20
            } },

            { name: "season" + tag, run: function() {
                seasonWin.visible = true
                WallState.cfg.season = true
                WallState.seasonDemo = ""
                WallState.game = null; WallState.gameNext = null; WallState.gameDemo = false
                WallState.seasonDay = new Date(2026, 9, 20)
                return 80
            } },
            { name: "season: leaves" + tag, run: function() {
                check("season: 20 Oct is leaves" + tag, WallState.seasonKind === "leaves", WallState.seasonKind)
                check("season: 16 leaves drawn" + tag, glyphs(WallState.leafGlyph || season.leafGlyph) === 16, glyphs(season.leafGlyph))
                check("season: no paw on a day without a game" + tag, !has(texts(season), "Game day"))
                WallState.game = { opponent: "Wake Forest", home: true, time: "7:30 PM" }
                return 50
            } },
            { name: "season: game day" + tag, run: function() {
                const t = texts(season)
                check("season: home game text" + tag, has(t, "Game day\nWake Forest at Clemson  7:30 PM"), t.join("|"))
                const tl = textItem(season, s => s.indexOf("Game day") === 0)
                const r = tl ? tl.mapToItem(season, 0, 0, tl.width, tl.height) : null
                check("season: the game-day mark sits inside the screen" + tag, r && r.x >= 0 && r.y >= 0 && r.x + r.width <= season.width && r.y + r.height <= season.height,
                      r ? [r.x, r.y, r.width, r.height].join(",") : "none")
                WallState.game = { opponent: "South Carolina", home: false }
                return 50
            } },
            { name: "season: away game" + tag, run: function() {
                check("season: away game, no time" + tag, has(texts(season), "Game day\nClemson at South Carolina") && !has(texts(season), "undefined"))
                WallState.game = null; WallState.gameNext = { opponent: "Furman", home: true, time: "noon" }; WallState.gameDemo = true
                return 50
            } },
            { name: "season: demo" + tag, run: function() {
                check("season: gameday demo shows the next game" + tag, has(texts(season), "Furman at Clemson  noon"))
                WallState.gameDemo = false; WallState.gameNext = null
                WallState.seasonDay = new Date(2026, 11, 25)
                return 50
            } },
            { name: "season: snow" + tag, run: function() {
                check("season: 25 Dec is snow, 24 flakes" + tag, WallState.seasonKind === "snow" && glyphs(season.flakeGlyph) === 24, WallState.seasonKind + " " + glyphs(season.flakeGlyph))
                check("season: the paw goes when the game is gone" + tag, !has(texts(season), "Game day"))
                WallState.seasonDay = new Date(2026, 3, 1)
                return 50
            } },
            { name: "season: petals" + tag, run: function() {
                check("season: 1 Apr is petals, 14 of them" + tag, WallState.seasonKind === "petals" && petals() === 14, WallState.seasonKind + " " + petals())
                check("season: petals are not leaf glyphs" + tag, glyphs(season.leafGlyph) === 0)
                WallState.seasonDay = new Date(2026, 6, 4); WallState.sunAlt = -12
                return 50
            } },
            { name: "season: fireflies" + tag, run: function() {
                check("season: a July night has fireflies" + tag, WallState.seasonKind === "fireflies", WallState.seasonKind)
                WallState.sunAlt = 30
                check("season: a July day has none" + tag, WallState.seasonKind === "", WallState.seasonKind)
                WallState.sunAlt = -30
                return 30
            } },
            { name: "season: edges" + tag, run: function() {
                const kind = (m, d) => { WallState.seasonDay = new Date(2026, m - 1, d); return WallState.seasonKind }
                const got = [kind(10, 14), kind(10, 15), kind(11, 30), kind(12, 1), kind(2, 28), kind(3, 1), kind(3, 14), kind(3, 15), kind(4, 30), kind(5, 1), kind(9, 1)]
                const want = ["", "leaves", "leaves", "snow", "snow", "", "", "petals", "petals", "", ""]
                check("season: first and last days of each season" + tag, JSON.stringify(got) === JSON.stringify(want), got.join(","))
                WallState.seasonDemo = "snow"
                const demo = WallState.seasonKind
                WallState.seasonDemo = "none"
                const none = WallState.seasonKind
                WallState.seasonDemo = ""
                WallState.cfg.season = false
                WallState.game = { opponent: "Furman", home: true }
                check("season: a demo kind wins, 'none' shows nothing" + tag, demo === "snow" && none === "", demo + "/" + none)
                check("season: the season effect off: nothing, not even the game" + tag, WallState.seasonKind === "" && WallState.gameShown === null)
                return 50
            } },
            { name: "season: off" + tag, run: function() {
                check("season: effect off draws nothing" + tag, texts(season).length === 0 && petals() === 0, texts(season).join("|"))
                WallState.cfg.season = true; WallState.game = null
                seasonWin.visible = false
                return 20
            } },
        ]
    }
    function glyphs(g) { let n = 0; walk(season, o => { if (isText(o) && o.visible && o.text === g) n++ }); return n }
    function petals() { let n = 0; walk(season, o => { if (!isText(o) && o.visible && o.radius !== undefined && o.width > 0 && o.height > 0 && Math.abs(o.radius - o.height / 2) < 0.01 && o.width > o.height && o.parent && o.parent.parent === season) n++ }); return n }
    property bool loadingSeen: false
    property int feedRuns: 0

    // ---- cases that act, run once ----
    readonly property var actions: [
        { name: "overview: keys and clicks", run: function() {
            setDark(true)
            hyprFull()
            Sys.reset()
            overview.visible = true
            return 250
        } },
        { name: "overview: number key", run: function() {
            key(overview, Qt.Key_2)
            check("overview: '2' goes to desktop 2 and closes", Sys.calls.indexOf("goDesktop 2") >= 0 && !overview.visible, Sys.calls.join(","))
            Sys.reset(); overview.visible = true
            return 200
        } },
        { name: "overview: click a window", run: function() {
            const w = winOf("lecture-07.org - Emacs")
            check("overview: window found to click", w !== null)
            if (w) click(w)
            check("overview: a click on a window focuses it by address (0x added once)",
                  last(runs()) === "run hyprctl dispatch 'hl.dsp.focus({ window = \"address:0x5600000000b0\" })'" && !overview.visible, last(runs()))
            Sys.reset(); overview.visible = true
            return 200
        } },
        { name: "overview: click a bare address", run: function() {
            const w = winOf("Course page — Mozilla Firefox")
            if (w) click(w)
            check("overview: a bare address gets its 0x", last(runs()).indexOf("address:0x5600000000a0") >= 0, last(runs()))
            Sys.reset(); overview.visible = true
            return 200
        } },
        { name: "overview: click a card", run: function() {
            const c = cardOf(3)
            if (c) click(c, 30, 12)
            check("overview: a click on a card's title goes to that desktop", Sys.calls.indexOf("goDesktop 3") >= 0 && !overview.visible, Sys.calls.join(","))
            Sys.reset(); overview.visible = true
            return 200
        } },
        { name: "overview: backdrop and escape", run: function() {
            click(body(overview), 5, 5)
            check("overview: a click on the backdrop closes, goes nowhere", !overview.visible && Sys.calls.length === 0, Sys.calls.join(","))
            overview.visible = true
            return 200
        } },
        { name: "overview: escape", run: function() {
            key(overview, Qt.Key_Escape)
            check("overview: Escape closes", !overview.visible)
            overview.toggle()
            check("overview: toggle opens", overview.visible)
            overview.toggle()
            check("overview: toggle closes", !overview.visible)
            return 50
        } },

        // switcher: Alt+Tab is `qs ipc call switcher next` then commit on Alt let go (or Alt key release)
        { name: "switcher: quick alt+tab", run: function() {
            Sys.reset()
            switcher.step(1)
            switcher.commit()           // Alt let go before the list arrived
            check("switcher: a commit before the list arrives waits", switcher.commitWaiting && runs().length === 0)
            return { until: () => !switcher.visible, max: 3000 }
        } },
        { name: "switcher: quick alt+tab lands", run: function() {
            check("switcher: quick Alt+Tab flips to the previous window",
                  JSON.stringify(runs()) === JSON.stringify(["run sleep 0.05; hyprctl dispatch 'hl.dsp.focus({ window = \"address:0x5600000000b0\" })'"]), runs().join(" | "))
            check("switcher: asks hyprctl for the clients", calls().indexOf("hyprctl clients -j") >= 0)
            Sys.reset()
            switcher.step(-1)
            return { until: () => switcher.wins.length > 0, max: 3000 }
        } },
        { name: "switcher: shift+tab opens at the end", run: function() {
            check("switcher: Shift+Tab first opens on the oldest window", switcher.sel === 3, switcher.sel)
            switcher.step(1)
            check("switcher: next wraps from the last to the first", switcher.sel === 0, switcher.sel)
            switcher.step(-1)
            check("switcher: prev wraps from the first to the last", switcher.sel === 3, switcher.sel)
            for (let i = 0; i < 4; i++) switcher.step(1)
            check("switcher: a full round comes back to the same window", switcher.sel === 3, switcher.sel)
            activate(switcher)
            ev.keyClick(Qt.Key_Left, Qt.NoModifier, -1)
            check("switcher: Left arrow steps back", switcher.sel === 2, switcher.sel)
            ev.keyClick(Qt.Key_Right, Qt.NoModifier, -1)
            ev.keyClick(Qt.Key_Down, Qt.NoModifier, -1)
            check("switcher: Right/Down step on (wrapping)", switcher.sel === 0, switcher.sel)
            ev.keyPress(Qt.Key_Alt, Qt.AltModifier, -1)
            ev.keyRelease(Qt.Key_Alt, Qt.NoModifier, -1)
            return 100
        } },
        { name: "switcher: alt release", run: function() {
            check("switcher: letting go of Alt goes to the picked window",
                  !switcher.visible && last(runs()).indexOf("address:0x5600000000a0") >= 0, runs().join(" | "))
            Sys.reset()
            switcher.step(1)
            return { until: () => switcher.wins.length > 0, max: 3000 }
        } },
        { name: "switcher: click and enter", run: function() {
            let card = textItem(body(switcher), s => s === "Zoom Meeting")
            while (card && card.width < 200) card = card.parent
            if (card) click(card)
            check("switcher: a click picks that window", !switcher.visible && last(runs()).indexOf("address:0x5600000000d0") >= 0, runs().join(" | "))
            Sys.reset()
            switcher.step(1)
            return { until: () => switcher.wins.length > 0, max: 3000 }
        } },
        { name: "switcher: enter", run: function() {
            switcher.step(1)
            key(switcher, Qt.Key_Return)
            check("switcher: Enter picks the selected one", !switcher.visible && last(runs()).indexOf("address:0x5600000000c0") >= 0, runs().join(" | "))
            switcher.commit()
            check("switcher: a stray commit while closed does nothing", runs().length === 1)
            Sys.reset()
            writeFile(fix + "/clients.json", JSON.stringify([{ address: "0x1", mapped: false, workspace: { id: 11 }, title: "x", class: "x" }]))
            switcher.step(1)
            switcher.commit()
            return 600
        } },
        { name: "switcher: no windows", run: function() {
            check("switcher: no windows: it closes again, nothing focused", !switcher.visible && runs().length === 0, runs().join(" | "))
            writeFile(fix + "/clients.json", readFile(fix + "/clients.full.json"))
            return 20
        } },
        { name: "switcher: many windows", run: function() {
            const many = []
            for (let i = 0; i < 14; i++) many.push({ address: "0x7" + i, mapped: true, workspace: { id: 11 + (i % 3) }, title: "Window number " + i + " with a fairly long title to elide", class: "firefox", focusHistoryID: i })
            writeFile(fix + "/clients.json", JSON.stringify(many))
            Sys.reset()
            switcher.step(-1)
            return { until: () => switcher.wins.length === 14, max: 3000 }
        } },
        { name: "switcher: many windows fit", run: function() {
            check("switcher: 14 windows listed", switcher.wins.length === 14)
            return 300      // the scroll animation
        } },
        { name: "switcher: scrolls to the picked card", run: function() {
            let flick = null
            walk(body(switcher), o => { if (!flick && o.contentX !== undefined && o.flickableDirection !== undefined) flick = o })
            check("switcher: the strip scrolls to keep the picked (last) card in view", flick && flick.contentX > 0 && flick.contentX <= flick.contentWidth - flick.width + 1,
                  flick ? flick.contentX + "/" + flick.contentWidth : "no flick")
            const p = cut(switcher, "switcher many")
            check("switcher: 14 windows: nothing cut off (strip scrolls)", p.length === 0, p.join(" ;; "))
            key(switcher, Qt.Key_Escape)
            writeFile(fix + "/clients.json", readFile(fix + "/clients.full.json"))
            return 50
        } },

        { name: "dashboard: keys", run: function() {
            Sys.reset()
            Sys.player = Sys.fakePlayer
            Sys.fakePlayer.isPlaying = true
            Pet.calls = []
            writeFile(fix + "/feeds.json", readFile(fix + "/feeds.full.json"))
            dashboard.visible = true
            return 300
        } },
        { name: "dashboard: space and pet buttons", run: function() {
            key(dashboard, Qt.Key_Space)
            check("dashboard: Space plays/pauses the player", Sys.calls.indexOf("player toggle") >= 0 && dashboard.visible, Sys.calls.join(","))
            for (const label of ["Pet", "Feed", "Play"]) {
                const b = textItem(body(dashboard), s => s === label)
                if (b) click(b.parent)
            }
            check("dashboard: the pet card's buttons pat, feed and play", JSON.stringify(Pet.calls) === JSON.stringify(["petIt", "giveFood", "playWith"]), Pet.calls.join(","))
            const card = textItem(body(dashboard), s => s === "UNREAD MAIL")
            if (card) click(card)
            check("dashboard: a click on a card does not close it", dashboard.visible)
            key(dashboard, Qt.Key_Q)
            check("dashboard: Q closes", !dashboard.visible)
            dashboard.peek()
            check("dashboard: peek shows it without the keyboard grab", dashboard.visible && dashboard.grab === false)
            dashboard.visible = false
            check("dashboard: closing restores the grab for next time", dashboard.grab === true)
            dashboard.toggle()
            return 200
        } },
        { name: "dashboard: escape and backdrop", run: function() {
            key(dashboard, Qt.Key_Escape)
            check("dashboard: Escape closes", !dashboard.visible)
            dashboard.visible = true
            click(body(dashboard), 3, 3)
            check("dashboard: a click on the backdrop closes", !dashboard.visible)
            Sys.player = null
            return 50
        } },

        // ShotButton: tip shown through the host, click signal, on/dim colours
        { name: "shot button", run: function() {
            setDark(true)
            petWin.visible = true
            return 150
        } },
        { name: "shot button: hover and click", run: function() {
            ev.mouseMove(shotBtn, 15, 15, 0, Qt.NoButton, Qt.NoModifier)
            check("shot button: hover shows its tip through the host", tipHost.tipNow === "Undo  Ctrl+Z", tipHost.tipNow)
            check("shot button: hover colour", Qt.colorEqual(shotBtn.color, Theme.hover))
            ev.mouseMove(shotDim, 15, 15, 0, Qt.NoButton, Qt.NoModifier)
            check("shot button: moving to another button shows that tip", tipHost.tipNow === "Dim", tipHost.tipNow)
            ev.mouseMove(petWin.contentItem, 590, 190, 0, Qt.NoButton, Qt.NoModifier)
            check("shot button: leaving clears the tip", tipHost.tipNow === "", tipHost.tipNow)
            click(shotBtn)
            check("shot button: click emits clicked once", root.shotClicks === 1, root.shotClicks)
            const onText = textItem(shotOn, s => s === "S"), dimText = textItem(shotDim, s => s === "D")
            check("shot button: 'on' is an accent fill with dark ink", Qt.colorEqual(shotOn.color, Theme.accentBg) && onText && Qt.colorEqual(onText.color, Theme.accentInk))
            check("shot button: 'dim' greys its glyph", dimText && Qt.colorEqual(dimText.color, Theme.dim))
            check("shot button: 30 px square", shotBtn.width === 30 && shotBtn.height === 30)
            ev.mouseMove(petWin.contentItem, 590, 190, 0, Qt.NoButton, Qt.NoModifier)
            ev.mouseMove(shotBtn, 15, 15, 0, Qt.NoButton, Qt.NoModifier)
            tipHost.tipNow = "Other"            // another button's tip took over meanwhile
            ev.mouseMove(petWin.contentItem, 590, 190, 0, Qt.NoButton, Qt.NoModifier)
            check("shot button: leaving leaves another button's tip alone", tipHost.tipNow === "Other", tipHost.tipNow)
            return 20
        } },

        // PetSky: the shooting star and the saucer, from PetSecrets.sky / skyT
        { name: "pet sky", run: function() {
            PetSecrets.sky = ""
            check("pet sky: nothing drawn when the sky is empty", !petSky.visible)
            PetSecrets.sky = "star"; PetSecrets.skyT = 0.5; PetSecrets.skyLtr = true; PetSecrets.skyY = 0.2
            const kids = petSky.children
            const star = kids[0], ufo = kids[1]
            check("pet sky: star shown, saucer hidden", petSky.visible && star.visible && !ufo.visible)
            check("pet sky: star at its place along the streak (left to right)", Math.abs(star.x - (60 + 600 * (0.2 + 0.18))) < 0.5 && Math.abs(star.y - 200 * (0.2 + 0.07)) < 0.5, star.x + "," + star.y)
            check("pet sky: brightest halfway", Math.abs(star.opacity - 1) < 0.001)
            PetSecrets.skyLtr = false
            check("pet sky: right to left mirrors it", Math.abs(star.x - (540 - 600 * 0.38)) < 0.5 && star.rotation === 159, star.x)
            PetSecrets.sky = "ufo"; PetSecrets.skyT = 0.25; PetSecrets.skyLtr = true
            check("pet sky: saucer shown, star hidden", ufo.visible && !star.visible)
            check("pet sky: saucer crosses with t", Math.abs(ufo.x - ((600 + 120) * 0.25 - 60)) < 0.5, ufo.x)
            PetSecrets.sky = ""; PetSecrets.skyT = 0
            check("pet sky: gone again", !petSky.visible)
            return 20
        } },

        // PetAntics on a stand-in sprite
        { name: "antics: dizzy", run: function() {
            const a = sprite.antics
            PetSecrets.foundList = []; sprite.calls = []
            let tenth = false
            for (let i = 0; i < 10; i++) tenth = a.tapped()
            check("antics: the tenth quick pat makes it dizzy", tenth && a.act === "dizzy" && sprite.bubble === "@_@" && sprite.busy, a.act + " " + sprite.bubble)
            check("antics: dizzy counts as found", PetSecrets.foundList.indexOf("dizzy") >= 0)
            check("antics: a pat while dizzy is just a pat", a.tapped() === false)
            return { until: () => sprite.upside, max: 2500 }
        } },
        { name: "antics: dizzy falls over", run: function() {
            check("antics: after spinning it lies on its back", sprite.upside && sprite.frame === sprite.fLoaf)
            return { until: () => !sprite.busy, max: 5000 }
        } },
        { name: "antics: dizzy ends", run: function() {
            check("antics: dizzy ends by itself, upright", sprite.calls.indexOf("endBusy") >= 0 && !sprite.upside && sprite.bubble === "" && sprite.antics.act === "")
            const a = sprite.antics
            sprite.calls = []
            check("antics: dropped away from any pill is not an antic", a.dropped(100) === false && a.act === "")
            check("antics: dropped on the bell rings it", a.dropped(315) === true && a.act === "bell" && sprite.bubble === "ding!" && sprite.calls.indexOf("rang") >= 0 && sprite.atop)
            check("antics: centred on the bell", sprite.x === Math.round(315 - 16), sprite.x)
            sprite.busy = false     // a pat ends it
            check("antics: whatever ends the busy spell ends the antic", a.act === "" && !sprite.atop)
            check("antics: dropped on the clock sits on it", a.dropped(450) === true && a.act === "clock" && sprite.weigh && sprite.atop && sprite.frame === sprite.fSit)
            sprite.busy = false
            check("antics: let go: the clock comes back up", !sprite.weigh && !sprite.atop)
            return 20
        } },
        { name: "antics: doze", run: function() {
            const a = sprite.antics
            a.dozeMs = 600
            sprite.busy = false; sprite.mood = "idle"; sprite.hovered = true
            return { until: () => a.dozing, max: 3000 }
        } },
        { name: "antics: wakes", run: function() {
            const a = sprite.antics
            check("antics: the pointer resting on it sends it to sleep", a.dozing && a.act === "doze" && sprite.bubble === "z" && sprite.frame === sprite.fSleep)
            check("antics: doze counts as found", PetSecrets.foundList.indexOf("doze") >= 0)
            sprite.hovered = false
            a.stir()
            check("antics: a pointer move wakes it with a start", !a.dozing && sprite.bubble === "!" && sprite.frame === sprite.fBlink)
            return { until: () => !sprite.busy, max: 2000 }
        } },
        { name: "antics: sky", run: function() {
            const a = sprite.antics
            a.dozeMs = 60000
            check("antics: after waking, it is done", a.act === "" && sprite.calls.indexOf("endBusy") >= 0)
            Pet.calm = true
            PetSecrets.sky = "star"
            check("antics: a calm pet ignores the sky", a.act === "")
            PetSecrets.sky = ""; Pet.calm = false
            PetSecrets.sky = "star"
            check("antics: a shooting star: it sits and watches", a.act === "star" && sprite.bubble === "★" && sprite.busy)
            sprite.busy = false
            PetSecrets.sky = ""
            sprite.kind = ({ shell: true })
            PetSecrets.sky = "ufo"
            check("antics: a saucer: the turtle hides in its shell", a.act === "ufo" && sprite.bubble === "!" && sprite.frame === sprite.fPounce)
            sprite.busy = false; PetSecrets.sky = ""; sprite.kind = ({ shell: false })
            sprite.mood = "asleep"
            PetSecrets.touchdown()
            check("antics: asleep, a touchdown is missed", a.act === "")
            sprite.mood = "idle"
            PetSecrets.touchdown()
            check("antics: a touchdown: paw and cheer", a.act === "td" && sprite.bubble.indexOf("!") > 0 && PetSecrets.foundList.indexOf("touchdown") >= 0)
            return { until: () => sprite.calls.some(c => c.indexOf("patted") === 0), max: 3000 }
        } },
        { name: "antics: fire and sulk", run: function() {
            const a = sprite.antics
            check("antics: after the touchdown it is patted with a heart", sprite.calls.indexOf("patted ♥") >= 0, sprite.calls.join(","))
            sprite.busy = false
            PetSecrets.act("fire")
            check("antics: 'fire' from a script: flame drawn", a.act === "fire" && a.fire && sprite.frame === sprite.fGroom)
            let flame = null
            for (let i = 0; i < a.children.length; i++) if (a.children[i].visible && a.children[i].children.length === 3) flame = a.children[i]
            check("antics: the flame is shown at the mouth", flame !== null)
            sprite.busy = false
            check("antics: interrupted, the flame goes out", !a.fire)
            PetSecrets.foundList = []
            PetSecrets.offended = true
            Pet.name = "Cat"
            return 200
        } },
        { name: "antics: sulk", run: function() {
            const a = sprite.antics
            check("antics: named after its kind, it sulks", a.act === "sulk" && sprite.bubble === "..." && PetSecrets.foundList.indexOf("species") >= 0, a.act + " " + sprite.bubble)
            sprite.busy = false
            PetSecrets.offended = false; Pet.name = "Cub"
            PetSecrets.clemson = true
            sprite.walking = true
            sprite.x = 10; sprite.x = 60; sprite.x = 62; sprite.x = 120
            check("antics: a Clemson name leaves paw prints as it walks (not every pixel)", a.prints.length === 3, a.prints.length)
            check("antics: paw prints count as found", PetSecrets.foundList.indexOf("clemson") >= 0)
            sprite.walking = false; PetSecrets.clemson = false
            return { until: () => a.prints.length === 0, max: 4000 }
        } },
        { name: "antics: prints fade", run: function() {
            check("antics: paw prints fade away", sprite.antics.prints.length === 0)
            petWin.visible = false
            return 20
        } },

        // PetBrief with the real PetSay, fed by the dashboard-data stand-in
        { name: "brief: open", run: function() {
            setDark(true)
            writeFile(fix + "/feeds.json", readFile(fix + "/feeds.full.json"))
            writeFile(fix + "/sys.json", readFile(fix + "/sys.full.json"))
            Sys.today = [{ start: "10:00", end: "11:15", title: "CPSC 2120 lecture" }, { start: "14:00", end: "15:00", title: "Faculty meeting" },
                         { start: "16:00", end: "16:30", title: "Advising" }, { allday: true, title: "Reading day" }]
            Sys.currentEvent = Sys.today[0]; Sys.nextEvent = Sys.today[1]; Sys.nowHM = "10:30"
            Sys.netKind = "wifi"
            Notif.dnd = false; Notif.unseen = 2
            root.feedRuns = calls().filter(c => c === "dashboard-data feeds").length
            briefWin.visible = true
            brief.open = true
            return { until: () => PetSay.feedsAt > 0 && PetSay.sysAt > 0, max: 3000 }
        } },
        { name: "brief: the briefing", run: function() {
            const t = texts(brief)
            check("brief: headline: nothing wrong", has(t, "Nothing is wrong"), t[0])
            check("brief: now and next, with how long", has(t, "Now: CPSC 2120 lecture, until 11:15") && has(t, "Faculty meeting in 3 h 30 min (14:00)"), t.join(" | "))
            check("brief: then N more, and the all-day ones", has(t, "then 1 more today") && has(t, "All day: Reading day"))
            check("brief: unread mail per inbox, newest sender", has(t, "Unread mail: Clemson 3, Gmail 0") && has(t, "Dean's Office: Spring schedule review"))
            check("brief: notifications", has(t, "2 unread notifications"))
            check("brief: weather in a few words", has(t, "64° and clear sky") && has(t, "Today 41° to 66°"))
            PetSay.refresh()
            const n = calls().filter(c => c === "dashboard-data feeds").length
            check("brief: asking again within a minute does not run dashboard-data again", n === root.feedRuns + 1, n + " vs " + root.feedRuns)
            const p = cut(briefWin, "brief")
            check("brief: nothing cut off at 290 px", p.length === 0, p.join(" ;; "))
            Notif.dnd = true
            Sys.netKind = "offline"
            writeFile(fix + "/sys.json", JSON.stringify({ disks: [{ name: "home", used: 0.95, free_gb: 12 }], mem: 0.5, temp: 60 }))
            PetSay.sysAt = 0
            PetSay.refresh()
            return { until: () => PetSay.sysState.disks && PetSay.sysState.disks[0].name === "home" && PetSay.sysState.disks.length === 1, max: 3000 }
        } },
        { name: "brief: something wrong", run: function() {
            const t = texts(brief)
            check("brief: headline counts what is wrong", has(t, "2 things to look at"), t[0])
            const head = textItem(brief, s => s.indexOf("things to look at") > 0)
            check("brief: the headline turns red", head && Qt.colorEqual(head.color, Theme.red))
            check("brief: what is wrong comes first", PetSay.items[0].bad && PetSay.items[1].bad && PetSay.items[0].text === "Offline: no network" && PetSay.items[1].text.indexOf("home disk 95% full, 12 GB free") === 0,
                  PetSay.items.slice(0, 2).map(i => i.text).join(" | "))
            check("brief: DND hides mail senders", !has(t, "Dean's Office") && has(t, "Senders hidden while Do Not Disturb is on"))
            check("brief: DND named on the notifications line", has(t, "Do Not Disturb on"))
            const p = cut(briefWin, "brief wrong")
            check("brief: long lines wrap, nothing cut off", p.length === 0, p.join(" ;; "))
            brief.open = false
            return 50
        } },
        { name: "brief: closed and empty", run: function() {
            check("brief: closed page draws no lines", !brief.visible && texts(brief).length === 0)
            Sys.netKind = "wifi"; Notif.dnd = false; Notif.unseen = 0
            Sys.today = []; Sys.currentEvent = null; Sys.nextEvent = null
            PetSay.feeds = ({ mail: { boxes: [], latest: [] } }); PetSay.sysState = ({})
            brief.open = true
            return 50
        } },
        { name: "brief: empty", run: function() {
            const t = texts(brief)
            check("brief: empty day", has(t, "Nothing more today") && has(t, "Mail: no mail index") && has(t, "No new notifications") && !has(t, "undefined"), t.join(" | "))
            brief.open = false; briefWin.visible = false
            return 20
        } },

        // CursorFind and DropPreview, fed by stand-in scripts on a two-screen layout
        { name: "cursor find: start", run: function() {
            cursorFind.enabled = true
            // the second shake line (the pointer moved on) comes once the window is up
            return { until: () => cursorFind.shaking && cursorFind.px === 2401, max: 3000 }
        } },
        { name: "cursor find: shaking", run: function() {
            const win = cursorWin()
            check("cursor find: a shake line shows the big pointer", cursorFind.shaking && win && win.visible)
            check("cursor find: on the screen under the pointer", win && win.screen && win.screen.name === "DP-3", win && win.screen ? win.screen.name : "none")
            return 400
        } },
        { name: "cursor find: placed", run: function() {
            const win = cursorWin(), arrow = win ? win.contentItem.children[0] : null
            check("cursor find: grown to full size", arrow && Math.abs(arrow.size - 150) < 0.5, arrow ? arrow.size : "none")
            check("cursor find: tip at the pointer, in that screen's coordinates",
                  arrow && Math.abs(arrow.x - (2401 - 1920 - 150 * 15 / 96)) < 0.5 && Math.abs(arrow.y - (500 - 150 * 5 / 96)) < 0.5, arrow ? arrow.x + "," + arrow.y : "")
            check("cursor find: the big arrow image loads", arrow && arrow.status === Image.Ready)
            check("cursor find: clicks pass through (empty mask)", win && win.mask !== null)
            return { until: () => !cursorFind.shaking, max: 3000 }
        } },
        { name: "cursor find: stops", run: function() {
            check("cursor find: any other line ends it", !cursorFind.shaking)
            return { until: () => !cursorWin().visible, max: 2000 }
        } },
        { name: "cursor find: hidden", run: function() {
            check("cursor find: the window goes once the arrow has shrunk", !cursorWin().visible)
            cursorFind.flash(100, 200)
            check("cursor find: flash (ipc) shows it at a point on the first screen", cursorFind.shaking && cursorWin().screen.name === "eDP-1", cursorWin().screen ? cursorWin().screen.name : "")
            cursorFind.enabled = false
            return { until: () => !cursorFind.shaking, max: 2000 }
        } },
        { name: "cursor find: off", run: function() {
            check("cursor find: turned off, the script stops and the pointer goes", !cursorFind.shaking)
            dropPreview.enabled = true
            return { until: () => dropPreview.active && dropPreview.zone.width === 1200, max: 3000 }
        } },
        { name: "drop preview: zone", run: function() {
            const win = dropWin()
            check("drop preview: a Z line shows the outline", dropPreview.active && win && win.visible)
            check("drop preview: zone parsed", dropPreview.zone.x === 1980 && dropPreview.zone.y === 40 && dropPreview.zone.width === 1200 && dropPreview.zone.height === 700,
                  JSON.stringify(dropPreview.zone))
            check("drop preview: on the screen holding the zone's centre", win && win.screen && win.screen.name === "DP-3")
            return 300
        } },
        { name: "drop preview: placed", run: function() {
            const box = dropWin().contentItem.children[0]
            check("drop preview: outline in that screen's coordinates", box && Math.abs(box.x - 60) < 0.5 && Math.abs(box.y - 40) < 0.5 && box.width === 1200, box ? box.x + "," + box.y + " " + box.width : "")
            check("drop preview: accent outline", box && Qt.colorEqual(box.border.color, Theme.accentBg) && box.border.width === 3)
            return { until: () => !dropPreview.active, max: 3000 }
        } },
        { name: "drop preview: gone", run: function() {
            check("drop preview: any other line hides it", !dropPreview.active)
            return { until: () => !dropWin().visible, max: 2000 }
        } },
        { name: "drop preview: off", run: function() {
            check("drop preview: the window goes after the fade", !dropWin().visible)
            dropPreview.enabled = false
            const cs = calls()
            check("drop preview / cursor find: the stand-in scripts were the ones run", cs.indexOf("cursor-shake ") >= 0 && cs.indexOf("drop-preview ") >= 0, cs.join(","))
            return 20
        } },
    ]
    function innerWin(scope) { return scope.testWin }      // the runner adds `testWin: win` to the copies
    function cursorWin() { return innerWin(cursorFind) }
    function dropWin() { return innerWin(dropPreview) }

    property var cases: themed(true).concat(themed(false)).concat(actions)
    property int at: 0
    property var waiting: null
    property double waitUntil: 0
    Timer {
        id: tick
        interval: 600; running: true
        onTriggered: {
            if (root.waiting) {
                let ok = false
                try { ok = root.waiting() } catch (e) { ok = false }
                if (!ok && Date.now() < root.waitUntil) { interval = 40; restart(); return }
                if (!ok) console.log("QTEST note: waited in vain before " + (root.at < root.cases.length ? root.cases[root.at].name : "the end"))
                root.waiting = null
            }
            if (root.at >= root.cases.length) {
                console.log("QTEST RESULT pass " + root.passed + " fail " + root.failed)
                done.start()
                return
            }
            const c = root.cases[root.at++]
            console.log("QTEST case: " + c.name)
            let wait = 100
            try { wait = c.run() } catch (e) { root.failed++; console.log("QTEST FAIL " + c.name + " threw: " + e + " " + e.stack) }
            if (wait && typeof wait === "object") { root.waiting = wait.until; root.waitUntil = Date.now() + wait.max; interval = 40 }
            else interval = Math.max(20, wait || 100)
            restart()
        }
    }
    Timer { id: done; interval: 300; onTriggered: Qt.quit() }
}
