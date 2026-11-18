// Tests for the notification core (Notif.qml, NotifStack.qml, NotifGroups.qml, NotifList.qml,
// NotifPopups.qml). NOT part of the shell: ~/.local/bin/notify-test copies those files next to
// this one with the stub Sys and StubPanel, seeds a temporary XDG_STATE_HOME (an old-shape
// history of 30 made-up entries, one snoozed entry already due and one due in an hour), and runs
// it offscreen inside dbus-run-session: the real NotificationServer owns
// org.freedesktop.Notifications on that private bus only, and the end-to-end case sends to it
// with gdbus on the same private bus. Every other case feeds stand-in notification objects
// through Notif.ingest(), the one way in.
//
// Each case logs NTEST PASS/FAIL; the last line is "NTEST RESULT pass N fail M". Pictures:
// $NOTIFY_TEST_OUT-dark.png and -light.png (grouped popups on the left, the grouped list on
// the right). Adding a case: append { name, run } to `cases`; `run` returns how many
// milliseconds to wait before the next case.
import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell
import Quickshell.Io

ShellRoot {
    // a stand-in Notification: the properties and calls Notif and the cards use
    Component {
        id: fakeC
        QtObject {
            property bool tracked: false
            property real expireTimeout: -1
            property string appName: ""
            property string appIcon: ""
            property string summary: ""
            property string body: ""
            property int urgency: 1
            property var actions: []
            property bool resident: false
            property string image: ""
            property var hints: ({})
            property bool gone: false
            property string how: ""
            signal closed(int reason)
            function dismiss() { if (gone) return; gone = true; how = "dismissed"; tracked = false; closed(1) }
            function expire() { if (gone) return; gone = true; how = "expired"; tracked = false; closed(0) }
        }
    }
    Component {
        id: fakeActionC
        QtObject { property string identifier; property string text; property int hits: 0; function invoke() { hits++ } }
    }

    // the state files, read straight from disk
    FileView { id: histPeek; path: Quickshell.env("XDG_STATE_HOME") + "/notif-history.json"; blockLoading: true; blockAllReads: true; printErrors: false }
    FileView { id: snzPeek; path: Quickshell.env("XDG_STATE_HOME") + "/notif-snoozed.json"; blockLoading: true; blockAllReads: true; printErrors: false }
    FileView { id: rulesPeek; path: Quickshell.env("XDG_STATE_HOME") + "/notif-rules.json"; blockLoading: true; blockAllReads: true; printErrors: false }

    Process { id: gdbus; onExited: (code, status) => win.gdbusCode = code }

    // the popup window's file itself (PanelWindow swapped for StubPanel by the runner)
    NotifPopups { id: popupsWin }

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 860; implicitHeight: 760
        color: Theme.solidBg

        property int passed: 0
        property int failed: 0
        property int gdbusCode: -1
        property int osdNotes: 0
        property string osdText: ""
        function check(what, ok, detail) {
            if (ok) passed++; else failed++
            console.log("NTEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
        }
        TestEvent { id: ev }
        Connections { target: Notif; function onOsdNote(text, percent) { win.osdNotes++; win.osdText = text + "|" + percent } }

        function json(peek) { peek.reload(); peek.waitForJob(); try { return JSON.parse(peek.text()) } catch (e) { return null } }
        function fake(props) { return fakeC.createObject(win, props) }
        function send(app, summary, extra) { const n = fake(Object.assign({ appName: app, summary: summary, body: "" }, extra || {})); return { n: n, how: Notif.ingest(n) } }
        function cards() { const out = []; for (const c of kids(stackView)) if (c.modelData !== undefined && c.g !== undefined) out.push(c); return out }
        function cardFor(app) { return cards().find(c => c.app === app) || null }
        function find(item, name) {
            if (!item) return null
            if (item.objectName === name) return item
            for (const c of kids(item)) { const f = find(c, name); if (f) return f }
            return null
        }
        function reset() {
            Notif.dismissAll()
            Notif.clear()
            if (Notif.dnd) Notif.setDnd(false)
            for (const a of Object.keys(Notif.rules)) Notif.setRule(a, "normal")
            stackView.expanded = ({}); stackView.menuFor = ""
            if (listView) listView.fresh = 0
            Notif.snoozed = []; Notif.saveSnoozed(); Notif.armSnooze()
        }
        property var keep: ({})             // values carried between cases

        Item {
            id: stage
            width: 860; height: 760
            Rectangle {                     // a stand-in desktop behind the popups
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.dark ? "#2a2d38" : "#c9cdd6" }
                    GradientStop { position: 1; color: Theme.dark ? "#14151b" : "#e8e4dc" }
                }
            }
            NotifStack {
                id: stackView
                x: 16; y: 16; width: 380
            }
            Rectangle {                     // the bell pill's popup, as Bar.qml draws it
                id: listBox
                x: 430; y: 16; width: 392
                height: Math.min(720, keyScope.implicitHeight + 32)
                radius: 12
                color: Theme.panelBg
                border.width: 2
                border.color: Theme.accentBg
                clip: true
                // the same key handling as Bar.qml's popup around its Loader (c clears)
                FocusScope {
                    id: keyScope
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                    implicitHeight: listLoader.implicitHeight
                    focus: true
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_C && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                            if (listLoader.item) listLoader.item.fresh = 0
                            Notif.clear()
                            event.accepted = true
                        }
                    }
                    Loader { id: listLoader; width: parent.width; active: win.listOpen; sourceComponent: Component { NotifList {} } }
                }
            }
        }
        property alias listView: listLoader.item
        property bool listOpen: false        // the list marks everything seen while open, so only for its cases
        function kids(item) { const a = []; if (!item) return a; for (let i = 0; i < item.children.length; i++) a.push(item.children[i]); return a }

        property var cases: [
            { name: "startup: old-shape history migrates", run: function() {
                check("history file read (loaded guard released)", Notif.loaded)
                check("30 saved + 1 snoozed one that came due while down = 31", Notif.history.length === 31, Notif.history.length)
                const old = Notif.history.find(e => e.summary === "Old 5")
                check("old entry kept its fields", !!old && old.app === "App1" && old.time === "Mon 09:05" && old.seen === true, JSON.stringify(old))
                check("old entry got the new fields with defaults", !!old && typeof old.id === "string" && old.id !== "" && Array.isArray(old.actions)
                      && old.actions.length === 0 && old.image === "" && old.appIcon === "" && old.urgency === 1, JSON.stringify(old))
                const crit = Notif.history.find(e => e.summary === "Old 2")
                check("old critical entry -> urgency 2", !!crit && crit.critical && crit.urgency === 2)
                check("unseen kept: 3 old unseen + the redelivered one", Notif.unseen === 4, Notif.unseen)
                check("unseenCritical from an old unseen critical", Notif.unseenCritical)
                check("an entry missing 'seen' counts as seen", Notif.history.find(e => e.summary === "Old 29").seen === true)
                return 50
            } },
            { name: "startup: snoozed ones due while down come back once", run: function() {
                const back = Notif.history[0]
                check("due one is at the top, unseen, marked snoozed", back.summary === "Snoozed earlier" && back.seen === false && back.snoozed === true, JSON.stringify(back))
                check("and pops up (marked snoozed, no live object)", Notif.live.length === 1 && Notif.live[0].snoozed && Notif.live[0].n === null)
                const c = cardFor("Remind")
                check("its card says Snoozed", !!c && c.newest.snoozed)
                check("the later one is still waiting", Notif.snoozed.length === 1 && Notif.snoozed[0].summary === "Snoozed later")
                check("next due about an hour out", Notif.nextDue > Date.now() + 3500000 && Notif.nextDue < Date.now() + 3700000)
                const f = json(snzPeek)
                check("snoozed file rewritten without the delivered one", Array.isArray(f) && f.length === 1 && f[0].summary === "Snoozed later", JSON.stringify(f))
                check("history file has all 31", (json(histPeek) || []).length === 31)
                Notif.reloadSnoozed()                       // what a second restart reads
                return 400
            } },
            { name: "restart again: not delivered twice", run: function() {
                check("one copy of it in history", Notif.history.filter(e => e.summary === "Snoozed earlier").length === 1)
                check("still one popup", Notif.live.length === 1, Notif.live.length)
                check("still one waiting", Notif.snoozed.length === 1)
                // the loaded guard: as if the shell just started and the file is not read yet
                win.keep.before = (json(histPeek) || []).length
                Notif.loaded = false
                Notif.history = []
                const r = send("Early", "Arrived before the file was read")
                check("arrives into an empty in-memory list", r.how === "popup" && Notif.history.length === 1)
                check("guard: the saved file is NOT overwritten with a list of one", (json(histPeek) || []).length === win.keep.before, (json(histPeek) || []).length)
                Notif.reloadHistory()
                return 400
            } },
            { name: "loaded guard: early arrival merged with the saved list", run: function() {
                check("loaded again", Notif.loaded)
                check("history = early one + every saved one", Notif.history.length === win.keep.before + 1, Notif.history.length + " vs " + (win.keep.before + 1))
                check("early one on top", Notif.history[0].app === "Early")
                check("file now has them all", (json(histPeek) || []).length === win.keep.before + 1)
                Notif.reloadHistory()
                return 300
            } },
            { name: "loaded guard: a second read is ignored", run: function() {
                check("no duplicates after reading the file again", Notif.history.length === win.keep.before + 1, Notif.history.length)
                win.reset()
                check("reset: no popups, empty history", Notif.live.length === 0 && Notif.history.length === 0)
                check("popup window hidden while nothing is shown", popupsWin.visible === false)
                check("no cards while nothing is shown", win.cards().length === 0)
                // end to end: the real server on this private bus, sent with gdbus
                gdbus.command = ["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
                                 "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify",
                                 "E2E App", "0", "dialog-information", "Real one", "Through the bus",
                                 "['default', 'Open', 'later', 'Later']", "{}", "600000"]
                gdbus.running = true
                return 1500
            } },
            { name: "end to end: a real notification on the private bus", run: function() {
                check("gdbus Notify answered", win.gdbusCode === 0, win.gdbusCode)
                const e = Notif.history[0]
                check("in history", !!e && e.app === "E2E App" && e.summary === "Real one", JSON.stringify(e))
                check("actions kept (id + text)", !!e && e.actions.length === 2 && e.actions[1].id === "later" && e.actions[1].text === "Later", e ? JSON.stringify(e.actions) : "")
                check("appIcon kept as a name", !!e && e.appIcon === "dialog-information", e ? e.appIcon : "")
                check("urgency kept", !!e && e.urgency === 1)
                check("popup with the live object", Notif.live.length === 1 && Notif.live[0].n !== null)
                check("popup window visible", popupsWin.visible === true, popupsWin.visible + " shown=" + Notif.shown.length)
                check("actions invocable while it is open", !!e && Notif.isLive(e.id) && Notif.invokeAction(e.id, "later"))
                check("invoking an action closes it (not resident)", Notif.live.length === 0)
                win.keep.e2e = e ? e.id : ""
                Notif.dismissAll()
                gdbus.command = ["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
                                 "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify",
                                 "osd", "0", "", "Volume", "40%", "[]", "{'value': <40>}", "1000"]
                gdbus.running = true
                return 1200
            } },
            { name: "end to end: dismissed; osd route untouched", run: function() {
                check("dismissed: no popup", Notif.live.length === 0)
                check("its actions no longer offered", !Notif.isLive(win.keep.e2e) && !Notif.invokeAction(win.keep.e2e, "later"))
                check("osd note reached Osd (text and value)", win.osdNotes === 1 && win.osdText === "Volume: 40%|40", win.osdText)
                check("osd note not in history", Notif.history.length === 1 && Notif.history[0].app === "E2E App")
                win.reset()
                // grouping in popups
                win.keep.chat = [send("Chat", "Ada: hi").n, send("Chat", "Ada: are you there?").n, send("Chat", "Bob: lunch?").n]
                send("Build", "Build finished")
                send("Power", "Battery at 5%", { urgency: 2 })
                return 150
            } },
            { name: "popups: one app's run makes one card", run: function() {
                check("3 groups from 5 notifications", Notif.popupGroups.length === 3, Notif.popupGroups.length)
                check("3 cards", win.cards().length === 3, win.cards().length)
                const c = win.cardFor("Chat")
                check("Chat card counts 3", !!c && c.count === 3)
                check("shows the newest summary", !!c && c.summary === "Bob: lunch?")
                const b = win.find(c, "badge")
                check("badge visible with the count", !!b && b.visible && b.children[0].text.indexOf("3") === 0)
                check("single ones have no badge", !win.find(win.cardFor("Build"), "badge").visible)
                check("newest group on top (Power)", win.cards()[0].app === "Power" || stackView.groups[0].app === "Power")
                check("critical stays its own card", Notif.popupGroups.find(g => g.app === "Power").items.length === 1)
                send("Power", "Battery at 4%", { urgency: 2 })
                check("a second critical is not folded in", Notif.popupGroups.filter(g => g.app === "Power").length === 2)
                win.keep.h = c.height
                ev.mouseClick(b, b.width / 2, b.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
                return 150
            } },
            { name: "popups: the badge expands", run: function() {
                const c = win.cardFor("Chat")
                check("expanded after a click on the badge", !!c && c.open && stackView.expanded[c.modelData] === true)
                check("card grew to show the other two", !!c && c.height > win.keep.h + 30, c ? c.height + " vs " + win.keep.h : "")
                for (const a of ["A1", "A2", "A3", "A4"]) send(a, "Hello from " + a)
                return 150
            } },
            { name: "popups: never more than 5 cards", run: function() {
                check("8 groups live", Notif.popupGroups.length === 8, Notif.popupGroups.length)
                check("5 cards drawn", win.cards().length === 5, win.cards().length)
                check("the newest 5", win.cards().every(c => stackView.groups.some(g => g.key === c.modelData)))
                const g = Notif.popupGroups.find(x => x.app === "Chat")
                Notif.dismissGroup(g.key)
                check("dismissing a card closes all its notifications", win.keep.chat.every(n => n.gone && n.how === "dismissed"))
                check("and only those", Notif.live.length === 7, Notif.live.length)
                win.reset()
                // a gap longer than the window starts a new card
                send("Gap", "first")
                Notif.live = Notif.live.map(i => Object.assign({}, i, { at: i.at - Notif.groupWindowMs - 1000 }))
                send("Gap", "much later")
                check("same app, far apart: two cards", Notif.popupGroups.filter(x => x.app === "Gap").length === 2)
                win.reset()
                send("Short", "goes by itself")
                return 6400
            } },
            { name: "popups: an ordinary card expires after 6 s", run: function() {
                check("expired and gone", Notif.live.length === 0)
                check("still in history", Notif.history.some(e => e.app === "Short"))
                win.reset()
                // the list: grouped by app, newest group first
                win.listOpen = true
                Notif.setDnd(true)
                send("Mail", "m1"); send("Chat", "c1"); send("Mail", "m2"); send("Build", "b1"); send("Mail", "m3")
                Notif.setDnd(false)
                return 200
            } },
            { name: "list: grouped under app headers", run: function() {
                const g = Notif.groups
                check("history stays flat (5 entries)", Notif.history.length === 5 && Notif.history[0].summary === "m3")
                check("3 groups, newest group first", g.length === 3 && g[0].app === "Mail" && g[1].app === "Build" && g[2].app === "Chat", g.map(x => x.app).join(","))
                check("Mail counts 3, entries newest first", g[0].count === 3 && g[0].entries[0].summary === "m3" && g[0].entries[2].summary === "m1")
                check("entries carry their history index", g[0].entries[1].index === 2 && g[2].entries[0].index === 3)
                check("list opened: all marked seen, all fresh", Notif.unseen === 0 && win.listView.fresh === 5, Notif.unseen + " / " + win.listView.fresh)
                check("Notif.apps with counts", Notif.apps.length === 3 && Notif.apps[0].app === "Mail" && Notif.apps[0].count === 3)
                const lst = win.listView
                const groupsView = kids(lst).find(c => c.removing !== undefined)
                win.keep.gv = groupsView
                check("collapsed: one row under Mail", rowsUnder(groupsView, "Mail") === 1)
                groupsView.toggle("Mail")
                return 150
            } },
            { name: "list: expand, forget a group", run: function() {
                const gv = win.keep.gv
                check("expanded: three rows under Mail", rowsUnder(gv, "Mail") === 3)
                // the header's x, as a click
                const x = headerForget(gv, "Mail")
                check("found the header x", !!x)
                if (x) ev.mouseClick(x, x.width / 2, x.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
                return 150
            } },
            { name: "list: group forgotten", run: function() {
                check("Mail gone from history", !Notif.history.some(e => e.app === "Mail"), Notif.history.map(e => e.app).join(","))
                check("others kept", Notif.history.length === 2)
                check("fresh count followed (5 - 3 = 2)", win.listView.fresh === 2, win.listView.fresh)
                check("file follows", (json(histPeek) || []).length === 2)
                // clear / forget / markSeen as before
                Notif.forget(0)
                check("forget(0) drops the newest", Notif.history.length === 1 && Notif.history[0].app === "Chat")
                win.listOpen = false
                Notif.history = Notif.history.map(e => Object.assign({}, e, { seen: false }))
                check("unseen counts", Notif.unseen === 1)
                Notif.markSeen()
                check("markSeen", Notif.unseen === 0 && Notif.history[0].seen === true)
                win.listOpen = true
                // the c key in the list (Bar.qml's handler around the list)
                Notif.setDnd(true); send("K", "one"); send("K", "two"); Notif.setDnd(false)
                check("list has the 'fresh' property Bar.qml sets", typeof win.listView.fresh === "number" && win.listView.fresh > 0)
                keyScope.forceActiveFocus()
                ev.keyClick(Qt.Key_C, Qt.NoModifier, -1)
                return 150
            } },
            { name: "list: c clears all, fresh back to 0", run: function() {
                check("c cleared history", Notif.history.length === 0, Notif.history.length)
                check("fresh = 0", win.listView.fresh === 0)
                check("file empty", (json(histPeek) || [1]).length === 0)
                win.listOpen = false
                Notif.clear()
                // rules
                check("unknown app is normal", Notif.ruleFor("Spam") === "normal")
                check("bad rule refused", Notif.setRule("Spam", "loud") === false)
                Notif.setRule("Spam", "mute"); Notif.setRule("Quiet", "list")
                const a = send("Spam", "buy now")
                check("mute: dropped entirely", a.how === "muted" && Notif.history.length === 0 && Notif.live.length === 0 && !a.n.tracked)
                const b = send("Spam", "server on fire", { urgency: 2 })
                check("mute: critical still pops up and is listed", b.how === "popup" && Notif.history.length === 1 && Notif.live.length === 1)
                const c = send("Quiet", "fyi")
                check("list: no popup, straight to the list", c.how === "listed" && Notif.history[0].app === "Quiet" && Notif.live.length === 1 && !c.n.tracked)
                const d = send("Quiet", "urgent", { urgency: 2 })
                check("list: critical still pops up", d.how === "popup" && Notif.live.length === 2)
                const e = send("Normal", "hello")
                check("normal: popup", e.how === "popup")
                const f = json(rulesPeek)
                check("rules file written", !!f && f.Spam === "mute" && f.Quiet === "list", JSON.stringify(f))
                check("rulesText", Notif.rulesText() === "list\tQuiet\nmute\tSpam", Notif.rulesText())
                check("apps lists a muted app even with nothing in history", Notif.apps.some(x => x.app === "Spam" && x.rule === "mute"))
                check("group carries its rule", Notif.groups.find(g => g.app === "Quiet").rule === "list")
                Notif.setRule("Normal", "list")
                check("setting list on a shown app takes its popup away", !Notif.live.some(i => i.app === "Normal") && e.n.gone)
                Notif.setRule("Spam", "normal")
                check("normal removes the rule", Notif.ruleFor("Spam") === "normal" && !("Spam" in Notif.rules))
                rulesPeek.setText('{"Hand": "list", "Odd": "loud"}\n')
                return 700
            } },
            { name: "rules: a hand edit of the file is picked up", run: function() {
                check("Hand is list", Notif.ruleFor("Hand") === "list", Notif.ruleFor("Hand"))
                check("a bad value is ignored", Notif.ruleFor("Odd") === "normal")
                win.reset()
                // DND
                Notif.setDnd(true)
                const a = send("Any", "quiet please")
                check("DND: listed, no popup, no sound", a.how === "listed" && Notif.live.length === 0)
                const b = send("Any", "fire", { urgency: 2 })
                check("DND: critical pops up", b.how === "popup" && Notif.live.length === 1)
                check("DND: both counted unseen", Notif.unseen === 2, Notif.unseen)
                Notif.setDnd(false)
                check("setDnd off", !Notif.dnd)
                win.reset()
                // snooze from a popup
                const s = send("Snz", "remind me")
                win.keep.snzId = Notif.history[0].id
                win.keep.snzN = s.n
                return 100
            } },
            { name: "snooze: leaves the popup, the list and the count", run: function() {
                Notif.history = Notif.history.map(e => Object.assign({}, e, { seen: false }))
                const before = Notif.unseen
                check("snooze 15 min accepted", Notif.snooze(win.keep.snzId, "15m"))
                check("popup closed", win.keep.snzN.gone && Notif.live.length === 0)
                check("out of history and the unseen count", Notif.history.length === 0 && Notif.unseen === before - 1)
                const s = Notif.snoozed.find(x => x.id === win.keep.snzId)
                check("waiting about 15 min", !!s && Math.abs(s.due - Date.now() - 900000) < 5000)
                const f = json(snzPeek)
                check("in notif-snoozed.json", Array.isArray(f) && f.some(x => x.id === win.keep.snzId))
                const t = new Date(Notif.dueFor("tomorrow"))
                const tm = new Date(); tm.setDate(tm.getDate() + 1)
                check("tomorrow = 08:00 the next day", t.getHours() === 8 && t.getMinutes() === 0 && t.getDate() === tm.getDate())
                check("1 h", Math.abs(Notif.dueFor("1h") - Date.now() - 3600000) < 2000)
                // bring it back soon: one timer for the earliest
                Notif.snooze(win.keep.snzId, Date.now() + 400)
                check("next due is the earliest one", Notif.nextDue <= Date.now() + 400)
                return 900
            } },
            { name: "snooze: back as a popup at its time", run: function() {
                const e = Notif.history.find(x => x.id === win.keep.snzId)
                check("back in history, unseen, marked snoozed", !!e && e.seen === false && e.snoozed === true)
                const it = Notif.live.find(i => i.id === win.keep.snzId)
                check("back as a popup marked snoozed", !!it && it.snoozed && it.n === null)
                check("no longer waiting", !Notif.snoozed.some(x => x.id === win.keep.snzId))
                check("a sound for it", Sys.lastSound === "message")
                win.reset()
                // a group snoozed from its card
                send("Grp", "one"); send("Grp", "two")
                const g = Notif.popupGroups[0]
                Notif.snoozeGroup(g.key, Date.now() + 300)
                check("whole card snoozed", Notif.live.length === 0 && Notif.snoozed.filter(x => x.app === "Grp").length === 2)
                return 800
            } },
            { name: "snooze: a snoozed card comes back as one card", run: function() {
                const gs = Notif.popupGroups.filter(x => x.app === "Grp")
                check("one group of 2, snoozed", gs.length === 1 && gs[0].items.length === 2 && gs[0].snoozed, JSON.stringify(gs.map(x => x.items.length)))
                const c = win.cardFor("Grp")
                const lbl = c ? c.newest.snoozed : false
                check("card marked Snoozed", lbl)
                win.reset()
                // in DND, one comes back to the list only
                send("Dz", "later"); const id = Notif.history[0].id
                Notif.snooze(id, Date.now() + 200)
                Notif.setDnd(true)
                win.keep.dz = id
                return 600
            } },
            { name: "snooze + DND: back in the list, no popup", run: function() {
                check("in history", Notif.history.some(e => e.id === win.keep.dz))
                check("no popup", Notif.live.length === 0)
                Notif.setDnd(false)
                send("Wk", "x"); Notif.snooze(Notif.history[0].id, "1h")
                check("one waiting", Notif.snoozed.length === 1)
                Notif.wakeSnoozed()
                check("Bring back delivers now", Notif.snoozed.length === 0 && Notif.live.length === 1 && Notif.live[0].snoozed)
                check("file emptied", (json(snzPeek) || [1]).length === 0)
                win.reset()
                return 100
            } },
            { name: "picture set-up", run: function() {
                win.listOpen = true
                Notif.setDnd(true)                          // older ones into the list only
                send("Firefox", "Download finished", { body: "syllabus-cpsc2120.pdf" })
                send("Build", "make: done in 41 s")
                send("Calendar", "Office hours in 15 min", { body: "129 McAdams" })
                send("Discord", "#general: 4 new messages")
                Notif.setDnd(false)
                win.listView.fresh = 0
                const long = { expireTimeout: 600000 }
                send("Discord", "Ada: is the lab due Friday?", long)
                send("Discord", "Bob: I think so", long)
                send("Discord", "Ada: thanks!", Object.assign({ body: "see you in class" }, long))
                const a1 = fakeActionC.createObject(win, { identifier: "default", text: "Open" })
                const a2 = fakeActionC.createObject(win, { identifier: "reply", text: "Reply" })
                send("Thunderbird", "3 new messages", Object.assign({ body: "Inbox: course questions", actions: [a1, a2] }, long))
                send("Battery", "Battery at 7%", { urgency: 2, body: "Plug in soon" })
                send("Spotify", "Now playing", Object.assign({ body: "Some song" }, long))
                Notif.snooze(Notif.history.find(e => e.app === "Spotify").id, Date.now() + 200)
                win.keep.spotifyAt = Date.now()
                return 600
            } },
            { name: "picture: expand and open menus", run: function() {
                const c = win.cardFor("Discord")
                if (c) stackView.toggle(c.modelData)
                const t = win.cardFor("Thunderbird")
                if (t) stackView.menuFor = t.modelData
                const gv = kids(win.listView).find(x => x.removing !== undefined)
                gv.toggle("Discord")
                gv.menuApp = "Build"
                check("4 cards for 8 notifications", win.cards().length === 4, win.cards().length)
                return 400
            } },
            { name: "grab dark", run: function() {
                const out = Quickshell.env("NOTIFY_TEST_OUT")
                if (out) stage.grabToImage(r => r.saveToFile(out + "-dark.png"))
                return 400
            } },
            { name: "light", run: function() { Theme.dark = false; return 500 } },
            { name: "grab light", run: function() {
                const out = Quickshell.env("NOTIFY_TEST_OUT")
                if (out) stage.grabToImage(r => r.saveToFile(out + "-light.png"))
                return 500
            } },
            { name: "repeats: the same message is counted, not shown again", run: function() {
                win.listOpen = false                // an open list marks everything seen
                win.reset(); Theme.dark = true
                const s0 = Sys.sounds
                const a = send("Spam", "Disk almost full", { body: "3% left" })
                const b = send("Spam", "Disk almost full", { body: "3% left" })
                const c = send("Spam", "Disk almost full", { body: "3% left" })
                check("first pops up, the rest are repeats", a.how === "popup" && b.how === "repeat" && c.how === "repeat", a.how + b.how + c.how)
                check("one history entry, repeat 3", Notif.history.length === 1 && Notif.history[0].repeat === 3, JSON.stringify(Notif.history))
                check("one popup, repeat 3, holding the newest object", Notif.live.length === 1 && Notif.live[0].repeat === 3 && Notif.live[0].n === c.n)
                check("the older ones closed as expired", a.n.how === "expired" && b.n.how === "expired" && c.n.how === "")
                check("same id all along (history and popup match)", Notif.live[0].id === Notif.history[0].id)
                check("one sound, not three", Sys.sounds - s0 === 1, Sys.sounds - s0)
                check("one unseen, not three", Notif.unseen === 1, Notif.unseen)
                check("saved with its count", ((json(histPeek) || [])[0] || {}).repeat === 3)
                win.keep.spamId = Notif.history[0].id
                return 300
            } },
            { name: "repeats: the card shows ×3", run: function() {
                const card = cardFor("Spam")
                const mark = card ? find(card, "repeat") : null
                check("one card", win.cards().length === 1, win.cards().length)
                check("×3 on it", !!mark && mark.visible && mark.text === "×3", mark ? mark.text : "none")
                check("no group badge (it is one message)", !!card && !find(card, "badge").visible)
                // different body, other app, other urgency: not repeats
                const d = send("Spam", "Disk almost full", { body: "2% left" })
                const e = send("Other", "Disk almost full", { body: "3% left" })
                const f = send("Spam", "Disk almost full", { body: "3% left", urgency: 2 })
                check("different body / app / urgency are new", d.how === "popup" && e.how === "popup" && f.how === "popup", d.how + e.how + f.how)
                check("history 4 entries", Notif.history.length === 4, Notif.history.length)
                // the popup gone, the same message later: counted onto the history entry, a new popup
                Notif.dismissAll()
                const g = send("Spam", "Disk almost full", { body: "3% left" })
                check("after its popup closed: a popup again", g.how === "popup" && Notif.live.length === 1)
                check("history entry now ×4, moved to the top", Notif.history[0].id === win.keep.spamId && Notif.history[0].repeat === 4 && Notif.history.length === 4)
                check("the popup carries ×4", Notif.live[0].repeat === 4)
                // in DND: listed and counted
                Notif.setDnd(true)
                const h = send("Spam", "Disk almost full", { body: "3% left" })
                check("DND: listed, count 5", h.how === "listed" && Notif.history[0].repeat === 5)
                Notif.setDnd(false)
                // (transient is a reserved word in QML, so the stand-in can't carry it: not tested here)
                return 300
            } },
            { name: "repeats: list shows ×N, old files load as 1", run: function() {
                win.listOpen = true
                return 300
            } },
            { name: "repeats: list check", run: function() {
                const row = listView ? (function walk(it) { if (!it) return null; if (it.plain !== undefined && it.modelData && it.modelData.app === "Spam" && it.modelData.repeat === 5) return it
                                                            for (const k of kids(it)) { const r = walk(k); if (r) return r } return null })(listView) : null
                check("list row for the ×5 entry", !!row)
                const txt = row ? [].concat.apply([], kids(row).map(k => kids(k))).filter(t => typeof t.text === "string").map(t => t.text).join("|") : ""
                check("its text says ×5", txt.indexOf("×5") >= 0, txt)
                check("old entries without a count load as 1", Notif.migrate({ app: "x", summary: "y" }).repeat === 1)
                win.listOpen = false
                return 300
            } }
        ]
        // rows shown under an app's header in the grouped list
        function groupItem(gv, app) {
            for (const c of kids(gv)) if (c.modelData && c.modelData.app === app && c.isOpen !== undefined) return c
            return null
        }
        function rowsUnder(gv, app) {
            const g = groupItem(gv, app)
            if (!g) return -1
            return kids(g).filter(c => c.plain !== undefined && c.visible).length
        }
        function headerForget(gv, app) {
            const g = groupItem(gv, app)
            if (!g) return null
            const header = kids(g)[0]
            const texts = kids(header).filter(c => c.text === "×")
            return texts.length ? texts[0] : null
        }

        property int at: 0
        Timer {
            interval: 1500; running: true           // the state files are read first
            onTriggered: {
                if (win.at >= win.cases.length) {
                    console.log("NTEST RESULT pass " + win.passed + " fail " + win.failed)
                    quitSoon.start()
                    return
                }
                const c = win.cases[win.at++]
                console.log("NTEST case: " + c.name)
                let wait = 100
                try { wait = c.run() } catch (e) { win.failed++; console.log("NTEST FAIL " + c.name + " threw: " + e) }
                interval = Math.max(20, wait || 100)
                restart()
            }
        }
        Timer { id: quitSoon; interval: 400; onTriggered: Qt.quit() }
    }
}
