// Tests for calendar-aware Do Not Disturb (QuietCore/Quiet) and Join. NOT part of the shell:
// ~/.local/bin/dayflow-test stages the real QuietCore.qml, Quiet.qml, Join.qml, quiet.js and
// join.js beside this file and the stub Sys, Notif and Icons, then runs it offscreen.
// A "shell reload" is the QuietCore instance being destroyed and a new one created over
// the same state file. Lines: DAYTEST PASS/FAIL ..., last line "DAYTEST RESULT pass N fail M".
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property int passed: 0
    property int failed: 0
    function check(what, ok, detail) {
        if (ok) passed++; else failed++
        console.log("DAYTEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
    }
    readonly property string statePath: Quickshell.env("XDG_STATE_HOME") + "/quiet-state.json"
    property var said: []
    property bool coreOn: false
    readonly property var core: ld.item
    Loader {
        id: ld
        active: root.coreOn
        sourceComponent: QuietCore { settleMs: 100; onAnnounce: (t, s) => root.said = root.said.concat([[t, s]]) }
    }
    FileView { id: rf; path: Quickshell.env("QUIET_RULES"); blockLoading: true; watchChanges: true; onFileChanged: reload(); printErrors: false }

    // ---- made-up days ----
    function ev(start, end, title, extra) {
        return Object.assign({ start: start, end: end, title: title, allday: false, location: "", url: "", date: "2026-11-14", id: "", calendar: "clemson", tags: [] }, extra || {})
    }
    readonly property var lecture: ev("09:30", "10:45", "CPSC 2920 Lecture")
    function offs() { return Notif.calls.filter(c => c === false).length }
    function ons() { return Notif.calls.filter(c => c === true).length }
    function at(hm) { Sys.nowHM = hm }
    function setRules(r) {
        const base = { enabled: true, titles: ["lecture", "class", "exam", "office hours"], calendars: [], tags: ["quiet"], lead: 0 }
        const next = Object.assign({}, base, r)
        core.rules = next
    }
    function reload() { coreOn = false }

    // a case: { name, steps: [fn...] }; each step may return a wait in ms (default 120)
    readonly property var cases: [
        { name: "defaults file is written when missing", steps: [
            () => { rf.reload(); const o = JSON.parse(rf.text()); check("rules.json has the defaults", o.enabled === true && o.titles.indexOf("office hours") >= 0 && o.tags[0] === "quiet" && o.calendars.length === 0 && o.lead === 0, rf.text().replace(/\s+/g, " ")) }
        ] },
        { name: "nothing before the event, DND on at its start, restored at its end", steps: [
            () => { Sys.today = [lecture]; at("09:00") },
            () => { check("before: DND off, not active", !Notif.dnd && !core.active); at("09:30") },
            () => { check("start: DND on", Notif.dnd); check("start: we switched it", core.weSet); check("start: island message", said.length === 1 && said[0][0] === "Quiet until 10:45" && said[0][1] === "CPSC 2920 Lecture", JSON.stringify(said)); at("10:00") },
            () => { check("mid: still on, one message", Notif.dnd && said.length === 1 && ons() === 1); at("10:45") },
            () => { check("end: DND off again", !Notif.dnd && !core.active && offs() === 1); at("11:00") },
            () => { check("after: no second restore", offs() === 1) }
        ] },
        { name: "DND on by hand before: left on at the end", steps: [
            () => { Sys.today = [lecture]; Notif.dnd = true; at("09:30") },
            () => { check("stays on, we did not set it", Notif.dnd && core.active && !core.weSet && ons() === 0); at("10:45") },
            () => { check("still on after the event, never switched off", Notif.dnd && !core.active && offs() === 0) }
        ] },
        { name: "DND turned off by hand during the event: stays off for the rest of it", steps: [
            () => { Sys.today = [lecture]; at("09:30") },
            () => { check("on at start", Notif.dnd); Notif.dnd = false },
            () => { check("released", core.released && !core.weSet); at("10:00") },
            () => { check("not switched back on", !Notif.dnd && ons() === 1); at("10:45") },
            () => { check("end: nothing to restore", !Notif.dnd && offs() === 0 && !core.active) }
        ] },
        { name: "released, then on by hand again: left on at the end", steps: [
            () => { Sys.today = [lecture]; at("09:30") },
            () => { Notif.dnd = false },
            () => { Notif.dnd = true; at("10:00") },
            () => { at("10:45") },
            () => { check("the user's own DND is not switched off", Notif.dnd && offs() === 0) }
        ] },
        { name: "a later event after a hand-off gets quiet again", steps: [
            () => { Sys.today = [lecture, ev("13:00", "13:50", "Office hours")]; at("09:30") },
            () => { Notif.dnd = false; at("10:45") },
            () => { at("13:00") },
            () => { check("second event switches it on", Notif.dnd && core.weSet && said.length === 2, JSON.stringify(said)); at("13:50") },
            () => { check("and off", !Notif.dnd) }
        ] },
        { name: "back-to-back events are one stretch", steps: [
            () => { Sys.today = [ev("09:30", "10:20", "Lecture A"), ev("10:20", "11:10", "Lecture B")]; at("09:30") },
            () => { check("one message so far, until 11:10", said.length === 1 && said[0][0] === "Quiet until 11:10", JSON.stringify(said)); at("10:20") },
            () => { check("handover: still on, never off, no second message", Notif.dnd && offs() === 0 && said.length === 1); at("11:10") },
            () => { check("end: off once", !Notif.dnd && offs() === 1) }
        ] },
        { name: "a gap between events restores and starts again", steps: [
            () => { Sys.today = [ev("09:30", "10:20", "Lecture A"), ev("10:30", "11:10", "Lecture B")]; at("09:30") },
            () => { at("10:20") },
            () => { check("gap: off", !Notif.dnd && offs() === 1); at("10:30") },
            () => { check("B: on again, second message", Notif.dnd && said.length === 2) }
        ] },
        { name: "reload in the middle of the event", steps: [
            () => { Sys.today = [lecture]; at("09:30") },
            () => { check("on", Notif.dnd && said.length === 1); at("10:00"); reload() },
            () => { Notif.dnd = false; root.coreOn = true; Sys.today = []; Sys.todayLoaded = false; return 20 },       // the real Notif starts off until its file is read, and Sys has no agenda yet
            () => { Notif.dnd = true; Sys.today = [lecture]; Sys.todayLoaded = true; return 400 },
            () => { check("after reload: still on, nothing restored, nothing announced again", Notif.dnd && offs() === 0 && said.length === 1 && core.active && core.weSet, JSON.stringify({ calls: Notif.calls, said: said.length, active: core.active, weSet: core.weSet })); at("10:45") },
            () => { check("end after reload: restored exactly once", !Notif.dnd && offs() === 1); reload() },
            () => { root.coreOn = true; return 400 },
            () => { check("a second reload does not restore again", offs() === 1 && !core.active) }
        ] },
        { name: "reload while agenda has not loaded yet does not end the event", steps: [
            () => { Sys.today = [lecture]; at("09:30") },
            () => { at("10:00"); reload() },
            () => { Sys.today = []; Sys.todayLoaded = false; root.coreOn = true; return 500 },
            () => { check("agenda not loaded: DND still on, no restore", Notif.dnd && offs() === 0) },
            () => { Sys.today = [lecture]; Sys.todayLoaded = true },
            () => { check("agenda loaded: still on", Notif.dnd && offs() === 0 && core.active) }
        ] },
        { name: "reload after the event ended: restored once", steps: [
            () => { Sys.today = [lecture]; at("09:30") },
            () => { reload() },
            () => { at("11:00"); root.coreOn = true; return 400 },
            () => { check("restored on the first look", !Notif.dnd && offs() === 1 && !core.active) }
        ] },
        { name: "reload when DND was the user's own: stays on", steps: [
            () => { Sys.today = [lecture]; Notif.dnd = true; at("09:30") },
            () => { reload() },
            () => { root.coreOn = true; return 400 },
            () => { check("still not ours", core.active && !core.weSet); at("10:45") },
            () => { check("still on at the end", Notif.dnd && offs() === 0) }
        ] },
        { name: "skip leaves this event un-silenced", steps: [
            () => { Sys.today = [lecture, ev("13:00", "13:50", "Exam review class")]; at("09:30") },
            () => { check("on", Notif.dnd); const r = core.skip(); check("skip says what", r.indexOf("CPSC 2920") >= 0, r) },
            () => { check("DND restored", !Notif.dnd && !core.active); at("09:45") },
            () => { check("stays off", !Notif.dnd); at("13:00") },
            () => { check("a different event still silences", Notif.dnd) },
            () => { check("skip with nothing current says so", core.skip() !== "" ); at("14:00") },
            () => { check("nothing to skip", core.skip().indexOf("no quiet event") === 0) }
        ] },
        { name: "skip survives a reload", steps: [
            () => { Sys.today = [lecture]; at("09:30") },
            () => { core.skip() },
            () => { reload() },
            () => { root.coreOn = true; return 400 },
            () => { check("still not silenced after the reload", !Notif.dnd && !core.active) }
        ] },
        { name: "disabled: nothing happens", steps: [
            () => { Sys.today = [lecture]; at("09:00"); setRules({ enabled: false }) },
            () => { at("09:30") },
            () => { check("no DND", !Notif.dnd && !core.active && said.length === 0); check("status says off", core.status() === "off") }
        ] },
        { name: "switching it off during an event restores", steps: [
            () => { Sys.today = [lecture]; at("09:30") },
            () => { check("on", Notif.dnd); core.setEnabled(false); return 400 },
            () => { check("off again", !Notif.dnd && !core.active); rf.reload(); check("rules.json now says enabled false", JSON.parse(rf.text()).enabled === false, rf.text().replace(/\s+/g, " ")); core.setEnabled(true); return 400 },
            () => { check("on again at once: the event is still current", Notif.dnd && core.active); rf.reload(); check("rules.json says enabled true", JSON.parse(rf.text()).enabled === true) }
        ] },
        { name: "all-day, endless and non-matching events are ignored", steps: [
            () => { Sys.today = [ev("", "", "Exam week", { allday: true }), ev("09:30", "", "Class with no end"), ev("09:30", "10:30", "Dentist")]; at("09:45") },
            () => { check("nothing", !Notif.dnd && !core.active && said.length === 0) }
        ] },
        { name: "title match is case-insensitive substring", steps: [
            () => { Sys.today = [ev("09:30", "10:30", "MIDTERM EXAM, room 12")]; at("09:45") },
            () => { check("EXAM matches exam", Notif.dnd) }
        ] },
        { name: "calendar and tag rules", steps: [
            () => { Sys.today = [ev("09:30", "10:30", "Standup", { calendar: "teaching" })]; setRules({ calendars: ["Teaching"] }); at("09:45") },
            () => { check("calendar rule", Notif.dnd); at("11:00") },
            () => { check("off after", !Notif.dnd); Sys.today = [ev("12:00", "13:00", "Reading", { tags: ["Quiet", "tentative"] })]; at("12:10") },
            () => { check("tag rule (case-insensitive)", Notif.dnd) }
        ] },
        { name: "lead starts early", steps: [
            () => { Sys.today = [lecture]; setRules({ lead: 5 }); at("09:24") },
            () => { check("five minutes before: not yet", !Notif.dnd); at("09:25") },
            () => { check("lead: on at 09:25", Notif.dnd) }
        ] },
        { name: "status text", steps: [
            () => { Sys.today = [lecture]; at("09:00") },
            () => { check("idle status names the next", core.status().indexOf("next 09:30") >= 0, core.status()); at("09:31") },
            () => { check("active status", core.status().indexOf("quiet until 10:45") === 0, core.status()) }
        ] },
        { name: "resync after something else switched DND off", steps: [
            () => { Sys.today = [lecture]; at("09:30") },
            () => { Notif.dnd = false },
            () => { check("released", core.released); core.resync() },
            () => { check("resync puts it back and we own it again", Notif.dnd && core.weSet && !core.released); at("10:45") },
            () => { check("end restores", !Notif.dnd) }
        ] },
        { name: "singleton wrappers load", steps: [
            () => { check("Quiet.status", typeof Quiet.status() === "string", Quiet.status()) }
        ] }
    ]

    // ---- Join (the singleton) ----
    property var soonSeen: []
    Connections { target: Join; function onSoon(ev) { root.soonSeen = root.soonSeen.concat([ev.title]) } }
    readonly property var joinCases: [
        { name: "join: nothing without a link", steps: [
            () => { Sys.todayLoaded = true; Sys.today = [ev("09:35", "10:00", "No link")]; at("09:30") },
            () => { check("no event, no row", Join.event === null && Join.row() === null) }
        ] },
        { name: "join: starts in 10 minutes shows, 11 does not", steps: [
            () => { Sys.today = [ev("09:40", "10:00", "Advising", { url: "https://x.zoom.us/j/1" })]; at("09:29") },
            () => { check("11 minutes ahead: none", Join.event === null); at("09:30") },
            () => { check("10 minutes ahead: shown", Join.event && Join.phase === "soon"); const r = Join.row(); check("row shape", r && r.label === "Join: Advising" && r.glyph === "C" && typeof r.run === "function" && r.sub.indexOf("in 10 min") >= 0, JSON.stringify(r)) }
        ] },
        { name: "join: under way wins, ended does not", steps: [
            () => { Sys.today = [ev("09:00", "10:00", "Long", { url: "https://a.example/1" }), ev("09:50", "10:30", "Next", { url: "https://b.example/2" })]; at("09:30") },
            () => { check("A is under way, B is 20 away: A", Join.event.title === "Long" && Join.phase === "now"); at("09:45") },
            () => { check("B within 10 but A under way: A", Join.event.title === "Long"); at("10:00") },
            () => { check("A over, B under way", Join.event.title === "Next"); at("10:30") },
            () => { check("everything over", Join.event === null) }
        ] },
        { name: "join: all-day and non-http links are ignored; run opens via xdg-open", steps: [
            () => { Sys.today = [ev("", "", "Conf", { allday: true, url: "https://a.example/1" }), ev("09:30", "10:00", "Odd", { url: "file:///etc/passwd" }), ev("09:30", "10:00", "Real", { url: "https://c.example/3" })]; at("09:35"); Sys.launched = [] },
            () => { check("only the real one", Join.event.title === "Real"); Join.row().run(); check("xdg-open called with the link", JSON.stringify(Sys.launched) === JSON.stringify([["xdg-open", "https://c.example/3"]]), JSON.stringify(Sys.launched)); check("open() refuses file://", Join.open("file:///etc/passwd") === false) }
        ] },
        { name: "join: island signal two minutes before", steps: [
            () => { Sys.today = [ev("11:00", "11:30", "Committee", { url: "https://d.example/4" })]; at("10:56"); return 5200 },
            () => { check("not yet at 4 minutes", root.soonSeen.length === 0); at("10:58") },
            () => { check("signalled at 2 minutes", root.soonSeen.length === 1 && root.soonSeen[0] === "Committee"); at("10:59") },
            () => { check("not signalled twice", root.soonSeen.length === 1); at("11:00") },
            () => { check("not after the start", root.soonSeen.length === 1) }
        ] }
    ]

    property int ci: -1
    property int si: 0
    property var all: []
    property bool joinStarted: false
    function resetFor(c) {
        Notif.dnd = false; Notif.calls = []; said = []
        Sys.today = []; Sys.todayLoaded = true; Sys.nowHM = "08:00"
    }
    Timer {
        id: tick
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (root.ci >= 0 && root.ci < root.all.length) {
                const c = root.all[root.ci]
                if (root.si === -1) {
                    if (!root.coreOn) console.log("DAYTEST case: " + c.name)                               // start of a case: fresh state
                    if (root.coreOn) { root.coreOn = false; interval = 100; return }
                    Quickshell.execDetached(["rm", "-f", root.statePath])
                    root.resetFor(c)
                    root.si = -2; interval = 150; return
                }
                if (root.si === -2) { root.coreOn = true; root.si = 0; interval = 500; return }
                if (root.si < c.steps.length) {
                    let w = 120
                    try { const r = c.steps[root.si](); if (typeof r === "number") w = r } catch (e) { root.check(c.name + " step " + root.si + " threw", false, e) }
                    root.si++; interval = w; return
                }
                root.ci++; root.si = -1; interval = 50; return
            }
            if (root.ci >= root.all.length) {
                console.log("DAYTEST RESULT pass " + root.passed + " fail " + root.failed)
                Qt.quit()
            }
        }
    }
    Component.onCompleted: { all = cases.concat(joinCases); ci = 0; si = -1 }
}
