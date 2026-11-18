// Tests for the settings window (Settings.qml + SettingsBody + Settings<Page>.qml + the row types),
// JsonFile.qml and the focus profiles (Profiles.qml / ProfilesCore.qml / FocusRow.qml). NOT part of
// the shell: ~/.local/bin/settings-test copies the real files next to these stubs (Settings.qml as
// a plain window) and runs it offscreen. Every singleton the pages touch is a stub here that
// records its calls; nothing reaches the real machine. Each case logs STEST PASS or FAIL; the
// last line is "STEST RESULT pass N fail M". Pictures go to $SETTINGS_TEST_OUT if set.
// SETTINGS_PASS=nocharge: the run without Charge.qml (only the cases that matter for it).
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
        console.log("STEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
    }
    function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
    readonly property string home: Quickshell.env("HOME")
    readonly property string state: Quickshell.env("XDG_STATE_HOME")
    readonly property string picDir: Quickshell.env("SETTINGS_TEST_OUT")
    readonly property bool noCharge: Quickshell.env("SETTINGS_PASS") === "nocharge"
    readonly property string cfgDir: home + "/.config/shell/"

    // ---- hooks the shell would give the window ----
    Item { id: islandStub; property bool enabled: true; property var calls: []; function setEnabled(on) { calls = calls.concat(["setEnabled " + on]); enabled = on } }
    QtObject { id: cursorStub; property bool enabled: true }
    QtObject { id: dropStub; property bool enabled: true }
    QtObject {
        id: viewStub
        property int closed: 0
        function close() { closed++ }
        readonly property var modes: [{ id: "apps", prefix: "" }, { id: "calc", prefix: "=", hint: "Calculate (qalc)" }, { id: "emoji", prefix: ":", hint: "Emoji and symbols" },
                                      { id: "org", prefix: "o ", hint: "Capture a note to Org" }]
    }

    Settings { id: settings; island: islandStub; launcherView: viewStub; cursorFind: cursorStub; dropPreview: dropStub }
    TestEvent { id: ev }

    // files read and written behind the pages' backs ("by hand")
    FileView { id: handFile; printErrors: false; blockLoading: true; blockWrites: true }
    function readJson(path) { handFile.path = ""; handFile.path = path; try { return JSON.parse(handFile.text()) } catch (e) { return null } }
    function writeHand(path, obj) { handFile.path = path; handFile.setText(typeof obj === "string" ? obj : JSON.stringify(obj, null, 2)) }
    FileView { id: modeFile; path: root.home + "/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark"; printErrors: false; blockWrites: true }
    function setDark(d) { modeFile.setText(d ? "true\n" : "false\n"); Theme.reload() }

    // a JsonFile on its own, for its own cases
    JsonFile { id: jf; path: root.cfgDir + "jf-test.json"; create: true; defaults: ({ a: 1, list: ["x"] }) }
    JsonFile { id: jfBad; path: root.cfgDir + "jf-bad.json"; defaults: ({ a: 1 }) }
    JsonFile { id: jfLazy; path: root.cfgDir + "jf-lazy.json"; defaults: ({ a: 1, b: 2 }) }

    // focus profiles: the real singleton, and a second core built later to stand for a shell reload
    property var core2: null
    Component { id: coreComp; ProfilesCore { appGapMs: 150; launch: id => Sys.rec("app " + id) } }

    // ---- helpers ----
    readonly property var body: settings.body
    function page(id) { return body ? body.pageItem(id) : null }
    function rowsIn(id) { return body.rowsOf(page(id).contentItem, []) }
    function row(pageId, label) { return rowsIn(pageId).find(r => r.label === label) || null }
    function findType(item, pred) {
        if (!item) return null
        if (pred(item)) return item
        const kids = item.children || []
        for (let i = 0; i < kids.length; i++) { const r = findType(kids[i], pred); if (r) return r }
        return null
    }
    function inputIn(item) { return findType(item, x => x.cursorPosition !== undefined && x.echoMode !== undefined) }
    function win() { return body.Window.window }
    function focusWin() { const w = win(); if (w && !w.active) w.requestActivate() }
    function key(k, mods) { focusWin(); ev.keyClick(k, mods || Qt.NoModifier, -1) }
    function typeText(s) { focusWin(); for (const c of s) ev.keyClickChar(c, Qt.NoModifier, -1) }
    function click(item, x, y) {
        const w = item.Window.window
        if (w && !w.active) w.requestActivate()
        const p = item.mapToItem(null, x === undefined ? item.width / 2 : x, y === undefined ? item.height / 2 : y)
        ev.mouseClick(w, p.x, p.y, Qt.LeftButton, Qt.NoModifier, -1)
    }
    function lastCall(list) { return list.length ? list[list.length - 1] : "" }

    property int grabbing: 0
    property double holdUntil: 0
    property Item backdrop: null
    function size(w, h) {          // a shown window keeps its size unless its limits move
        settings.implicitWidth = w; settings.implicitHeight = h
        const q = Qt.size(w, h)
        settings.maximumSize = Qt.size(9999, 9999); settings.minimumSize = q; settings.maximumSize = q
    }
    function picture(name, then) {
        if (!picDir) { if (then) then(); return }
        grabbing++
        const target = body
        const ok = target.grabToImage(r => {
            r.saveToFile(picDir + "/" + name + ".png"); console.log("STEST picture " + name)
            if (then) then()
            holdUntil = Date.now() + 250
            grabbing--
        })
        if (!ok) { console.log("STEST FAIL picture " + name + " not taken"); failed++; grabbing--; if (then) then() }
    }
    // every row on a page fits: control inside the row, label not squeezed under 120 px
    function overflow(pageId) {
        const bad = []
        for (const r of rowsIn(pageId)) {
            if (!r.visible || r.width <= 0) continue
            const c = r.controlItem, l = r.labelItem
            const cx = c.mapToItem(r, 0, 0).x
            if (cx < -1 || cx + c.width > r.width + 1) bad.push(r.label + " control " + Math.round(cx) + "+" + Math.round(c.width) + ">" + Math.round(r.width))
            else if (!r.below && l.width > 0 && l.x + l.width > cx + 1 && c.width > 0) bad.push(r.label + " label under control")
            else if (!r.below && l.width < 119) bad.push(r.label + " label " + Math.round(l.width))
        }
        const p = page(pageId)
        if (p.contentItem.childrenRect.width > p.width + 1) bad.push("page wider than its view")
        return bad
    }

    property var cases: [
        { name: "setup: window opens on Appearance, 17 pages", run: function() {
            size(1920, 1080)
            settings.open("")
            return 400
        } },
        { name: "pages", run: function() {
            check("window shown", settings.visible)
            check("body loaded", body !== null)
            check("17 pages in the list", settings.pages.length === 17, settings.pages.length)
            check("every page exists", settings.pages.every(p => page(p.id) !== null), settings.pages.filter(p => !page(p.id)).map(p => p.id).join(","))
            check("starts on Appearance", settings.page === "appearance" && page("appearance").visible)
            check("card fits 1920x1080", body.width <= 1920 && body.height <= 1080 - 40, body.width + "x" + body.height)
            backdropFor()
            return 100
        } },
        { name: "every page: rows fit at 1920x1080", run: function() {
            for (const p of settings.pages) { settings.page = p.id; const b = overflow(p.id); check("fits: " + p.id, b.length === 0, b.join("; ")) }
            settings.page = "appearance"
            return 100
        } },
        { name: "ipc-style open(page) and close", run: function() {
            settings.open("quiet"); check("open quiet", settings.page === "quiet")
            settings.open("Power"); check("open by title", settings.page === "power")
            settings.open("nonsense"); check("unknown page keeps the page", settings.page === "power")
            settings.close(); check("close", !settings.visible)
            settings.toggle(); check("toggle opens", settings.visible)
            settings.page = "appearance"
            return 300
        } },
        { name: "nocharge: power page without Charge", only: "nocharge", run: function() {
            settings.page = "power"
            const r = row("power", "Charge limit")
            check("charge row there", r !== null)
            check("charge row disabled and says why", r && !r.enabled && r.sub.indexOf("not loaded") >= 0, r ? r.sub : "")
            check("break reminders still work", row("power", "Remind me to take breaks") !== null && row("power", "Remind me to take breaks").enabled)
            const sw = row("power", "Remind me to take breaks"); sw.edited(true)
            return 400
        } },
        { name: "nocharge: breaks written without the singleton", only: "nocharge", run: function() {
            const o = readJson(cfgDir + "breaks.json")
            check("breaks.json written with defaults and the change", o && o.enabled === true && o.workMinutes === 50, JSON.stringify(o))
            check("page fits", overflow("power").length === 0, overflow("power").join("; "))
            return 100
        } },

        // ---- JsonFile ----
        { name: "JsonFile: creates the defaults when missing", run: function() {
            const o = readJson(cfgDir + "jf-test.json")
            check("file created with defaults", same(o, { a: 1, list: ["x"] }), JSON.stringify(o))
            check("data = defaults", jf.values.a === 1 && jf.loaded)
            check("lazy file not created", readJson(cfgDir + "jf-lazy.json") === null && jfLazy.missing)
            writeHand(cfgDir + "jf-test.json", { a: 1, list: ["x"], mine: { keep: true } })
            return 400
        } },
        { name: "JsonFile: hand edit picked up; set keeps unknown keys", run: function() {
            check("hand edit seen", jf.values.mine && jf.values.mine.keep === true, JSON.stringify(jf.values))
            jf.set("a", 5)
            const o = readJson(cfgDir + "jf-test.json")
            check("set wrote the key", o.a === 5, JSON.stringify(o))
            check("unknown key kept", o.mine && o.mine.keep === true)
            jfLazy.set("b", 9)
            const l = readJson(cfgDir + "jf-lazy.json")
            check("first write of a missing file includes the defaults", same(l, { a: 1, b: 9 }), JSON.stringify(l))
            writeHand(cfgDir + "jf-bad.json", "{ not json")
            return 400
        } },
        { name: "JsonFile: bad JSON is never overwritten", run: function() {
            jfBad.reload()
            check("error reported", jfBad.error !== "")
            check("set refused", jfBad.set("a", 2) === false)
            handFile.path = ""; handFile.path = cfgDir + "jf-bad.json"
            check("file untouched", handFile.text() === "{ not json")
            settings.page = "notifications"
            return 300
        } },

        // ---- the row types, both ways ----
        { name: "switch: Do Not Disturb", run: function() {
            const r = row("notifications", "Do Not Disturb")
            Notif.dnd = false
            click(r.controlItem.children[0])
            check("click turns DND on", Notif.dnd === true && lastCall(Notif.calls) === "setDnd true", JSON.stringify(Notif.calls))
            check("switch shows it", r.checked === true)
            Notif.dnd = false
            check("changed elsewhere: switch follows", r.checked === false)
            r.forceActiveFocus(); key(Qt.Key_Space)
            check("Space flips it", Notif.dnd === true)
            Notif.setDnd(false)
            return 100
        } },
        { name: "choice: per-app rule and wallpaper scene", run: function() {
            const r = row("notifications", "Slack")
            check("Slack shows its rule", r && r.value === "list")
            const chips = r.controlItem.children[0].children
            click(chips[2])                                   // Mute
            check("click Mute sets the rule", Notif.ruleFor("Slack") === "mute" && lastCall(Notif.calls) === "setRule Slack mute", JSON.stringify(Notif.calls))
            Notif.setRule("Slack", "normal")
            check("changed elsewhere: chip follows", r.value === "normal")
            settings.page = "appearance"
            const sc = row("appearance", "Scene")
            sc.forceActiveFocus(); key(Qt.Key_Right)
            check("Right steps the scene", WallState.cfg.scene === "aurora", WallState.cfg.scene)
            WallState.setScene("depths")
            check("scene changed elsewhere: chip follows", sc.value === "depths")
            const mo = row("appearance", "Motion")
            mo.edited("still")
            check("Motion Still holds the frame", WallState.cfg.running === false && WallState.cfg.hidden === false)
            WallState.cfg.hidden = true
            check("Plain shows when hidden elsewhere", mo.value === "plain")
            WallState.cfg.hidden = false; WallState.cfg.running = true
            settings.page = "saver"
            return 300
        } },
        { name: "stepper: screensaver minutes", run: function() {
            const r = row("saver", "Start after")
            const plus = r.controlItem.children[0].children[2]
            click(plus)
            check("+ adds a minute", SaverState.cfg.minutes === 6, SaverState.cfg.minutes)
            r.forceActiveFocus(); key(Qt.Key_Left); key(Qt.Key_Left)
            check("Left takes them off", SaverState.cfg.minutes === 4)
            SaverState.setMinutes(0)
            check("0 elsewhere: shows never", r.value === 0 && r.text === "never")
            const sc = row("saver", "Scene")
            check("scene row disabled while off", !sc.enabled)
            SaverState.setMinutes(5)
            settings.page = "lecture"
            return 300
        } },
        { name: "slider: spotlight size", run: function() {
            const r = row("lecture", "Spotlight size")
            const s = r.controlItem.children[0].children[0]
            click(s, s.width * 0.5 + 6, s.height / 2)
            check("click mid-slider sets about the middle", Math.abs(Lecture.spotRadius - 420) <= 20, Lecture.spotRadius)
            Lecture.setSpotSize(100)
            check("changed elsewhere: slider follows", r.value === 100 && Math.abs(s.value - 60 / 760) < 0.01, s.value)
            r.forceActiveFocus(); key(Qt.Key_Right)
            check("Right steps by 10", Lecture.spotRadius === 110)
            settings.page = "launcher"
            return 300
        } },
        { name: "text: capture template key", run: function() {
            const r = row("launcher", "Capture template key")
            check("shows the file's key", r.value === "i", r.value)
            const inp = r.input
            click(inp); inp.selectAll(); typeText("j"); key(Qt.Key_Return)
            return 400
        } },
        { name: "text: written, hand edit seen, bad input refused", run: function() {
            const r = row("launcher", "Capture template key")
            const o = readJson(state + "/launcher.json")
            check("Enter wrote captureKey", o && o.captureKey === "j", JSON.stringify(o))
            check("other keys kept", o && o.other === 1)
            writeHand(state + "/launcher.json", { captureKey: "t", other: 1 })
            r.input.forceActiveFocus(); r.input.selectAll(); typeText("no way"); key(Qt.Key_Return)
            check("a bad key is refused", readJson(state + "/launcher.json").captureKey === "t")
            key(Qt.Key_Escape)
            return 400
        } },
        { name: "text: Esc puts the real value back", run: function() {
            const r = row("launcher", "Capture template key")
            check("hand edit shown", r.value === "t" && r.input.text === "t", r.value + " / " + r.input.text)
            check("window still open after Esc in a field", settings.visible)
            check("prefix list from the launcher", row("launcher", "Calculate (qalc)") !== null && row("launcher", "Calculate (qalc)").value === "=")
            return 100
        } },
        { name: "chips: quiet titles add, remove, hand edit", run: function() {
            settings.page = "quiet"
            const r = row("quiet", "Words in the title")
            check("shows the file's words", same(r.items, ["lecture", "class", "exam", "office hours"]), JSON.stringify(r.items))
            r.field.forceActiveFocus(); typeText("seminar"); key(Qt.Key_Return)
            return 400
        } },
        { name: "chips: written with unknown keys kept", run: function() {
            const r = row("quiet", "Words in the title")
            let o = readJson(cfgDir + "quiet.json")
            check("added", o.titles.indexOf("seminar") === 3 + 1, JSON.stringify(o.titles))
            check("unknown key kept", o.note === "mine")
            typeText("Exam"); key(Qt.Key_Return)
            o = readJson(cfgDir + "quiet.json")
            check("a duplicate is not added", o.titles.filter(t => t.toLowerCase() === "exam").length === 1)
            key(Qt.Key_Backspace)
            o = readJson(cfgDir + "quiet.json")
            check("Backspace in the empty field removes the last", o.titles.indexOf("seminar") < 0, JSON.stringify(o.titles))
            writeHand(cfgDir + "quiet.json", Object.assign(o, { titles: ["defense"] }))
            return 400
        } },
        { name: "chips: hand edit seen; quiet switch writes the file", run: function() {
            const r = row("quiet", "Words in the title")
            check("hand edit shown", same(r.items, ["defense"]), JSON.stringify(r.items))
            row("quiet", "Silence during matching events").edited(false)
            const o = readJson(cfgDir + "quiet.json")
            check("enabled false written, rest kept", o.enabled === false && o.note === "mine" && same(o.titles, ["defense"]), JSON.stringify(o))
            const lead = row("quiet", "Start early"); lead.bump(1)
            check("lead +5", readJson(cfgDir + "quiet.json").lead === 5)
            return 100
        } },
        { name: "button: palette use asks twice", run: function() {
            settings.page = "appearance"
            const plan = row("appearance", "Plan")
            check("plans from palette list", plan && plan.vals.join(",") === "clemson,forest,ocean", plan ? plan.vals.join(",") : "")
            check("live plan lit", plan.value === "clemson")
            plan.edited("forest")
            const b = row("appearance", "Use forest")
            check("use row names the plan", b !== null)
            Sys.reset()
            b.activated()
            check("first press only arms", b.armed && !Sys.calls.some(c => c.indexOf("palette use") >= 0))
            check("armed button says what happens", b.controlItem.children[0].label.indexOf("reloads Hyprland") >= 0)
            b.activated()
            check("second press runs palette use", Sys.calls.some(c => c.indexOf("palette use 'forest'") >= 0), JSON.stringify(Sys.calls))
            check("and disarms", !b.armed)
            const b2 = row("appearance", "Plan in use")
            plan.edited("ocean")
            const b3 = row("appearance", "Use ocean")
            b3.activated()
            return 4300
        } },
        { name: "button: an armed button disarms after 4 s", run: function() {
            const b = row("appearance", "Use ocean")
            check("disarmed by itself", b && !b.armed)
            Sys.reset(); b.activated()
            check("so one press after that only arms again", !Sys.calls.some(c => c.indexOf("palette use") >= 0))
            row("appearance", "Plan").edited("clemson")
            return 100
        } },
        { name: "sunset times through sunset-times", run: function() {
            const r = row("appearance", "Light from")
            check("light time read", r.value === "07:00", r.value)
            check("dark time read", row("appearance", "Dark from").value === "20:00")
            r.edited("06:45")
            return 900
        } },
        { name: "sunset times written", run: function() {
            handFile.path = ""; handFile.path = Quickshell.env("SUNSET_CONF")
            check("conf rewritten", /time = 6:45/.test(handFile.text()), handFile.text())
            check("row re-read", row("appearance", "Light from").value === "06:45")
            row("appearance", "Mode").edited("light")
            check("theme via cosmic-theme-toggle", lastCall(Sys.calls).indexOf("cosmic-theme-toggle light") >= 0, lastCall(Sys.calls))
            return 100
        } },
        { name: "hooks: island, cursor, launcher", run: function() {
            settings.page = "bar"
            const r = row("bar", "Island messages")
            check("island row enabled with the hook", r.enabled && r.checked)
            r.edited(false)
            check("island.setEnabled called", islandStub.enabled === false && lastCall(islandStub.calls) === "setEnabled false")
            islandStub.enabled = true
            check("island change elsewhere shown", r.checked)
            row("bar", "Shake to find the pointer").edited(false)
            check("cursor shake off", cursorStub.enabled === false)
            return 100
        } },
        { name: "power: charge, breaks, profile", run: function() {
            settings.page = "power"
            const c = row("power", "Charge limit")
            check("charge from Charge", c.value === "balanced" && c.enabled, c.value)
            c.edited("max_lifespan")
            check("Charge.set called", Charge.profile === "max_lifespan")
            row("power", "Remind me to take breaks").edited(true)
            row("power", "After working for").bump(1)
            const o = readJson(cfgDir + "breaks.json")
            check("breaks.json written, unknown kept", o && o.enabled === true && o.workMinutes === 30 && o.extra === "x", JSON.stringify(o))
            row("power", "Power profile").edited("performance")
            check("power profile via Sys.setProfile", Sys.profileCls === "performance")
            return 100
        } },
        { name: "health: ignore toggles", run: function() {
            settings.page = "health"
            const r = row("health", "Mail sync  ·  failing")
            check("failing job watched", r && r.enabled && r.checked)
            r.edited(false)
            check("ignored", Health.ignored.mail === 1)
            check("row says ignored", r.sub.indexOf("Ignored") === 0, r.sub)
            const ok = row("health", "Calendars  ·  working")
            check("working job not switchable", ok && !ok.enabled && ok.checked)
            Health.unignore("mail")
            check("unignored elsewhere: row follows", r.checked)
            return 100
        } },

        { name: "health: stop watching and notices", run: function() {
            settings.page = "health"
            const w = row("health", "Mail sync")
            check("watch row per job, hidden ones too", w && w.checked && !!row("health", "Old job"), w ? w.checked : "none")
            w.edited(false)
            let o = readJson(cfgDir + "health.json")
            check("hidden list written", o && JSON.stringify(o.hidden) === '["mail"]', JSON.stringify(o))
            check("and the shell-health is asked again", Health.calls[Health.calls.length - 1] === "refresh")
            w.edited(true)
            check("turning it back on empties the list", JSON.stringify(readJson(cfgDir + "health.json").hidden) === "[]")
            row("health", "Firmware").edited(false)
            o = readJson(cfgDir + "health.json")
            check("a notice kind switch keeps the others on", o.notices.firmware === false && o.notices.updates === true && o.notices.disk === true && o.notices.reboot === true, JSON.stringify(o.notices))
            check("kind switch shows off", row("health", "Firmware").checked === false)
            const nag = row("health", "Nag above")
            check("nag stepper at the default", nag.value === 50, nag.value)
            nag.bump(1)
            check("nag stepper writes updatesNag", readJson(cfgDir + "health.json").updatesNag === 60)
            row("health", "EFI partition below").bump(-1)
            check("esp stepper writes espMB", readJson(cfgDir + "health.json").espMB === 15)
            return 100
        } },

        // ---- search and keyboard ----
        { name: "search: / then words", run: function() {
            settings.page = "appearance"
            body.pageList.forceActiveFocus()
            key(Qt.Key_Slash)
            check("/ focuses the search", body.searchField.activeFocus)
            typeText("frames")
            check("finds Frames a second", body.results.length >= 1 && body.results[0].label === "Frames a second", JSON.stringify(body.results.map(r => r.label)))
            body.query = ""; typeText("snooze")
            const pages = body.results.map(r => r.pageId)
            check("finds across pages", pages.indexOf("notifications") >= 0 && pages.indexOf("power") >= 0, JSON.stringify(pages))
            check("page list shows counts", body.resultCount.power >= 1)
            check("results replace the page", !body.stack.visible)
            body.query = ""; typeText("lead")
            check("keywords count", body.results.some(r => r.label === "Start early"), JSON.stringify(body.results.map(r => r.label)))
            body.query = ""; typeText("zzqx")
            check("nothing for nonsense", body.results.length === 0)
            body.query = ""; typeText("calm")
            return 100
        } },
        { name: "search: Enter goes to the row", run: function() {
            const first = body.results[0]
            key(Qt.Key_Down); key(Qt.Key_Up)
            key(Qt.Key_Return)
            check("page switched", settings.page === first.pageId, settings.page)
            check("query cleared, page back", body.query === "" && body.stack.visible)
            return 200
        } },
        { name: "search: focus landed", run: function() {
            const r = body.results.length ? null : rowsIn(settings.page).find(x => x.activeFocus)
            check("the found row has focus", r !== null && r !== undefined && r.label.toLowerCase().indexOf("calm") >= 0, r ? r.label : "none")
            key(Qt.Key_Slash); typeText("x")
            key(Qt.Key_Escape)
            check("Esc clears the search first", body.query === "" && settings.visible)
            return 100
        } },
        { name: "keyboard: pages, Tab into a page, Esc closes", run: function() {
            settings.page = "appearance"
            body.pageList.forceActiveFocus()
            key(Qt.Key_Down)
            check("Down: next page", settings.page === "bar", settings.page)
            key(Qt.Key_Down); key(Qt.Key_Down); key(Qt.Key_Up)
            check("Down Down Up", settings.page === "notifications", settings.page)
            key(Qt.Key_End)
            check("End: last page", settings.page === "about")
            settings.page = "bar"
            key(Qt.Key_Tab)
            const f = rowsIn("bar").find(r => r.activeFocus)
            check("Tab goes to the first row", f && f.label === "Show the bar", f ? f.label : "none")
            key(Qt.Key_Tab)
            const g = rowsIn("bar").find(r => r.activeFocus)
            check("Tab again: next row", g && g.label === "Island messages", g ? g.label : "none")
            key(Qt.Key_Space)
            check("Space flips it", islandStub.enabled === false)
            islandStub.setEnabled(true)
            key(Qt.Key_Escape)
            check("Esc closes", !settings.visible)
            settings.open("focus")
            return 300
        } },

        // ---- focus profiles ----
        { name: "profiles: defaults created", run: function() {
            const o = readJson(cfgDir + "profiles.json")
            check("profiles.json has the three", o && o.profiles.map(p => p.name).join(",") === "Teaching,Grading,Writing", JSON.stringify(o))
            check("list", Profiles.list.length === 3 && Profiles.active === "")
            Profiles.island = islandStub
            return 100
        } },
        { name: "profiles: apply and end restore everything", run: function() {
            Notif.dnd = false; WallState.cfg.running = true; Pet.calm = false; Sys.keepAwake = false
            const s = Profiles.apply("teaching")
            check("apply Teaching", Profiles.active === "Teaching", s)
            check("DND on, wallpaper still, pet calm, keep awake", Notif.dnd && !WallState.cfg.running && Pet.calm && Sys.keepAwake)
            const st = readJson(state + "/profile-state.json")
            check("state saved with before values", st && st.active === "Teaching" && st.changed.dnd.before === "off" && st.changed.wallpaper.before === "moving", JSON.stringify(st))
            check("the page shows it on", row("focus", "On now") !== null)
            Profiles.end()
            check("all back", !Notif.dnd && WallState.cfg.running && !Pet.calm && !Sys.keepAwake && Profiles.active === "")
            return 100
        } },
        { name: "profiles: a hand change in between is kept", run: function() {
            Profiles.apply("Teaching")
            Notif.setDnd(false)                         // by hand
            WallState.cfg.running = true; WallState.cfg.running = false   // moved and back: still what it set
            const s = Profiles.end()
            check("DND left off (yours)", Notif.dnd === false, s)
            check("wallpaper put back", WallState.cfg.running === true)
            check("end says what it left", s.indexOf("left as you set them: dnd") >= 0, s)
            Notif.setDnd(true)
            Profiles.apply("Teaching")
            check("already-on DND is not remembered", !("dnd" in Profiles.changed))
            Profiles.end()
            check("so it stays on after end", Notif.dnd === true)
            Notif.setDnd(false)
            return 100
        } },
        { name: "profiles: reload in the middle", run: function() {
            Profiles.apply("Teaching")
            Sys.keepAwake = false                       // what a shell reload does to keep awake
            core2 = coreComp.createObject(root)
            return 600
        } },
        { name: "profiles: reloaded copy carries on and ends", run: function() {
            check("reloaded: still on", core2.active === "Teaching", core2.active)
            check("keep awake set again after the reload", Sys.keepAwake === true)
            const s = core2.end()
            check("ended from the reloaded copy: all back", !Notif.dnd && WallState.cfg.running && !Pet.calm && !Sys.keepAwake, s)
            core2.destroy(); core2 = null
            Profiles.file.reload()
            return 300
        } },
        { name: "profiles: switching keeps the first before-values", run: function() {
            Profiles.list; Profiles.end()
            Notif.dnd = false; Sys.keepAwake = false; islandStub.enabled = true; WallState.cfg.running = true
            Profiles.apply("Teaching")
            Profiles.apply("Writing")
            check("Writing on", Profiles.active === "Writing")
            check("keep awake (Teaching only) given back", Sys.keepAwake === false)
            check("pet calm (Teaching only) given back", Pet.calm === false)
            check("island off", islandStub.enabled === false)
            check("DND remembered from before Teaching", Profiles.changed.dnd && Profiles.changed.dnd.before === "off")
            Profiles.end()
            check("end: all as before Teaching", !Notif.dnd && islandStub.enabled && WallState.cfg.running)
            return 100
        } },
        { name: "profiles: breaks, apps and desktop", run: function() {
            Sys.reset(); Sys.desktop = 1
            writeHand(cfgDir + "breaks.json", { enabled: false, workMinutes: 30, extra: "x" })
            Profiles.edit("Grading", "apps", ["org.gnome.Nautilus", "zotero@3"])
            Profiles.edit("Grading", "desk", 2)
            return 300
        } },
        { name: "profiles: grading opens apps", run: function() {
            const g = Profiles.find("Grading")
            check("edit wrote apps and desk", same(g.apps, ["org.gnome.Nautilus", "zotero@3"]) && g.desk === 2, JSON.stringify(g))
            Profiles.apply("Grading")
            const o = readJson(cfgDir + "breaks.json")
            check("break reminders on in breaks.json", o && o.enabled === true, JSON.stringify(o))
            return 1800
        } },
        { name: "profiles: apps on their desktops, then the profile's", run: function() {
            const runs = Sys.calls.filter(c => c.startsWith("goDesktop") || c.startsWith("run uwsm"))
            check("desktop 3 then zotero, desktop 2 then Nautilus", same(runs, ["goDesktop 3", "run uwsm app -- 'zotero.desktop'", "goDesktop 2", "run uwsm app -- 'org.gnome.Nautilus.desktop'"]), JSON.stringify(runs))
            const s = Profiles.end()
            check("end goes back to desktop 1", Sys.desktop === 1, s)
            check("breaks back off", readJson(cfgDir + "breaks.json").enabled === false)
            Profiles.edit("Grading", "apps", []); Profiles.edit("Grading", "desk", 0)
            return 300
        } },
        { name: "profiles: launcher rows", run: function() {
            check("nothing for an empty query", Profiles.launcherRows("", viewStub).length === 0)
            const all = Profiles.launcherRows("focus", viewStub).map(r => r.label)
            check("focus: three rows", same(all, ["Focus: Teaching", "Focus: Grading", "Focus: Writing"]), JSON.stringify(all))
            check("'fo' too", Profiles.launcherRows("fo", viewStub).length === 3)
            check("by name", same(Profiles.launcherRows("teach", viewStub).map(r => r.label), ["Focus: Teaching"]))
            check("focus wri", same(Profiles.launcherRows("focus wri", viewStub).map(r => r.label), ["Focus: Writing"]))
            check("unrelated", Profiles.launcherRows("firefox", viewStub).length === 0 && Profiles.launcherRows("g", viewStub).length === 0)
            const row0 = Profiles.launcherRows("teaching", viewStub)[0]
            check("rows have label, sub, run", row0.sub !== "" && typeof row0.run === "function")
            row0.run()
            check("run closes the launcher and applies", viewStub.closed === 1 && Profiles.active === "Teaching")
            const rows = Profiles.launcherRows("focus", viewStub).map(r => r.label)
            check("while on: End row", rows.indexOf("End focus: Teaching") >= 0, JSON.stringify(rows))
            Profiles.launcherRows("teaching", viewStub)[0].run()
            check("End row ends it", Profiles.active === "")
            return 100
        } },
        { name: "profiles: page edits and the panel row", run: function() {
            settings.page = "focus"
            const ch = rowsIn("focus").filter(r => r.label === "Island")[2]      // Writing's
            ch.edited("on")
            check("page edit written", readJson(cfgDir + "profiles.json").profiles[2].island === "on")
            check("and shown", ch.value === "on")
            const add = row("focus", "Name")
            add.input.forceActiveFocus(); typeText("Meetings"); key(Qt.Key_Return)
            check("new profile", Profiles.find("Meetings") !== null && Profiles.list.length === 4)
            const rm = rowsIn("focus").filter(r => r.label === "Remove this profile")[3]
            rm.activated()
            check("remove asks twice", Profiles.find("Meetings") !== null)
            rm.activated()
            check("removed", Profiles.find("Meetings") === null)
            frWin.visible = true
            return 300
        } },
        { name: "profiles: the panel row", run: function() {
            const chip = findType(fr, c => c.label === "Grading" && c.onClicked !== undefined)   // chips sit in a GridLayout since 2026-11-17
            click(chip)
            check("panel row starts it", Profiles.active === "Grading")
            check("chip lit", chip.on)
            click(chip)
            check("click again ends it", Profiles.active === "")
            frWin.visible = false
            return 100
        } },

        // ---- pictures and fitting ----
        { name: "pictures: 1920x1080", run: function() {
            Notif.dnd = true
            Profiles.apply("Teaching")
            backdropFor()
            const shots = ["appearance", "notifications", "quiet", "power", "focus"]
            let n = 0
            const next = () => {
                if (n >= shots.length * 2) { root.busyPics = false; return }
                const i = n++, p = shots[i % shots.length], dark = i < shots.length
                setDark(dark)
                settings.page = p
                page(p).contentY = 0
                Qt.callLater(() => picture(p + "-" + (dark ? "dark" : "light"), next))
            }
            if (picDir) { root.busyPics = true; Qt.callLater(next); timeoutPics.start() }
            return 600
        } },
        { name: "portrait 1080x1920 fits", run: function() {
            setDark(true)
            size(1080, 1920)
            return 400
        } },
        { name: "portrait: rows fit", run: function() {
            check("window is portrait now", settings.width === 1080 && settings.height === 1920, settings.width + "x" + settings.height)
            check("card fits the portrait screen", body.width <= 1080 - 16 && body.height <= 1920, body.width + "x" + body.height)
            for (const p of settings.pages) { settings.page = p.id; const b = overflow(p.id); check("portrait fits: " + p.id, b.length === 0, b.join("; ")) }
            settings.page = "appearance"
            picture("appearance-portrait-dark")
            return 400
        } },
        { name: "small 1366x768 fits", run: function() {
            size(1366, 768)
            return 300
        } },
        { name: "small: card inside", run: function() {
            check("card fits 1366x768", body.width <= 1366 && body.height <= 768 - 40, body.width + "x" + body.height + " in " + settings.width + "x" + settings.height)
            settings.page = "focus"
            picture("focus-1366-dark")
            Profiles.end()
            return 300
        } }
    ]
    property bool busyPics: false
    property bool settingsWasOpen: false
    Timer { id: timeoutPics; interval: 20000; onTriggered: root.busyPics = false }
    // something to stand for the wallpaper behind the translucent window
    function backdropFor() {
        if (!backdrop || backdrop.parent !== body) backdrop = Qt.createQmlObject('import QtQuick; Rectangle { anchors.fill: parent; z: -1; gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "#2b3a55" } GradientStop { position: 0.6; color: "#6b4c7a" } GradientStop { position: 1; color: "#c97b4a" } } }', body)
        return {}
    }
    FloatingWindow { id: frWin; visible: false; implicitWidth: 600; implicitHeight: 60; color: Theme.solidBg; FocusRow { id: fr; anchors.fill: parent; anchors.margins: 10 } }
    Connections { target: settings; function onVisibleChanged() { if (!settings.visible) console.log("STEST note: window closed " + new Error().stack.split("\n").slice(0, 6).join(" | ")) } }

    property int at: 0
    Timer {
        interval: 900; running: true
        onTriggered: {
            if (root.grabbing > 0 || root.busyPics || Date.now() < root.holdUntil) { interval = 50; restart(); return }
            while (root.at < root.cases.length && (root.cases[root.at].only || "") !== (root.noCharge ? "nocharge" : "")
                   && !(root.noCharge && root.at === 0) && !(root.noCharge && root.cases[root.at].name === "pages")) root.at++
            if (root.at >= root.cases.length) {
                console.log("STEST RESULT pass " + root.passed + " fail " + root.failed)
                done.start()
                return
            }
            const c = root.cases[root.at++]
            console.log("STEST case: " + c.name + (root.settingsWasOpen && !settings.visible ? "  (window closed)" : ""))
            root.settingsWasOpen = settings.visible
            let wait = 100
            try { wait = c.run() } catch (e) { root.failed++; console.log("STEST FAIL " + c.name + " threw: " + e + " " + e.stack) }
            interval = Math.max(20, wait || 100)
            restart()
        }
    }
    Timer { id: done; interval: 400; onTriggered: Qt.quit() }
}
