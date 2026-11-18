//@ pragma IconTheme Papirus-Dark
// Tests for the launcher with modes (Launcher.qml + LaunchView.qml) and for the pick list
// after its ranked search moved to rank.js. NOT part of the shell: ~/.local/bin/launcher-test
// copies the real files next to this one (Launcher.qml and Picker.qml as plain windows,
// RefLauncher.qml / RefPicker.qml = the versions before the modes, from ref/), with the stub
// Sys, and runs it offscreen. Commands get made-up answers from fakeRun below; nothing is
// launched (Sys records it). Each case logs PASS or FAIL; the last line is
// "LTEST RESULT pass N fail M". Pictures go to $LAUNCHER_TEST_OUT if set.
// The cases from "new prefixes" to "providers" cover mail, notes, tabs, clipboard pins, the QR row and
// the providers hook (they use the fake mu / tabs-list / launcher-roam-index / clip-pin answers above,
// and a real qrencode for the picture of the code).
//
// Adding a case: append { name, run } to `cases`; `run` does its keys and checks and returns
// how many milliseconds to wait before the next case.
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property int passed: 0
    property int failed: 0
    function check(what, ok, detail) {
        if (ok) passed++; else failed++
        console.log("LTEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
    }
    function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }

    readonly property string home: Quickshell.env("HOME")
    readonly property string state: Quickshell.env("XDG_STATE_HOME")
    readonly property string cache: Quickshell.env("XDG_CACHE_HOME")
    readonly property string picDir: Quickshell.env("LAUNCHER_TEST_OUT")

    // ---- made-up command output ----
    property var ran: []                // every argv the fake runner was given
    function ranOf(name) { return ran.filter(a => a[0] === name || (a[0] === "sh" && a.indexOf(name) !== -1)) }
    readonly property var calcAnswers: ({ "2+2": "4", "2*(3+4)": "14", "sqrt(2)": "1.414213562", "10 km to mi": "6.213711922 mi", "2+": "2" })
    readonly property string clipList: "12\thello world   with spaces\n42\t[[ binary data 3 KiB png 64x40 ]]\n7\tsecond entry  \n"
    property bool clipEmpty: false          // cliphist wiped
    property string clipExtra: ""           // more cliphist lines
    property var muOut: undefined           // `mu find` answer: undefined = the made-up mail, "" = none, null = fails
    readonly property string mailOut: "2026-11-14 09:12\tAda Lovelace <ada@example.org>\tQuarterly budget review\tid1@example.org\n"
        + "2026-11-13 22:05\t\"Grace Hopper\" <grace@example.org>\tLab 5 grades\tid2@example.org\n"
        + "2026-11-13 17:40\tbob@example.org\t\tid3@example.org\n"
    readonly property string roamIndexText: "/n/roam/10-literature/rubric.org\tGrading rubric ideas\t1794664880\n"
        + "/n/roam/20-permanent/budget.org\tBudget meeting notes\t1794000000\n/n/roam/00-fleeting/rec.org\tZettel on recursion\t1790000000\n"
    property bool tabsFail: false
    readonly property var tabsJson: [
        { title: "Example A", url: "https://example.org/a", host: "example.org", window: 1, index: 1, active: false, pinned: false },
        { title: "Docs X", url: "https://www.docs.test/x", host: "docs.test", window: 1, index: 2, active: true, pinned: true },
        { title: "", url: "https://news.test/", host: "news.test", window: 2, index: 2, active: true, pinned: false }
    ]
    property bool qrFail: false
    property var seenQ: []
    readonly property var binds: [
        { modmask: 64, key: "D", description: "App launcher" },
        { modmask: 65, key: "left", description: "Move window left" },
        { modmask: 64, key: "Return", description: "Terminal" },
        { modmask: 0, key: "Print", description: "Screenshot of an area" },
        { modmask: 12, key: "XF86AudioMute", description: "Mute" },
        { modmask: 64, key: "Q", description: "" },
        { modmask: 64, key: "mouse:272", description: "Move window with the mouse" }
    ]
    function fakeRun(argv) {
        ran = ran.concat([argv])
        if (argv[0] === "qalc") return calcAnswers[argv[2]] ?? "0"
        if (argv[0] === "cliphist" && argv[1] === "list") return clipEmpty ? "" : clipList + clipExtra
        if (argv[0].endsWith("/.local/bin/mu")) return muOut === undefined ? mailOut : muOut
        if (argv[0].endsWith("/launcher-roam-index")) return ""
        if (argv[0].endsWith("/tabs-list")) return tabsFail ? null : JSON.stringify(tabsJson)
        if (argv[0].endsWith("/clip-pin")) return argv[3] === "99" ? null : ""
        if (argv[0] === "sh" && argv[2].indexOf("qrencode") !== -1) return qrFail ? null : ""
        if (argv[0] === "hyprctl") return JSON.stringify(binds)
        if (argv[0] === "sh" && argv[4] && argv[4].endsWith("/.local/bin/fd")) return "notes/it's here.txt\nDocuments/report-final.pdf\nCode/\nDocuments/old/report.pdf\n"
        if (argv[0] === "sh" && argv[2].indexOf("cliphist decode") !== -1) return ""
        return null
    }
    // apps: names, keywords and usage chosen so every scoring level and the tie rules show up
    readonly property var apps: [
        { id: "firefox", name: "Firefox", genericName: "Web Browser", keywords: ["internet", "www"], comment: "Browse the web", icon: "firefox" },
        { id: "org.gnome.Settings", name: "Settings", genericName: "", keywords: ["preferences"], comment: "System settings", icon: "preferences-system" },
        { id: "com.mitchellh.ghostty", name: "Ghostty", genericName: "Terminal Emulator", keywords: ["shell", "prompt"], comment: "A terminal", icon: "com.mitchellh.ghostty" },
        { id: "code", name: "Visual Studio Code", genericName: "Text Editor", keywords: ["vscode"], comment: "Code editing", icon: "vscode" },
        { id: "emacs", name: "Emacs", genericName: "Text Editor", keywords: ["text", "editor"], comment: "Edit text", icon: "emacs" },
        { id: "org.gnome.TextEditor", name: "Text Editor", genericName: "", keywords: ["notepad"], comment: "Edit text files", icon: "org.gnome.TextEditor" },
        { id: "thunderbird", name: "Thunderbird", genericName: "Mail Client", keywords: ["email"], comment: "Read mail", icon: "thunderbird" },
        { id: "chromium", name: "Chromium", genericName: "Web Browser", keywords: [], comment: "Access the Internet", icon: "chromium" },
        { id: "foot", name: "Foot", genericName: "Terminal", keywords: [], comment: "", icon: "foot" },
        { id: "files", name: "Files", genericName: "File Manager", keywords: ["folder"], comment: "Browse files", icon: "system-file-manager" },
        { id: "org.inkscape.Inkscape", name: "Inkscape", genericName: "Vector Graphics Editor", keywords: ["svg"], comment: "", icon: "inkscape" },
        { id: "mpv", name: "mpv Media Player", genericName: "Multimedia player", keywords: ["video"], comment: "Play movies", icon: "mpv" },
        { id: "zoom", name: "Zoom Workplace", genericName: "", keywords: ["meeting"], comment: "Video calls", icon: "Zoom" },
        { id: "fire-starter", name: "Fire Starter", genericName: "", keywords: [], comment: "Lights fires", icon: "" }
    ].map(a => Object.assign({ noDisplay: false }, a))
    readonly property var usage: {
        const now = Date.now(), d = 86400000
        return { "chromium": { n: 3, t: now - 0.5 * d }, "firefox": { n: 1, t: now - 40 * d }, "emacs": { n: 2, t: now - 3 * d },
                 "foot": { n: 5, t: now - 10 * d }, "org.gnome.TextEditor": { n: 1, t: now - 0.1 * d } }
    }
    readonly property var appQueries: ["", "f", "fi", "fire", "text", "edit", "web", "term", "code", "o", "s", "zz", "firfox", "browsr", "media player", "mail"]
    readonly property var windows: [
        { address: "0xaaa", title: "Inbox  -  Thunderbird", cls: "thunderbird", ws: 21, focus: 2 },
        { address: "0xbbb", title: "~/Code", cls: "com.mitchellh.ghostty", ws: 11, focus: 0 },
        { address: "0xccc", title: "Mozilla Firefox", cls: "firefox", ws: 12, focus: 1 },
        { address: "0xddd", title: "scratch term", cls: "foot", ws: -98, focus: 3 }
    ]

    // ---- helpers ----
    function inputOf(item) {                // the TextInput inside a window
        if (!item) return null
        if (item.echoMode !== undefined && item.cursorPosition !== undefined) return item
        const kids = item.children || []
        for (let i = 0; i < kids.length; i++) { const r = inputOf(kids[i]); if (r) return r }
        return null
    }
    function rowsOf(item, acc) {            // the list's delegates that exist
        acc = acc || []
        if (!item) return acc
        if (item.modelData !== undefined && item.pic !== undefined) acc.push(item)
        const kids = item.children || []
        for (let i = 0; i < kids.length; i++) rowsOf(kids[i], acc)
        return acc
    }
    function textsOf(item, acc) {           // the visible texts in a window
        acc = acc || []
        if (!item || item.visible === false) return acc
        if (typeof item.text === "string" && item.text !== "") acc.push(item.text)
        const kids = item.children || []
        for (let i = 0; i < kids.length; i++) textsOf(kids[i], acc)
        return acc
    }
    function readIndex() { pinIndex.path = ""; pinIndex.path = root.state + "/clip-pins/index.json"; return pinIndex.text() }
    function focusLauncher() { const w = launcher.view.Window.window; if (w && !w.active) w.requestActivate() }
    function key(k, mods) { focusLauncher(); ev.keyClick(k, mods || Qt.NoModifier, -1) }
    function typeText(s) { focusLauncher(); for (const c of s) ev.keyClickChar(c, Qt.NoModifier, -1) }
    readonly property var v: launcher.view
    function labels(n) { return v.results.slice(0, n || 99).map(r => r.label) }
    function setDark(d) { modeFile.setText(d ? "true\n" : "false\n"); Theme.reload() }
    property int grabbing: 0            // pictures not saved yet: the next case waits for them
    property double holdUntil: 0
    // save a picture of the launcher, then switch to dark or light (the next case starts once both are done)
    function picture(name, dark) {
        if (!picDir) { if (dark !== undefined) setDark(dark); return }
        grabbing++
        launcher.view.parent.grabToImage(r => {
            r.saveToFile(picDir + "/" + name + ".png"); console.log("LTEST picture " + name)
            if (dark !== undefined) { setDark(dark); holdUntil = Date.now() + 300 }
            grabbing--
        })
    }

    FileView { id: modeFile; path: root.home + "/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark"; printErrors: false }
    FileView { id: recentFile; path: root.state + "/emoji-recent"; blockLoading: true; printErrors: false }
    FileView { id: settingsFile; path: root.state + "/launcher.json"; printErrors: false }
    FileView { id: roamTsv; path: root.cache + "/launcher-roam.tsv"; printErrors: false }
    FileView { id: pinIndex; path: root.state + "/clip-pins/index.json"; blockLoading: true; printErrors: false }
    FileView { id: emojiList; path: root.cache + "/emoji-picker.txt"; blockLoading: true; printErrors: false }

    TestEvent { id: ev }
    Launcher { id: launcher }
    RefLauncher { id: refLauncher }
    Picker { id: picker }
    RefPicker { id: refPicker }
    LaunchCmd { id: realCmd; timeout: 400; property var got: []; onFinished: (out, ok) => got = got.concat([[out, ok]]) }
    // a small picture to stand for an image on the clipboard
    FloatingWindow {
        id: artWin
        visible: true
        implicitWidth: 64; implicitHeight: 40
        Rectangle {
            id: art
            anchors.fill: parent
            gradient: Gradient { GradientStop { position: 0; color: "#3a7bd5" } GradientStop { position: 1; color: "#00d2a0" } }
            Text { anchors.centerIn: parent; text: "IMG"; color: "white"; font.pixelSize: 14; font.bold: true }
        }
    }

    property var cases: [
        { name: "setup", run: function() {
            art.grabToImage(r => r.saveToFile(root.cache + "/launcher-clip/42.png"))
            launcher.view.fakeApps = root.apps
            launcher.view.fakeWindows = root.windows
            launcher.view.fakeRun = root.fakeRun
            refLauncher.fakeApps = root.apps
            return 200
        } },

        // ---- apps: same order as the launcher before the modes ----
        { name: "app ranking unchanged (made-up apps, usage weighting)", run: function() {
            launcher.view.usage = root.usage; refLauncher.usage = root.usage
            launcher.toggle()
            const refIn = inputOf(refLauncher.contentItem)
            check("reference launcher's query found", refIn !== null)
            for (const q of root.appQueries) {
                launcher.view.queryText = q; refIn.text = q
                const got = launcher.view.results.map(r => r.entry ? r.entry.id : "calc")
                const want = refLauncher.results.map(e => e.id)
                check("apps for '" + q + "'", same(got, want), JSON.stringify(got) + " vs " + JSON.stringify(want))
            }
            return 50
        } },
        { name: "app ranking unchanged (the apps installed here)", run: function() {
            launcher.view.fakeApps = null; refLauncher.fakeApps = null
            const real = launcher.view.all
            const u = {}
            real.slice(0, 6).forEach((e, i) => u[e.id] = { n: i + 1, t: Date.now() - i * 5 * 86400000 })
            launcher.view.usage = u; refLauncher.usage = u
            const refIn = inputOf(refLauncher.contentItem)
            let bad = []
            for (const q of root.appQueries.concat(["a", "e", "set", "files", "termnal"])) {
                launcher.view.queryText = q; refIn.text = q
                const got = launcher.view.results.map(r => r.entry ? r.entry.id : "calc")
                const want = refLauncher.results.map(e => e.id)
                if (!same(got, want)) bad.push(q)
            }
            check("same order for " + real.length + " installed apps, 21 queries", real.length > 0 && bad.length === 0, "differs for " + JSON.stringify(bad) + ", apps " + real.length)
            launcher.view.fakeApps = root.apps; refLauncher.fakeApps = root.apps
            launcher.view.usage = root.usage
            return 50
        } },
        { name: "app row and Enter", run: function() {
            launcher.view.queryText = "fire"
            const r = v.results[0]
            check("row has label, sub, icon", r.label === "Firefox" && r.sub === "Browse the web" && r.icon === "firefox", JSON.stringify(r))
            Sys.reset()
            key(Qt.Key_Return)
            check("Enter starts it with uwsm", same(Sys.ran, ["uwsm app -- 'firefox.desktop'"]), JSON.stringify(Sys.ran))
            check("and closes", !launcher.visible)
            check("usage counted", launcher.view.usage.firefox.n === 2)
            return 50
        } },
        { name: "picture: apps", run: function() {
            launcher.view.usage = root.usage
            launcher.toggle()
            setDark(true)
            return 150
        } },
        { name: "picture: apps dark", run: function() { picture("apps-dark", false); return 250 } },
        { name: "picture: apps light", run: function() {
            check("prefix hint shows on an empty query", v.mode === "apps" && v.queryText === "")
            picture("apps-light", true)
            return 150
        } },

        // ---- prefixes, Tab, Backspace, Esc ----
        { name: "prefix keys switch the mode", run: function() {
            const want = [["=", "calc"], [":", "emoji"], ["v ", "clip"], ["w ", "win"], ["/", "files"], ["?", "keys"], ["o ", "org"]]
            for (const [p, m] of want) {
                launcher.view.begin("apps")
                typeText(p)
                check("typing '" + p + "' gives " + m + " with the prefix gone", v.mode === m && v.queryText === "", v.mode + " '" + v.queryText + "'")
            }
            launcher.view.begin("apps")
            typeText("v")
            check("'v' alone still searches apps", v.mode === "apps" && v.queryText === "v")
            launcher.view.queryText = "=2+2"
            check("pasted '=2+2' keeps the expression", v.mode === "calc" && v.queryText === "2+2", v.queryText)
            return 300
        } },
        { name: "Tab cycles, Backspace leaves, Esc closes", run: function() {
            launcher.view.begin("apps")
            const seen = [v.mode]
            for (let i = 0; i < 8; i++) { key(Qt.Key_Tab); seen.push(v.mode) }
            check("Tab goes through every mode and back", same(seen, ["apps", "calc", "emoji", "clip", "win", "files", "keys", "org", "apps"]), JSON.stringify(seen))
            key(Qt.Key_Backtab)
            check("Shift+Tab goes back", v.mode === "org", v.mode)
            typeText("x")
            key(Qt.Key_Backspace)
            check("Backspace deletes text first", v.mode === "org" && v.queryText === "")
            key(Qt.Key_Backspace)
            check("Backspace on empty leaves the mode", v.mode === "apps")
            key(Qt.Key_Backspace)
            check("and does nothing more in apps", v.mode === "apps" && launcher.visible)
            launcher.view.queryText = "e"
            const n = v.results.length
            key(Qt.Key_Down); key(Qt.Key_Down)
            check("Down moves", v.currentIndex === 2, v.currentIndex)
            key(Qt.Key_Up)
            check("Up moves", v.currentIndex === 1)
            key(Qt.Key_PageDown)
            check("PageDown moves a page", v.currentIndex > 1, v.currentIndex)
            key(Qt.Key_PageUp)
            check("PageUp goes back a page", v.currentIndex === 1, v.currentIndex)
            key(Qt.Key_Escape)
            check("Esc closes", !launcher.visible)
            return 50
        } },

        // ---- IPC ----
        { name: "open/toggle", run: function() {
            launcher.open("v")
            check("open v: visible, clipboard", launcher.visible && v.mode === "clip")
            launcher.open("v ")
            check("open v again: closed", !launcher.visible)
            launcher.open(":")
            check("open : shows emoji", launcher.visible && v.mode === "emoji")
            launcher.view.queryText = "cat"
            launcher.open("w")
            check("open w while open: windows, query cleared", launcher.visible && v.mode === "win" && v.queryText === "")
            launcher.toggle()
            check("toggle closes", !launcher.visible)
            launcher.toggle()
            check("toggle opens apps", launcher.visible && v.mode === "apps")
            launcher.open("")
            check("open '' while apps open: closed", !launcher.visible)
            launcher.open("bogus")
            check("unknown prefix opens apps", launcher.visible && v.mode === "apps")
            launcher.toggle()
            return 50
        } },

        // ---- calculator ----
        { name: "calculator", run: function() {
            root.ran = []
            launcher.open("=")
            typeText("2+")
            typeText("2")
            return 400
        } },
        { name: "calculator answer", run: function() {
            check("one qalc run for quick typing (debounced)", ranOf("qalc").length === 1, JSON.stringify(ranOf("qalc")))
            check("qalc -t EXPR", same(ranOf("qalc")[0], ["qalc", "-t", "2+2"]))
            check("result row", v.results.length === 1 && v.results[0].label === "4", JSON.stringify(labels()))
            Sys.reset()
            key(Qt.Key_Return)
            check("Enter copies the result", same(Sys.launched, [["wl-copy", "--", "4"]]), JSON.stringify(Sys.launched))
            launcher.open("=")
            check("history row after reopening", labels()[0] === "4" && v.results[0].sub === "2+2", JSON.stringify(labels()))
            launcher.view.queryText = "sqrt(2)"
            return 400
        } },
        { name: "picture: calculator", run: function() {
            check("new result above the history", same(labels(), ["1.414213562", "4"]), JSON.stringify(labels()))
            picture("calc-dark", false)
            return 250
        } },
        { name: "picture: calculator light", run: function() {
            picture("calc-light", true)
            return 50
        } },
        { name: "arithmetic typed in app mode", run: function() {
            launcher.toggle(); launcher.toggle()
            launcher.view.queryText = "2*(3+4)"
            return 400
        } },
        { name: "arithmetic in app mode", run: function() {
            check("calculator row first", v.results[0].label === "14" && v.results[0].icon === "accessories-calculator", JSON.stringify(labels(3)))
            check("count is apps only", v.countText === (v.results.length - 1) + " apps", v.countText)
            root.ran = []
            launcher.view.queryText = "fire"
            check("plain words: no calculator row", v.results[0].label === "Firefox")
            for (const q of ["2", "fire 2", "1.5", "v2"]) check("'" + q + "' is not arithmetic", !v.isArith(q))
            for (const q of ["2+2", "2 * (3+4)", "2^10", "-3+1", "10/4"]) check("'" + q + "' is arithmetic", v.isArith(q))
            launcher.toggle()
            return 300
        } },
        { name: "calculator command really times out and replaces", run: function() {
            realCmd.run(["sh", "-c", "sleep 0.2; echo old"])
            realCmd.run(["sh", "-c", "echo new"])
            return 600
        } },
        { name: "calculator command result", run: function() {
            check("only the newest run answers", same(realCmd.got, [["new\n", true]]), JSON.stringify(realCmd.got))
            realCmd.got = []
            realCmd.run(["sleep", "3"])
            return 700
        } },
        { name: "calculator command timeout", run: function() {
            check("a run past the timeout is stopped", !realCmd.busy && realCmd.got.length === 0, JSON.stringify(realCmd.got))
            return 50
        } },

        // ---- emoji ----
        { name: "emoji", run: function() {
            launcher.open(":")
            const recent = recentFile.text().split("\n")[0]
            check("recently used first", v.results[0].line === recent, v.results[0].line + " vs " + recent)
            check("row: glyph, name", v.results[0].glyph === "🎉" && v.results[0].label === "party popper", JSON.stringify([v.results[0].glyph, v.results[0].label]))
            // same order as the pick list's ranked search (qs-pick --rank) on the same lines
            const lines = [recent].concat(emojiList.text().split("\n").filter(l => l !== "" && l !== recent))
            let bad = []
            for (const q of ["heart", "smile", "cat", "us", "alpha", "poop", "party", "arrow left", "thumbs up", "tacco", "fire", "grin face"]) {
                launcher.view.queryText = q
                // the reference pick list, fed the same lines
                refPicker.items = refItems(lines)
                inputOf(refPicker.contentItem).text = q
                refPicker.ranked = true
                const want = refPicker.results.slice(0, 25).map(r => r.label)
                const got = v.results.slice(0, 25).map(r => r.line)
                if (!same(got, want)) bad.push(q + ": " + got.slice(0, 3) + " / " + want.slice(0, 3))
            }
            check("emoji ranked as qs-pick --rank ranks them (12 queries)", bad.length === 0, JSON.stringify(bad))
            launcher.view.queryText = "heart"
            check("'heart' finds the red heart first", v.results[0].glyph === "❤️", v.results[0].glyph)
            return 100
        } },
        { name: "picture: emoji", run: function() { launcher.view.queryText = "cat"; return 150 } },
        { name: "picture: emoji dark", run: function() { picture("emoji-dark", false); return 250 } },
        { name: "picture: emoji light", run: function() {
            picture("emoji-light", true)
            return 50
        } },
        { name: "emoji Enter", run: function() {
            launcher.view.queryText = "heart"
            Sys.reset()
            key(Qt.Key_Return)
            const a = Sys.launched[0] || []
            check("Enter copies and types it like emoji-picker", a[0] === "sh" && a[2].indexOf("wl-copy") !== -1 && a[2].indexOf("wtype") !== -1 && a[4] === "❤️", JSON.stringify(a))
            check("closes", !launcher.visible)
            return 200
        } },
        { name: "emoji recents written", run: function() {
            recentFile.path = ""; recentFile.path = root.state + "/emoji-recent"
            const ls = recentFile.text().split("\n").filter(l => l !== "")
            check("recents: the pick first, then the old ones", ls.length === 2 && ls[0].startsWith("❤️  red heart") && ls[1].startsWith("🎉"), JSON.stringify(ls))
            return 50
        } },

        // ---- clipboard ----
        { name: "clipboard", run: function() {
            Sys.reset(); root.ran = []
            launcher.open("v")
            check("old pictures cleaned on open", same(Sys.launched[0], ["find", root.cache + "/launcher-clip", "-type", "f", "-mmin", "+1440", "-delete"]), JSON.stringify(Sys.launched))
            return 300
        } },
        { name: "clipboard rows", run: function() {
            check("cliphist list once", ranOf("cliphist").length === 1)
            check("three rows", same(labels(), ["hello world   with spaces", "Image 64x40", "second entry"]), JSON.stringify(labels()))
            check("image row is a picture row", v.results[1].image === true && v.results[1].sub === "png, 3 KiB")
            const rows = rowsOf(launcher.view)
            const pic = rows.find(r => r.pic)
            check("picture row is taller", pic && pic.height === 92, pic ? pic.height : "none")
            check("decoded for the row on screen", v.thumbs["42"] === "file://" + root.cache + "/launcher-clip/42.png", JSON.stringify(v.thumbs))
            const dec = root.ran.find(a => a[0] === "sh" && a[2].indexOf("cliphist decode") !== -1)
            check("decode command gets the id as an argument", dec && dec[4] === root.cache + "/launcher-clip" && dec[5] === "42", JSON.stringify(dec))
            return 200
        } },
        { name: "picture: clipboard dark", run: function() { picture("clip-dark", false); return 250 } },
        { name: "picture: clipboard light", run: function() {
            picture("clip-light", true)
            return 50
        } },
        { name: "clipboard filter, delete, Enter", run: function() {
            launcher.view.queryText = "second"
            check("typing filters", same(labels(), ["second entry"]))
            launcher.view.queryText = "image"
            check("'image' finds pictures", same(labels(), ["Image 64x40"]))
            launcher.view.queryText = ""
            Sys.reset()
            key(Qt.Key_Down); key(Qt.Key_Down)
            key(Qt.Key_Delete, Qt.ShiftModifier)
            check("Shift+Delete forgets it", same(Sys.launched, [["sh", "-c", 'printf "%s\\t\\n" "$1" | cliphist delete', "sh", "7"]]), JSON.stringify(Sys.launched))
            check("and the row goes", same(labels(), ["hello world   with spaces", "Image 64x40"]) && launcher.visible)
            key(Qt.Key_Delete)
            check("plain Delete does not", v.results.length === 2)
            Sys.reset()
            key(Qt.Key_Up)
            key(Qt.Key_Return)
            check("Enter decodes it to the clipboard", same(Sys.launched, [["sh", "-c", 'printf "%s\\t\\n" "$1" | cliphist decode | wl-copy', "sh", "12"]]), JSON.stringify(Sys.launched))
            check("closes and forgets the list", !launcher.visible && v.clipRows.length === 0 && v.mode === "apps")
            return 50
        } },

        // ---- windows ----
        { name: "windows", run: function() {
            launcher.open("w")
            check("most recent first, the current one last", same(labels(), ["Mozilla Firefox", "Inbox - Thunderbird", "scratch term", "~/Code"]), JSON.stringify(labels()))
            check("class and desktop", v.results[0].sub === "firefox  Desktop 1" && v.results[2].sub === "foot  scratch", JSON.stringify(v.results.map(r => r.sub)))
            check("icon from the desktop entry", v.results[0].icon !== "", v.results[0].icon)
            launcher.view.queryText = "thunder"
            check("filter", same(labels(), ["Inbox - Thunderbird"]))
            Sys.reset()
            key(Qt.Key_Return)
            check("Enter focuses it as the Alt+Tab switcher does", same(Sys.ran, ["sleep 0.05; hyprctl dispatch 'hl.dsp.focus({ window = \"address:0xaaa\" })'"]), JSON.stringify(Sys.ran))
            return 50
        } },

        // ---- files ----
        { name: "files", run: function() {
            root.ran = []
            launcher.open("/")
            typeText("rep pdf")
            return 400
        } },
        { name: "files rows", run: function() {
            const fd = ranOf("sh").filter(a => a[4] && a[4].endsWith("/.local/bin/fd"))
            check("one fd run (debounced)", fd.length === 1, fd.length)
            const a = fd[0] || []
            check("fd under ~, at most 60, words in order", a.indexOf("--max-results") !== -1 && a[a.indexOf("--max-results") + 1] === "60"
                  && a[a.indexOf("--base-directory") + 1] === root.home && a[a.length - 1] === "rep.*pdf" && a[a.length - 2] === "--", JSON.stringify(a))
            check("shallow first", same(labels(), ["Code/", "report-final.pdf", "it's here.txt", "report.pdf"]), JSON.stringify(labels()))
            check("folder shown", v.results[1].sub === "~/Documents/", v.results[1].sub)
            Sys.reset()
            key(Qt.Key_Down); key(Qt.Key_Down)
            key(Qt.Key_Return)
            check("Enter: xdg-open, quoted", same(Sys.ran, ["xdg-open '" + root.home + "/notes/it'\\''s here.txt'"]), JSON.stringify(Sys.ran))
            launcher.open("/"); launcher.view.queryText = "rep pdf"
            return 400
        } },
        { name: "files: Ctrl and Alt", run: function() {
            Sys.reset()
            key(Qt.Key_Down)
            key(Qt.Key_Return, Qt.ControlModifier)
            check("Ctrl+Enter opens the folder", same(Sys.ran, ["xdg-open '" + root.home + "/Documents'"]), JSON.stringify(Sys.ran))
            launcher.open("/"); launcher.view.queryText = "rep pdf"
            return 400
        } },
        { name: "files: Alt", run: function() {
            Sys.reset()
            key(Qt.Key_Down)
            key(Qt.Key_Return, Qt.AltModifier)
            check("Alt+Enter copies the path", same(Sys.launched, [["wl-copy", "--", root.home + "/Documents/report-final.pdf"]]) && Sys.ran.length === 0, JSON.stringify(Sys.launched))
            root.ran = []
            launcher.open("/"); launcher.view.queryText = "r"
            return 300
        } },
        { name: "files: short query", run: function() {
            check("one letter does not search", root.ran.length === 0 && v.results.length === 0)
            launcher.toggle()
            return 50
        } },

        // ---- keybindings ----
        { name: "keybindings", run: function() {
            launcher.open("?")
            return 200
        } },
        { name: "keybinding rows", run: function() {
            check("formatted like keybind-help, undescribed left out", same(v.results.map(r => r.label + " = " + r.sub), [
                "Super + D = App launcher", "Super + Shift + ← = Move window left", "Super + Enter = Terminal", "PrtSc = Screenshot of an area",
                "Ctrl + Alt + Fn key = Mute", "Super + left-drag = Move window with the mouse"]), JSON.stringify(v.results.map(r => r.label)))
            launcher.view.queryText = "capture"
            check("other names work ('capture' finds Screenshot)", same(labels(), ["PrtSc"]), JSON.stringify(labels()))
            Sys.reset()
            key(Qt.Key_Return)
            check("Enter only copies the combo", same(Sys.launched, [["wl-copy", "--", "PrtSc"]]) && Sys.ran.length === 0, JSON.stringify(Sys.launched))
            return 50
        } },

        // ---- org capture ----
        { name: "org without a template", run: function() {
            launcher.open("o")
            launcher.view.queryText = "buy milk"
            check("asks for a template", labels()[0] === "Set a capture template first")
            Sys.reset()
            key(Qt.Key_Return)
            check("Enter does nothing", Sys.launched.length === 0 && Sys.ran.length === 0 && launcher.visible)
            settingsFile.setText('{ "captureKey": "j" }')
            launcher.toggle()
            return 200
        } },
        { name: "org capture", run: function() {
            launcher.open("o")
            launcher.view.queryText = "buy milk"
            check("row with the text and the template", labels()[0] === "buy milk" && v.results[0].sub.indexOf("template j") !== -1, JSON.stringify(v.results[0]))
            Sys.reset()
            key(Qt.Key_Return)
            check("emacsclient by argv with a timeout", same(Sys.launched, [["timeout", "5", "emacsclient", "-n", "-e", '(org-capture-string "buy milk" "j")']]), JSON.stringify(Sys.launched))
            check("no shell string", Sys.ran.length === 0)
            const tricky = ['say "hi"', "back\\slash \\\" mix", "two\nlines", "café ☕ 😀 ‽", "it's $(rm -rf ~) `x` ; |", ""]
            for (const t of tricky) {
                const a = v.captureArgv(t, "j")[5]
                // read the Lisp string back by hand: \\ -> \, \" -> ", \n -> newline
                const m = /^\(org-capture-string "((?:[^"\\]|\\.)*)" "j"\)$/.exec(a)
                const back = m ? m[1].replace(/\\(.)/g, (x, c) => c === "n" ? "\n" : c === "r" ? "\r" : c) : null
                check("escaped: " + JSON.stringify(t), back === t && a.indexOf("\n") === -1, a)
                console.log("LTEST ORGARG " + JSON.stringify([t + "|j", a]))
            }
            launcher.open("o")
            check("empty text: Enter does nothing", labels()[0] === "Type a note to capture" && v.results[0].run === null)
            launcher.toggle()
            return 50
        } },

        // ---- mail, notes, tabs, clipboard pins, QR, providers (agent `search`, round 2) ----
        { name: "new prefixes and the Space hint", run: function() {
            if (!launcher.visible) launcher.toggle()
            for (const [p, m] of [["m ", "mail"], ["n ", "notes"], ["t ", "tabs"]]) {
                launcher.view.begin("apps")
                typeText(p)
                check("typing '" + p + "' gives " + m + " with the prefix gone", v.mode === m && v.queryText === "", v.mode + " '" + v.queryText + "'")
            }
            for (const l of ["m", "n", "t"]) {
                launcher.view.begin("apps")
                typeText(l)
                const t = textsOf(launcher.view).join("|")
                check("'" + l + "' alone still searches apps and asks for Space", v.mode === "apps" && v.queryText === l && t.indexOf("Space") !== -1, t.slice(0, 80))
            }
            launcher.view.begin("apps")
            const hint = textsOf(launcher.view).join("|")
            check("the prefix line lists m, n, t and qr", ["m ␣", "n ␣", "t ␣", "qr ␣"].every(p => hint.indexOf(p.replace(" ", "&nbsp;")) !== -1), hint)
            launcher.view.setMode("mail")
            key(Qt.Key_Tab)
            check("Tab from a new mode goes to apps", v.mode === "apps", v.mode)
            const seen = new Set()
            launcher.view.begin("apps")
            for (let i = 0; i < 9; i++) { key(Qt.Key_Tab); seen.add(v.mode) }
            check("Tab never lands in mail, notes or tabs", !seen.has("mail") && !seen.has("notes") && !seen.has("tabs"), JSON.stringify([...seen]))
            check("modeOf finds them", v.modeOf("m") === "mail" && v.modeOf("n ") === "notes" && v.modeOf("tabs") === "tabs")
            launcher.toggle()
            return 100
        } },

        // ---- mail ----
        { name: "mail: unread by default", run: function() {
            Notif.dnd = false
            Sys.reset(); root.ran = []
            launcher.open("m")
            return 300
        } },
        { name: "mail: rows", run: function() {
            check("one mu find", root.ran.filter(a => a[0].endsWith("/.local/bin/mu")).length === 1, JSON.stringify(root.ran.map(a => a[0])))
            const a = root.ran.find(x => x[0].endsWith("/.local/bin/mu")) || []
            check("fields, sort and limit", same(a.slice(1, 7), ["find", "--fields", "d\tf\ts\ti", "--sortfield=date", "--reverse", "--maxnum=40"]), JSON.stringify(a))
            check("empty query is the unread query for both inboxes", a[7] === v.mailUnread && a[7].indexOf("flag:unread") !== -1 && a[7].indexOf("/work/INBOX") !== -1 && a[7].indexOf("/personal/INBOX") !== -1, a[7])
            check("rows: subject, sender and date", same(labels(), ["Quarterly budget review", "Lab 5 grades", "(no subject)"]), JSON.stringify(labels()))
            check("sender without the address, then the date", v.results[0].sub === "Ada Lovelace   2026-11-14 09:12" && v.results[2].sub === "bob@example.org   2026-11-13 17:40", JSON.stringify(v.results.map(r => r.sub)))
            check("count says messages", v.countText === "3 messages", v.countText)
            return 50
        } },
        { name: "mail: Enter opens it in mu4e and focuses Emacs", run: function() {
            key(Qt.Key_Down)
            Sys.reset()
            key(Qt.Key_Return)
            const l = Sys.launched[0] || []
            check("emacsclient by argv with a timeout", same(l.slice(0, 5), ["timeout", "5", "emacsclient", "-n", "-e"]) && l.length === 6, JSON.stringify(l))
            check("calls the mu4e view function with the id, starting mu4e if needed", l[5] === '(progn (unless (mu4e-running-p) (mu4e t)) (mu4e-view-message-with-message-id "id2@example.org"))', l[5])
            check("Emacs is focused, no shell string, launcher closed", Sys.emacsFocused === 1 && Sys.ran.length === 0 && !launcher.visible)
            return 50
        } },
        { name: "mail: reopen", run: function() { launcher.open("m"); return 300 } },
        { name: "mail: typing is debounced and the query is wrapped", run: function() {
            root.ran = []
            launcher.view.queryText = "f"; launcher.view.queryText = "fr"; launcher.view.queryText = "from:ada"
            return 120
        } },
        { name: "mail: debounced run", run: function() {
            check("nothing ran inside the delay", root.ran.filter(a => a[0].endsWith("/.local/bin/mu")).length === 0)
            return 350
        } },
        { name: "mail: debounced result", run: function() {
            const runs = root.ran.filter(a => a[0].endsWith("/.local/bin/mu"))
            check("one run for three keystrokes, query in parentheses", runs.length === 1 && runs[0][7] === "(from:ada)", JSON.stringify(runs))
            launcher.view.queryText = "-x"
            return 400
        } },
        { name: "mail: a query that starts with a dash", run: function() {
            const runs = root.ran.filter(a => a[0].endsWith("/.local/bin/mu"))
            check("never passed bare, so mu cannot take it for an option", runs.length === 2 && runs[1][7] === "(-x)", JSON.stringify(runs.map(r => r[7])))
            root.muOut = ""
            launcher.view.queryText = "zzz"
            return 400
        } },
        { name: "mail: nothing found", run: function() {
            check("says so, one info row, no count", labels()[0] === "No messages found" && v.results[0].run === null && v.countText === "0 messages", JSON.stringify(labels()) + v.countText)
            root.muOut = null
            launcher.view.queryText = "yyy"
            return 400
        } },
        { name: "mail: mu fails", run: function() {
            check("a failed run is an empty list, not an error", labels()[0] === "No messages found")
            root.muOut = undefined
            launcher.view.queryText = ""
            return 350
        } },
        { name: "mail: hidden while Do Not Disturb is on", run: function() {
            check("rows are back", labels().length === 3)
            root.ran = []
            Notif.dnd = true
            return 400
        } },
        { name: "mail: DND shows a notice", run: function() {
            check("only the notice, no subject or sender", same(labels(), ["Mail is hidden while Do Not Disturb is on"]) && v.results[0].run === null && v.results[0].sub === "", JSON.stringify(v.results))
            check("no count", v.countText === "")
            check("the mu query was not run again", root.ran.filter(a => a[0].endsWith("/.local/bin/mu")).length === 0)
            launcher.view.queryText = "ada"
            return 400
        } },
        { name: "mail: typing under DND runs nothing", run: function() {
            check("still hidden, still no query", labels().length === 1 && root.ran.filter(a => a[0].endsWith("/.local/bin/mu")).length === 0)
            Sys.reset()
            key(Qt.Key_Return)
            check("Enter does nothing", Sys.launched.length === 0 && launcher.visible)
            launcher.toggle()
            launcher.open("m")
            return 300
        } },
        { name: "mail: reopened under DND", run: function() {
            check("still hidden after reopening", labels().length === 1 && root.ran.filter(a => a[0].endsWith("/.local/bin/mu")).length === 0)
            Notif.dnd = false
            return 400
        } },
        { name: "mail: DND off brings the rows back", run: function() {
            check("rows return and the query runs", labels().length === 3 && root.ran.filter(a => a[0].endsWith("/.local/bin/mu")).length === 1, JSON.stringify(labels()))
            launcher.toggle()
            check("closing forgets the mail rows", v.mailRows.length === 0)
            return 50
        } },
        { name: "picture: mail", run: function() { launcher.open("m"); return 300 } },
        { name: "picture: mail dark", run: function() { picture("mail-dark", false); return 600 } },
        { name: "picture: mail light", run: function() { picture("mail-light", true); return 50 } },
        { name: "mail: close", run: function() { launcher.toggle(); return 50 } },

        // ---- notes ----
        { name: "notes: write the index", run: function() {
            roamTsv.setText(root.roamIndexText)
            return 150
        } },
        { name: "notes: open", run: function() {
            root.ran = []
            launcher.open("n")
            return 300
        } },
        { name: "notes: rows", run: function() {
            const idx = root.ran.filter(a => a[0].endsWith("/launcher-roam-index"))
            check("the refresh runs once, in the background, with directory and index file", idx.length === 1 && idx[0][1] === v.roamDir && idx[0][2] === root.cache + "/launcher-roam.tsv", JSON.stringify(idx))
            check("the roam directory is the one Emacs uses", v.roamDir === root.home + "/.emacs.d/org/roam", v.roamDir)
            check("rows, newest first", same(labels(), ["Grading rubric ideas", "Budget meeting notes", "Zettel on recursion"]), JSON.stringify(labels()))
            check("second line: modified date and file", v.results[0].sub === "Modified " + v.dayOf(1794664880) + "   rubric" && /^Modified \d{4}-\d\d-\d\d   /.test(v.results[1].sub), JSON.stringify(v.results.map(r => r.sub)))
            check("count", v.countText === "3 notes", v.countText)
            return 50
        } },
        { name: "notes: ranked search", run: function() {
            launcher.view.queryText = "budget"
            check("title match", same(labels(), ["Budget meeting notes"]), JSON.stringify(labels()))
            launcher.view.queryText = "recur"
            check("part of a word", same(labels(), ["Zettel on recursion"]), JSON.stringify(labels()))
            launcher.view.queryText = "rubric"
            check("file name counts as a keyword", labels()[0] === "Grading rubric ideas", JSON.stringify(labels()))
            launcher.view.queryText = "budgt"
            check("a slip is allowed", labels()[0] === "Budget meeting notes", JSON.stringify(labels()))
            launcher.view.queryText = "zzzz"
            check("nothing", v.results.length === 0 || v.results[0].path === undefined, JSON.stringify(labels()))
            launcher.view.queryText = "budget"
            Sys.reset()
            key(Qt.Key_Return)
            check("Enter: emacsclient with the file, then Emacs is focused", same(Sys.launched, [["timeout", "5", "emacsclient", "-n", "/n/roam/20-permanent/budget.org"]]) && Sys.emacsFocused === 1, JSON.stringify(Sys.launched))
            check("closed, no shell string", !launcher.visible && Sys.ran.length === 0)
            return 50
        } },
        { name: "notes: empty index", run: function() { roamTsv.setText(""); return 150 } },
        { name: "notes: empty index shown", run: function() {
            launcher.open("n")
            return 250
        } },
        { name: "notes: nothing indexed yet", run: function() {
            check("an info row, no crash", labels()[0] === "No notes found" && v.results[0].run === null, JSON.stringify(labels()))
            roamTsv.setText(root.roamIndexText)
            launcher.toggle()
            return 150
        } },
        { name: "picture: notes", run: function() { launcher.open("n"); return 300 } },
        { name: "picture: notes dark", run: function() { picture("notes-dark", false); return 600 } },
        { name: "picture: notes light", run: function() { picture("notes-light", true); return 50 } },
        { name: "notes: close", run: function() { launcher.toggle(); return 50 } },

        // ---- tabs ----
        { name: "tabs: open", run: function() {
            launcher.view.fakeWindows = root.windows.concat([{ address: "0xeee", title: "Docs X — Mozilla Firefox", cls: "firefox", ws: 12, focus: 4 }])
            root.ran = []; root.tabsFail = false; v.tabsAt = 0; v.tabRaw = []
            launcher.open("t")
            return 300
        } },
        { name: "tabs: rows", run: function() {
            check("tabs-list ran once", root.ran.filter(a => a[0].endsWith("/tabs-list")).length === 1, JSON.stringify(root.ran))
            check("rows: title and domain", same(labels(), ["Example A", "Docs X", "https://news.test/"]), JSON.stringify(labels()))
            check("the active tab of a window says it goes to that window", v.results[1].sub === "docs.test   goes to its window", v.results[1].sub)
            check("others say they open again in a new tab", v.results[0].sub === "example.org   opens it again in a new tab" && v.results[2].sub === "news.test   opens it again in a new tab", JSON.stringify(v.results.map(r => r.sub)))
            check("count", v.countText === "3 tabs", v.countText)
            launcher.view.queryText = "docs"
            check("filter by title", same(labels(), ["Docs X"]))
            launcher.view.queryText = "news.test"
            check("filter by domain", same(labels(), ["https://news.test/"]))
            launcher.view.queryText = "example.org/a"
            check("and by URL (not shown)", same(labels(), ["Example A"]))
            launcher.view.queryText = "docs"
            Sys.reset()
            key(Qt.Key_Return)
            check("Enter on the shown tab focuses its window", Sys.ran.length === 1 && Sys.ran[0].indexOf("address:0xeee") !== -1 && Sys.launched.length === 0, JSON.stringify(Sys.ran))
            launcher.open("t")
            return 100
        } },
        { name: "tabs: another tab opens the URL", run: function() {
            launcher.view.queryText = "example"
            Sys.reset()
            key(Qt.Key_Return)
            check("firefox URL by argv", same(Sys.launched, [["firefox", "https://example.org/a"]]), JSON.stringify(Sys.launched))
            check("and the most recent Firefox window is focused", Sys.ran.length === 1 && Sys.ran[0].indexOf("address:0xccc") !== -1, JSON.stringify(Sys.ran))
            return 50
        } },
        { name: "tabs: cached for 30 seconds", run: function() {
            root.ran = []
            launcher.open("t")
            return 200
        } },
        { name: "tabs: cache hit", run: function() {
            check("reopening inside 30 s does not read the sessionstore again", root.ran.filter(a => a[0].endsWith("/tabs-list")).length === 0 && v.results.length === 3)
            launcher.toggle()
            v.tabsAt = Date.now() - 31000
            launcher.open("t")
            return 300
        } },
        { name: "tabs: cache expired", run: function() {
            check("after 30 s it is read again", root.ran.filter(a => a[0].endsWith("/tabs-list")).length === 1)
            launcher.toggle()
            return 50
        } },
        { name: "picture: tabs", run: function() { v.tabsAt = 0; launcher.open("t"); return 300 } },
        { name: "picture: tabs dark", run: function() { picture("tabs-dark", false); return 600 } },
        { name: "picture: tabs light", run: function() { picture("tabs-light", true); return 50 } },
        { name: "tabs: failure", run: function() {
            launcher.toggle()
            v.tabRaw = []; v.tabsAt = 0; root.tabsFail = true
            launcher.open("t")
            return 300
        } },
        { name: "tabs: failure shown", run: function() {
            check("says it could not read them", labels()[0] === "Could not read the Firefox tabs" && v.results[0].run === null, JSON.stringify(labels()))
            launcher.view.queryText = "x"
            check("typing with no tabs does not break", v.results.length === 1)
            launcher.toggle()
            root.tabsFail = false
            launcher.view.fakeWindows = root.windows
            return 50
        } },

        // ---- clipboard pins ----
        { name: "pins: start from an empty index", run: function() {
            pinIndex.setText("[]")
            root.ran = []
            return 150
        } },
        { name: "pins: open", run: function() {
            Sys.reset()
            launcher.open("v")
            return 300
        } },
        { name: "pins: Ctrl+P pins a text entry", run: function() {
            check("three entries and a hint line with Ctrl+P", v.results.length === 3 && textsOf(launcher.view).join("|").indexOf("Ctrl+P") !== -1)
            root.ran = []
            key(Qt.Key_P, Qt.ControlModifier)
            const a = root.ran.find(x => x[0].endsWith("/clip-pin")) || []
            check("clip-pin gets directory, file, cliphist id and kind", a.length === 5 && a[1] === root.state + "/clip-pins" && /^\d+\.txt$/.test(a[2]) && a[3] === "12" && a[4] === "text", JSON.stringify(a))
            return 250
        } },
        { name: "pins: the pin is first", run: function() {
            check("pinned and listed first with a pin glyph, not twice", same(labels(), ["hello world   with spaces", "Image 64x40", "second entry"]) && v.results[0].pin !== undefined && v.results[0].glyph === "" && v.results[0].sub === "pinned", JSON.stringify(v.results.map(r => [r.label, r.sub])))
            check("count and notice", v.countText === "Pinned", v.countText)
            check("selection stays on top", v.currentIndex === 0)
            key(Qt.Key_Down); key(Qt.Key_Down)
            root.ran = []
            key(Qt.Key_P, Qt.ControlModifier)
            const a = root.ran.find(x => x[0].endsWith("/clip-pin")) || []
            check("a second pin: the other entry", a[3] === "7" && a[4] === "text", JSON.stringify(a))
            return 250
        } },
        { name: "pins: newest pin first, then the image", run: function() {
            check("order: newest pin, older pin, the rest", same(labels(), ["second entry", "hello world   with spaces", "Image 64x40"]) && v.results[0].pin && v.results[1].pin && !v.results[2].pin, JSON.stringify(labels()))
            key(Qt.Key_Down); key(Qt.Key_Down)
            root.ran = []
            key(Qt.Key_P, Qt.ControlModifier)
            const a = root.ran.find(x => x[0].endsWith("/clip-pin")) || []
            check("an image pin is a png", a[3] === "42" && a[4] === "image" && /^\d+\.png$/.test(a[2]), JSON.stringify(a))
            return 250
        } },
        { name: "pins: image pin row", run: function() {
            const r = v.results[0]
            check("image pin first, with its own picture, not decoded again", r.image === true && r.pin.kind === "image" && r.thumbUrl === "file://" + root.state + "/clip-pins/" + r.pin.file, JSON.stringify(r.thumbUrl))
            check("three pins and nothing else left", v.pins.length === 3 && v.results.length === 3)
            return 150
        } },
        { name: "pins: index file written", run: function() {
            const idx = JSON.parse(readIndex())
            check("index.json lists the three, newest first", idx.length === 3 && idx[0].kind === "image" && idx[1].label === "second entry" && idx[2].label === "hello world   with spaces", readIndex())
            check("with src, file and time", idx.every(p => p.src && /^\d+\.(txt|png)$/.test(p.file) && p.t > 0))
            return 50
        } },
        { name: "pins: Enter copies from the pin file", run: function() {
            key(Qt.Key_Down)
            const p = v.results[1].pin
            Sys.reset()
            key(Qt.Key_Return)
            check("wl-copy reads the file", same(Sys.launched, [["sh", "-c", 'wl-copy < "$1"', "sh", root.state + "/clip-pins/" + p.file]]), JSON.stringify(Sys.launched))
            check("no cliphist involved", JSON.stringify(Sys.launched).indexOf("cliphist") === -1 && !launcher.visible)
            launcher.open("v")
            return 200
        } },
        { name: "pins: image Enter has its type", run: function() {
            const p = v.results[0].pin
            Sys.reset()
            key(Qt.Key_Return)
            check("png image copied from the pin", same(Sys.launched, [["sh", "-c", 'wl-copy --type image/png < "$1"', "sh", root.state + "/clip-pins/" + p.file]]), JSON.stringify(Sys.launched))
            return 50
        } },
        { name: "picture: pinned clipboard", run: function() { launcher.open("v"); return 350 } },
        { name: "picture: pinned clipboard dark", run: function() { picture("pins-dark", false); return 250 } },
        { name: "picture: pinned clipboard light", run: function() { picture("pins-light", true); return 50 } },
        { name: "pins: pins survive a cleared cliphist", run: function() {
            launcher.toggle()
            root.clipEmpty = true
            launcher.open("v")
            return 300
        } },
        { name: "pins: cleared list", run: function() {
            check("cliphist is empty, the three pins are still listed", v.clipRows.length === 0 && v.results.length === 3 && v.results.every(r => r.pin), JSON.stringify(labels()))
            check("they came back from index.json", v.pins.length === 3)
            check("search finds pins by text and by the word pinned", (launcher.view.queryText = "second", same(labels(), ["second entry"])) && (launcher.view.queryText = "pinned", labels().length === 3))
            launcher.view.queryText = ""
            return 50
        } },
        { name: "pins: Ctrl+P on a pin unpins, Shift+Delete too", run: function() {
            const first = v.results[0].pin
            Sys.reset()
            key(Qt.Key_P, Qt.ControlModifier)
            check("the pin and its file go", v.pins.length === 2 && same(Sys.launched, [["rm", "-f", root.state + "/clip-pins/" + first.file]]), JSON.stringify(Sys.launched))
            Sys.reset()
            key(Qt.Key_Delete, Qt.ShiftModifier)
            check("Shift+Delete removes a pin, and not from cliphist", v.pins.length === 1 && Sys.launched.length === 1 && Sys.launched[0][0] === "rm", JSON.stringify(Sys.launched))
            check("the notice says so", v.countText === "Unpinned")
            return 150
        } },
        { name: "pins: removal persisted", run: function() {
            check("index.json has the one left", JSON.parse(readIndex()).length === 1, readIndex())
            root.clipEmpty = false
            launcher.toggle()
            launcher.open("v")
            return 300
        } },
        { name: "pins: an unpinned entry is an ordinary row again", run: function() {
            check("the pin first, the others back where they were", labels().length === 3 && v.results[0].pin !== undefined && v.results.filter(r => r.pin).length === 1, JSON.stringify(labels()))
            check("Shift+Delete on an ordinary row still forgets it in cliphist", (function() {
                key(Qt.Key_Down); Sys.reset(); key(Qt.Key_Delete, Qt.ShiftModifier)
                return Sys.launched.length === 1 && Sys.launched[0][2].indexOf("cliphist delete") !== -1
            })(), JSON.stringify(Sys.launched))
            return 50
        } },
        { name: "pins: too big or not convertible", run: function() {
            launcher.toggle()
            root.clipExtra = "99\ta very long entry\n"
            launcher.open("v")
            return 300
        } },
        { name: "pins: failed pin", run: function() {
            const before = v.pins.length
            const i = v.results.findIndex(r => r.id === "99")
            while (v.currentIndex < i) key(Qt.Key_Down)
            key(Qt.Key_P, Qt.ControlModifier)
            return 250
        } },
        { name: "pins: failed pin result", run: function() {
            check("nothing pinned, the notice says why", v.pins.length === 1 && v.countText.indexOf("Could not pin") !== -1, v.countText + " " + v.pins.length)
            launcher.toggle()
            root.clipExtra = ""
            check("closing forgets the pins in memory", v.pins.length === 0)
            return 50
        } },
        { name: "pins: a tampered index", run: function() {
            pinIndex.setText(JSON.stringify([{ id: "1", kind: "text", file: "../../etc/passwd", label: "evil", src: "1", t: 1 },
                                             { id: "2", kind: "text", file: "5.txt", label: "fine", src: "2", t: 2 }, "junk", null]))
            return 150
        } },
        { name: "pins: tampered index read", run: function() {
            launcher.open("v")
            return 250
        } },
        { name: "pins: only names this code writes are used", run: function() {
            check("the path-like entry is dropped", v.pins.length === 1 && v.pins[0].label === "fine", JSON.stringify(v.pins))
            launcher.toggle()
            pinIndex.setText("not json")
            return 150
        } },
        { name: "pins: a broken index", run: function() {
            launcher.open("v")
            return 250
        } },
        { name: "pins: broken index tolerated", run: function() {
            check("no pins, the clipboard list still works", v.pins.length === 0 && v.results.length === 3)
            launcher.toggle()
            return 50
        } },

        // ---- QR ----
        { name: "qr: row", run: function() {
            launcher.open("")
            root.ran = []
            Sys.reset()
            launcher.view.queryText = "qr"
            launcher.view.queryText = "qr "
            check("'qr' and 'qr ' alone make no row", !v.results.some(r => r.big))
            // the picture the stand-in run "made": real qrencode, under the name the next run will use
            realCmd.got = []
            realCmd.timeout = 3000
            realCmd.run(["qrencode", "-o", v.runDir + "/launcher-qr-" + (v.qrGen + 1) + ".png", "-s", "8", "-m", "2", "--", "https://example.org/qr-test"])
            return 400
        } },
        { name: "qr: type it", run: function() {
            realCmd.timeout = 400
            check("qrencode made the stand-in picture", realCmd.got.length === 1 && realCmd.got[0][1] === true, JSON.stringify(realCmd.got))
            launcher.view.queryText = "qr https://example.org/qr-test"
            return 450
        } },
        { name: "qr: row shown", run: function() {
            const q = root.ran.filter(a => a[0] === "sh" && a[2].indexOf("qrencode") !== -1)
            check("qrencode runs once, the text is its last argument, after --", q.length === 1 && q[0][q[0].length - 1] === "https://example.org/qr-test" && q[0][2].indexOf("-- \"$3\"") !== -1, JSON.stringify(q))
            check("under the runtime directory", q[0][4] === v.runDir && q[0][2].indexOf("launcher-qr-") !== -1, JSON.stringify(q[0]))
            const r = v.results[0]
            check("the first row is the code, large", r.big === true && r.label === "https://example.org/qr-test" && r.bigUrl === "file://" + v.runDir + "/launcher-qr-" + v.qrGen + ".png" && r.sub.indexOf("Enter copies") !== -1, JSON.stringify(r))
            check("the count does not include the code", v.countText === (v.results.length - 1) + " apps", v.countText)
            return 300
        } },
        { name: "picture: qr", run: function() { return 100 } },
        { name: "picture: qr dark", run: function() { picture("qr-dark", false); return 250 } },
        { name: "picture: qr light", run: function() { picture("qr-light", true); return 50 } },
        { name: "qr: Enter copies the picture", run: function() {
            const f = v.qrFile
            Sys.reset()
            key(Qt.Key_Return)
            check("wl-copy as image/png from the file, then the file is removed", same(Sys.launched, [["sh", "-c", 'wl-copy --type image/png < "$1"; rm -f "$1"', "sh", f]]), JSON.stringify(Sys.launched))
            check("closed", !launcher.visible && v.qrFile === "")
            return 50
        } },
        { name: "qr: too much text", run: function() {
            root.qrFail = true
            launcher.open("")
            launcher.view.queryText = "qr " + "x".repeat(40)
            return 450
        } },
        { name: "qr: failure shown", run: function() {
            check("an info row says so", v.results[0].label === "Too much text for one QR code" && v.results[0].run === null && !v.results[0].big, JSON.stringify(v.results[0]))
            root.qrFail = false
            launcher.view.queryText = "qr x"
            launcher.view.queryText = "firefox"
            return 300
        } },
        { name: "qr: leaving the query clears the code", run: function() {
            check("no QR row for ordinary queries", !v.results.some(r => r.big || r.label === "Too much text for one QR code") && v.qrFile === "")
            launcher.toggle()
            return 50
        } },
        { name: "qr: closing removes a picture nobody copied", run: function() {
            launcher.open("")
            launcher.view.queryText = "qr abc"
            return 450
        } },
        { name: "qr: close", run: function() {
            const f = v.qrFile
            Sys.reset()
            launcher.toggle()
            check("rm -f of the file", f !== "" && same(Sys.launched, [["rm", "-f", f]]), JSON.stringify(Sys.launched))
            return 50
        } },

        // ---- providers ----
        { name: "providers: rows from other features", run: function() {
            launcher.open("")
            root.seenQ = []
            v.providers = [q => { root.seenQ.push(q); return [] },
                           q => q === "zzz" ? [{ label: "Join next meeting", sub: "in 5 min", icon: "", run: () => Sys.launch(["joined"]) }] : [],
                           q => { throw new Error("boom") },
                           q => null,
                           q => q === "" ? [{ label: "Focus: Writing", sub: "", run: null }] : []]
            check("no query: the apps, then the provider's row", v.results[v.results.length - 1].label === "Focus: Writing" && v.results.length === root.apps.length + 1, JSON.stringify(labels()))
            launcher.view.queryText = "zzz"
            check("rows follow the apps; a throwing or null provider changes nothing", same(labels(), ["Join next meeting"]) , JSON.stringify(labels()))
            launcher.view.queryText = "  fire "
            check("providers get the trimmed query", root.seenQ.length > 0 && root.seenQ.every(q => q === q.trim()) && root.seenQ.indexOf("fire") !== -1, JSON.stringify(root.seenQ))
            check("extraRows is public", same(v.extraRows("zzz").map(r => r.label), ["Join next meeting"]) && same(v.extraRows("a"), []))
            launcher.view.queryText = "zzz"
            Sys.reset()
            key(Qt.Key_Return)
            check("Enter runs the provider's row", same(Sys.launched, [["joined"]]), JSON.stringify(Sys.launched))
            v.providers = []
            launcher.open("")
            launcher.view.queryText = "zzz"
            check("none left: back to plain apps", v.results.length === 0)
            launcher.toggle()
            return 50
        } },

        // ---- the pick list after the move to rank.js ----
        { name: "pick list unchanged", run: function() {
            const lines = emojiList.text().split("\n").filter(l => l !== "")
            let bad = []
            picker.items = newItems(lines); refPicker.items = refItems(lines)
            picker.ranked = true; refPicker.ranked = true
            const pin = inputOf(picker.contentItem), rin = inputOf(refPicker.contentItem)
            for (const q of ["heart", "smile", "cat", "us", "alpha", "poop", "party", "arrow left", "thumbs up", "tacco", "fire", "", "zzzz", "grinning cat"]) {
                pin.text = q; rin.text = q
                if (!same(picker.results.map(r => r.index), refPicker.results.map(r => r.index))) bad.push(q)
            }
            check("ranked (qs-pick --rank), " + lines.length + " lines, 14 queries", bad.length === 0 && pin !== null, JSON.stringify(bad))
            const kb = ["Super + D        App launcher", "Super + Shift + ←   Move window left", "PrtSc            Screenshot of an area",
                        "Super + Q        Close window", "Super + 1        Go to desktop 1", "Super + Space    Toggle floating"]
            picker.items = newItems(kb); refPicker.items = refItems(kb)
            picker.ranked = false; refPicker.ranked = false
            bad = []
            for (const q of ["capture", "kill", "desktop", "left", "float", "screnshot", "workspace", "super"]) {
                pin.text = q; rin.text = q
                if (!same(picker.results.map(r => r.index), refPicker.results.map(r => r.index))) bad.push(q)
            }
            check("plain lists with other names and slips, 8 queries", bad.length === 0, JSON.stringify(bad))
            pin.text = "capture"
            check("'capture' still finds the screenshot line", picker.results.length === 1 && picker.results[0].index === 2)
            return 50
        } },
        { name: "pick list loads lines as before", run: function() {
            // through the real file loader (Picker.open), without answering anyone
            picker.open(root.cache + "/emoji-picker.txt", root.state + "/unused-out", "Emoji")
            refPicker.open(root.cache + "/emoji-picker.txt", root.state + "/unused-out", "Emoji")
            picker.ranked = true; refPicker.ranked = true
            return 300
        } },
        { name: "pick list loaded", run: function() {
            const pin = inputOf(picker.contentItem), rin = inputOf(refPicker.contentItem)
            pin.text = "smile cat"; rin.text = "smile cat"
            const strip = it => JSON.stringify([it.label, it.icon, it.index, it.lower, it.plain, it.nameToks, it.keyToks])
            check("items built the same way", picker.items.length > 0 && same(picker.items.map(strip), refPicker.items.map(strip)), picker.items.length + " / " + refPicker.items.length)
            check("same results", same(picker.results.map(r => r.index), refPicker.results.map(r => r.index)))
            picker.visible = false; refPicker.visible = false
            return 50
        } }
    ]
    // items as Picker.qml's file loader builds them, old and new code
    function refItems(lines) {
        return lines.map((l, i) => {
            const label = l.replace(/\t/g, "  ")
            const lower = label.toLowerCase(), split = lower.indexOf("   ")
            return { label: label, icon: "", index: i, lower: lower, plain: split === -1,
                     nameToks: tokens(split === -1 ? lower : lower.slice(0, split)),
                     keyToks: split === -1 ? [] : tokens(lower.slice(split)) }
        })
    }
    function tokens(text) { return text.toLowerCase().split(/[^a-z0-9]+/).filter(t => t.length > 1) }     // fuzzy.js tokens()
    function newItems(lines) { return refItems(lines) }

    property int at: 0
    Timer {
        interval: 800; running: true            // let the windows and files settle first
        onTriggered: {
            if (root.grabbing > 0 || Date.now() < root.holdUntil) { interval = 50; restart(); return }
            if (root.at >= root.cases.length) {
                console.log("LTEST RESULT pass " + root.passed + " fail " + root.failed)
                done.start()
                return
            }
            const c = root.cases[root.at++]
            console.log("LTEST case: " + c.name)
            let wait = 100
            try { wait = c.run() } catch (e) { root.failed++; console.log("LTEST FAIL " + c.name + " threw: " + e + " " + e.stack) }
            interval = Math.max(20, wait || 100)
            restart()
        }
    }
    Timer { id: done; interval: 400; onTriggered: Qt.quit() }
}
