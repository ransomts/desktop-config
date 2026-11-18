// Tests for the charge limit (Charge.qml + charge-profile), the travel reminder (ChargeTravel.qml) and
// break reminders (Breaks.qml, BreaksCore.qml). NOT part of the shell: ~/.local/bin/power-test stages the
// real files beside this one and the stub Sys and Notif, with stub system76-power / agenda-day on PATH.
// Lines: PWRTEST PASS/FAIL ..., last line "PWRTEST RESULT pass N fail M". A "shell reload" is the
// core instance being destroyed and a new one created over the same state file.
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property int passed: 0
    property int failed: 0
    function check(what, ok, detail) {
        if (ok) passed++; else failed++
        console.log("PWRTEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
    }
    readonly property string dir: Quickshell.env("POWER_TEST_DIR")
    function sh(cmd) { Quickshell.execDetached(["sh", "-c", cmd]) }
    // Files are read by a short Python process shortly before each step (a FileView reload answers late):
    // a step sees the files as they were about 80 ms before it ran.
    property var fetched: ({})
    readonly property var watched: ["p76.log", "agenda.log", "notify.log", "power.json", "breaks.json", "state/charge-travel.json", "state/breaks-state.json"]
    function slurp(path) { const k = path.replace(dir + "/", ""); return fetched[k] === undefined ? "" : fetched[k] }
    Process {
        id: fetcher
        command: ["python3", "-I", "-c", "import json,sys,os\nd=sys.argv[1]\nout={}\nfor p in sys.argv[2:]:\n    try: out[p]=open(os.path.join(d,p)).read()\n    except OSError: out[p]=''\nprint(json.dumps(out))", root.dir].concat(root.watched)
        stdout: StdioCollector { onStreamFinished: { try { root.fetched = JSON.parse(text) } catch (e) {} } }
    }
    Timer { id: pf; onTriggered: if (!fetcher.running) fetcher.running = true }
    function p76calls() { return slurp(dir + "/p76.log").split("\n").filter(l => l === "charge-thresholds").length }

    // ================= Charge.qml =================
    readonly property var chargeCases: [
        { name: "charge: read at start", steps: [
            () => { Charge.status() },
            () => 700,
            () => {
                check("loaded", Charge.loaded)
                check("full charge profile and thresholds", Charge.profile === "full_charge" && Charge.start === 90 && Charge.end === 100, Charge.status())
                check("plain name", Charge.label === "Full charge", Charge.label)
                check("not limited, no tooltip line", !Charge.limited && Charge.tip === "")
                check("percentages from the tool's list", Charge.nameOf("balanced") === "Balanced (stops at 90%)" && Charge.nameOf("max_lifespan") === "Longest life (stops at 60%)", Charge.nameOf("balanced") + " | " + Charge.nameOf("max_lifespan"))
                check("profile list parsed", Object.keys(Charge.profiles).length === 3 && Charge.profiles.balanced.end === 90 && Charge.profiles.max_lifespan.end === 60)
            }
        ] },
        { name: "charge: set balanced", steps: [
            () => { Charge.set("balanced"); check("busy while waiting", Charge.busy) },
            () => 500,
            () => {
                check("not busy any more", !Charge.busy)
                check("profile balanced 86-90", Charge.profile === "balanced" && Charge.start === 86 && Charge.end === 90, Charge.status())
                check("limited, label and tooltip line", Charge.limited && Charge.label === "Balanced (stops at 90%)" && Charge.tip === "Charging stops at 90%", Charge.tip)
                check("no error", Charge.error === "" && Charge.changes === 1)
                check("a second set while busy is ignored, one call per change", slurp(dir + "/p76.log").split("\n").filter(l => l === "charge-thresholds --profile balanced").length === 1)
            }
        ] },
        { name: "charge: next cycles", steps: [
            () => { Charge.next() },
            () => 500,
            () => { check("balanced -> longest life", Charge.profile === "max_lifespan" && Charge.tip === "Charging stops at 60%" && Charge.label === "Longest life (stops at 60%)", Charge.status()); Charge.next() },
            () => 500,
            () => { check("longest life -> full", Charge.profile === "full_charge" && !Charge.limited && Charge.tip === "", Charge.status()) }
        ] },
        { name: "charge: refused authorisation", steps: [
            () => { sh("touch '" + dir + "/deny'") },
            () => 150,
            () => { Charge.set("balanced") },
            () => 500,
            () => {
                check("profile unchanged", Charge.profile === "full_charge" && !Charge.limited, Charge.status())
                check("error says not changed, not busy", Charge.error === "not changed" && !Charge.busy, Charge.error)
                sh("rm -f '" + dir + "/deny'")
            }
        ] },
        { name: "charge: toggle between the cap and full", steps: [
            () => { Charge.toggle(); check("busy while waiting", Charge.busy) },
            () => 500,
            () => {
                check("full -> cap: custom 70-80", Charge.profile === "custom" && Charge.start === 70 && Charge.end === 80, Charge.status())
                check("capped, limited, label and tooltip line", Charge.capped && Charge.limited && Charge.cap === 80 && Charge.label === "Stops at 80%" && Charge.tip === "Charging stops at 80%", Charge.label + " | " + Charge.tip)
                Charge.toggle()
            },
            () => 500,
            () => { check("cap -> full", Charge.profile === "full_charge" && !Charge.limited && !Charge.capped, Charge.status()); Charge.set("cap") },
            () => 500,
            () => { check("set(\"cap\") works too", Charge.capped, Charge.status()); Charge.set("full_charge") },
            () => 500,
            () => check("back to full for the next case", Charge.profile === "full_charge", Charge.status())
        ] },
        { name: "charge: bad names are ignored", steps: [
            () => { const n = Charge.changes; Charge.set("turbo"); Charge.set(""); Charge.set("balanced; rm -rf ~"); root.mark = n },
            () => 300,
            () => check("nothing ran", Charge.changes === root.mark && !Charge.busy && Charge.profile === "full_charge")
        ] },
        { name: "charge: read again when the panel opens, not polled", steps: [
            () => { sh("echo max_lifespan > '" + dir + "/p76.state'"); root.mark = p76calls() },
            () => 1500,
            () => { check("no polling in 1.5 s", p76calls() === root.mark && Charge.profile === "full_charge", p76calls() + " vs " + root.mark); Sys.panelOpen = true },
            () => 500,
            () => { check("panel open: profile read again", Charge.profile === "max_lifespan" && Charge.end === 60, Charge.status()); Sys.panelOpen = false; root.mark = p76calls() },
            () => 300,
            () => check("panel close reads nothing", p76calls() === root.mark),
            () => { sh("echo balanced > '" + dir + "/p76.state'") }
        ] }
    ]
    property int mark: 0

    // ================= ChargeTravel.qml =================
    property var asked: []
    property bool trOn: false
    property string trDate: "2026-11-14"
    readonly property var tr: trLoader.item
    Loader {
        id: trLoader
        active: root.trOn
        sourceComponent: ChargeTravel { dateOverride: root.trDate; onAsk: (t, d) => root.asked = root.asked.concat([[t, d]]) }
    }
    function agendaCalls() { return slurp(dir + "/agenda.log").split("\n").filter(l => l !== "") }
    function tomorrow(events) { sh("printf '%s' '" + JSON.stringify(events).replace(/'/g, "") + "' > '" + dir + "/agenda-2026-11-15.json'") }
    function ev(title, allday, start) { return { start: allday ? "" : (start || "09:00"), end: allday ? "" : "10:00", title: title, allday: allday, location: "", url: "", date: "2026-11-15", id: "", calendar: "", tags: [] } }
    function setCfg(o) { sh("printf '%s' '" + JSON.stringify(o) + "' > '" + dir + "/power.json'") }
    readonly property var travelCases: [
        { name: "travel: pure match", steps: [
            () => 100,
            () => {
                const t = tr
                check("case-insensitive substring", t.match([ev("Flight DL123 to DEN", false)], ["flight"]) !== null)
                check("all-day counts", t.match([ev("Conference: SIGCSE", true)], ["flight", "conference"]).title === "Conference: SIGCSE")
                check("no words, no match", t.match([ev("Flight", false)], []) === null && t.match([ev("Dentist", false)], ["flight", "travel"]) === null)
                check("first matching event wins", t.match([ev("Dentist", false), ev("Travel day", true), ev("Flight", false)], ["flight", "travel"]).title === "Travel day")
                check("empty or odd input", t.match(null, ["x"]) === null && t.match([{}], ["x"]) === null)
            }
        ] },
        { name: "travel: settings file written with defaults, reminder off", steps: [
            () => 400,
            () => {
                const c = JSON.parse(slurp(dir + "/power.json"))
                check("defaults file", c.remind === false && c.travelWords.join() === "flight,travel,conference" && c.eveningAt === "19:00", JSON.stringify(c))
                check("remind is off by default", tr.cfg.remind === false)
            }
        ] },
        { name: "travel: off means off", steps: [
            () => { Sys.nowHM = "20:00"; tomorrow([ev("Flight to Denver", false)]) },
            () => 600,
            () => check("limit on, evening, travel tomorrow, remind false: nothing asked, agenda not even read", Charge.limited && asked.length === 0 && agendaCalls().length === 0, JSON.stringify(asked) + agendaCalls().join())
        ] },
        { name: "travel: asks once, in the evening, for tomorrow", steps: [
            () => { setCfg({ travelWords: ["flight", "travel", "conference"], remind: true, eveningAt: "19:00" }) },
            () => { Sys.nowHM = "18:59" },
            () => { Sys.nowHM = "19:00" },
            () => 800,
            () => {
                check("config loaded as on", tr.cfg.remind === true)
                check("the agenda was read for tomorrow only", agendaCalls().join() === "2026-11-15", agendaCalls().join())
                check("one ask with the event and the date", asked.length === 1 && asked[0][0] === "Flight to Denver" && asked[0][1] === "2026-11-15", JSON.stringify(asked))
                check("the answer is remembered", JSON.parse(slurp(dir + "/state/charge-travel.json")).asked === "2026-11-15")
                Sys.nowHM = "19:01"
            },
            () => 500,
            () => { check("a later minute does not ask again", asked.length === 1 && agendaCalls().length === 1); Sys.nowHM = "23:00" },
            () => 500,
            () => check("still once at 23:00", asked.length === 1)
        ] },
        { name: "travel: not before the evening", steps: [
            () => { asked = []; sh("rm -f '" + dir + "/state/charge-travel.json' '" + dir + "/agenda.log'"); tr.askedFor = ""; Sys.nowHM = "18:59" },
            () => 500,
            () => { check("18:59: nothing", asked.length === 0 && agendaCalls().length === 0); Sys.nowHM = "19:00" },
            () => 700,
            () => check("19:00: asks", asked.length === 1)
        ] },
        { name: "travel: no limit, no ask", steps: [
            () => { asked = []; tr.askedFor = ""; sh("echo full_charge > '" + dir + "/p76.state'"); Sys.panelOpen = true },
            () => 500,
            () => { Sys.panelOpen = false; check("full charge now", !Charge.limited); Sys.nowHM = "19:05" },
            () => 500,
            () => { check("full charge: nothing asked or read", asked.length === 0 && agendaCalls().length === 1, agendaCalls().join()); sh("echo balanced > '" + dir + "/p76.state'"); Sys.panelOpen = true },
            () => 500,
            () => { Sys.panelOpen = false; check("limit back on: asks at once (it is evening and not yet asked)", Charge.limited && asked.length === 1, JSON.stringify(asked)) }
        ] },
        { name: "travel: all-day event matches; nothing matching: no ask but handled", steps: [
            () => { asked = []; tr.askedFor = ""; tomorrow([ev("Faculty meeting", false), ev("Conference: SIGCSE", true)]); Sys.nowHM = "19:10" },
            () => 700,
            () => { check("all-day conference asks", asked.length === 1 && asked[0][0] === "Conference: SIGCSE", JSON.stringify(asked)); asked = []; tr.askedFor = ""; tomorrow([ev("Dentist", false)]); Sys.nowHM = "19:11" },
            () => 700,
            () => { check("no travel word: no ask", asked.length === 0); check("but tomorrow is marked handled", tr.askedFor === "2026-11-15") }
        ] },
        { name: "travel: a shell reload does not ask twice", steps: [
            () => { asked = []; sh("printf '%s' '" + JSON.stringify([ev("Flight", false)]) + "' > '" + dir + "/agenda-2026-11-21.json'"); root.trDate = "2026-11-20"; Sys.nowHM = "19:20" },   // a new day: the state file really changes
            () => 700,
            () => { check("asked", asked.length === 1 && asked[0][1] === "2026-11-21", JSON.stringify(asked)); root.mark = 0 },
            () => 400,
            () => { root.trOn = false },
            () => 300,
            () => { root.trOn = true },
            () => 600,
            () => { Sys.nowHM = "19:21" },
            () => 700,
            () => check("new instance, same state: silent", asked.length === 1, JSON.stringify(asked) + " state=" + slurp(dir + "/state/charge-travel.json") + " agenda=" + agendaCalls().join())
        ] }
    ]

    // ================= Breaks =================
    property var nudges: []
    property bool brOn: false
    readonly property var br: brLoader.item
    Loader {
        id: brLoader
        active: root.brOn
        sourceComponent: BreaksCore { pollMs: 3600000; onNudge: m => root.nudges = root.nudges.concat([m]) }
    }
    property real clock: 1800000000000
    property real sumNow: 1000
    // minutes of activity (a changing sum) or of nothing (the same sum); every call is one minute
    function minute(active) { clock += 60000; if (active) sumNow += 3; br.step(clock, sumNow) }
    function work(n) { for (let i = 0; i < n; i++) minute(true) }
    function rest(n) { for (let i = 0; i < n; i++) minute(false) }
    function enable() { br.setKey("enabled", "on"); br.step(clock += 60000, sumNow) }     // switching on: the first minute is a baseline
    function reload() { brOn = false }
    readonly property var breakCases: [
        { name: "breaks: off by default, nothing happens", steps: [
            () => 500,
            () => {
                check("disabled out of the box", br.enabled === false && br.workMinutes === 50 && br.restMinutes === 5 && br.snoozeMinutes === 15)
                check("defaults file written", JSON.parse(slurp(dir + "/breaks.json")).enabled === false)
                work(80)
                check("80 active minutes while disabled: no count, no nudge", br.workMin === 0 && nudges.length === 0 && br.line === "")
                check("status says off", br.status().indexOf("off") === 0, br.status())
            }
        ] },
        { name: "breaks: nudge exactly at the limit", steps: [
            () => { enable(); work(1) },
            () => {
                check("on: baseline minute counted nothing, first active minute is 1", br.workMin === 1, br.workMin)
                work(48)
                check("49 active minutes: quiet", br.workMin === 49 && nudges.length === 0)
                check("dashboard line", br.line === "Working for 49 min", br.line)
                work(1)
                check("50th active minute: one nudge saying 50", nudges.length === 1 && nudges[0] === 50, JSON.stringify(nudges))
            }
        ] },
        { name: "breaks: snooze, then again", steps: [
            () => { work(14) },
            () => {
                check("14 more minutes (snooze 15): silent", nudges.length === 1, JSON.stringify(nudges))
                work(1)
                check("15 minutes after the first: second nudge says 65", nudges.length === 2 && nudges[1] === 65, JSON.stringify(nudges))
            }
        ] },
        { name: "breaks: a real break resets silently", steps: [
            () => { rest(4) },
            () => { check("4 minutes of rest: not a break yet", br.workMin === 65); rest(1) },
            () => { check("5th minute: count back to 0, no message", br.workMin === 0 && nudges.length === 2 && br.line === ""); work(49) },
            () => check("after a break it takes the full 50 again", nudges.length === 2 && br.workMin === 49),
            () => { work(1) },
            () => check("nudge at 50, the snooze of the old stretch is gone", nudges.length === 3 && nudges[2] === 50, JSON.stringify(nudges))
        ] },
        { name: "breaks: a short pause is not a break", steps: [
            () => { br.reset(); nudges = []; work(30); rest(4); work(1) },
            () => check("4 minutes away: stretch goes on (31 active minutes)", br.workMin === 31 && br.restRun === 0, br.workMin + "/" + br.restRun),
            () => { work(18) },
            () => check("49", br.workMin === 49 && nudges.length === 0),
            () => { work(1) },
            () => check("50 active minutes in all, pauses did not count: nudge", nudges.length === 1 && nudges[0] === 50, JSON.stringify(nudges))
        ] },
        { name: "breaks: presenting holds it back", steps: [
            () => { br.reset(); nudges = []; br.forcePresenting = true; work(55) },
            () => { check("no nudge while presenting, count carries on", nudges.length === 0 && br.workMin === 55 && br.reason === "presenting", br.status()); br.forcePresenting = false; work(1) },
            () => check("the first minute after: nudge with the real count", nudges.length === 1 && nudges[0] === 56, JSON.stringify(nudges))
        ] },
        { name: "breaks: a call holds it back (mic, then camera)", steps: [
            () => { br.reset(); nudges = []; Sys.micInUse = true; work(51) },
            () => { check("mic in use: no nudge", nudges.length === 0 && br.reason === "call"); Sys.micInUse = false; Sys.videoInUse = true; work(1) },
            () => { check("camera in use: no nudge", nudges.length === 0 && br.reason === "call"); Sys.videoInUse = false; work(1) },
            () => check("call over: nudge", nudges.length === 1 && nudges[0] === 53, JSON.stringify(nudges))
        ] },
        { name: "breaks: Do Not Disturb holds it back", steps: [
            () => { br.reset(); nudges = []; Notif.dnd = true; work(60) },
            () => { check("DND on: no nudge", nudges.length === 0 && br.reason === "dnd"); Notif.dnd = false; work(1) },
            () => check("DND off: nudge", nudges.length === 1)
        ] },
        { name: "breaks: nothing held back means a nudge, the snooze setting is read", steps: [
            () => { br.reset(); nudges = []; br.setKey("snoozeMinutes", "30"); br.setKey("workMinutes", "10"); work(10) },
            () => { check("workMinutes 10: nudge at 10", nudges.length === 1 && nudges[0] === 10); work(29) },
            () => { check("29 minutes later (snooze 30): silent", nudges.length === 1); work(1) },
            () => check("30 minutes later: nudge", nudges.length === 2 && nudges[1] === 40, JSON.stringify(nudges)),
            () => { br.setKey("workMinutes", "50"); br.setKey("snoozeMinutes", "15") }
        ] },
        { name: "breaks: a gap in the minutes (suspend) is a break", steps: [
            () => { br.reset(); nudges = []; work(40); clock += 30 * 60000; sumNow += 5; br.step(clock, sumNow) },
            () => check("30 minutes nobody looked, then input: stretch starts over at 1", br.workMin === 1 && nudges.length === 0, br.workMin),
            () => { clock += 3 * 60000; sumNow += 5; br.step(clock, sumNow) },
            () => check("a 3 minute gap is not a break", br.workMin === 2, br.workMin)
        ] },
        { name: "breaks: reload mid-session keeps the count and does not nudge", steps: [
            () => { br.reset(); nudges = []; work(20) },
            () => 400,
            () => { reload() },
            () => 300,
            () => { root.brOn = true },
            () => 600,
            () => { check("count restored from the state file", br.workMin === 20 && br.enabled, br.workMin); check("nothing nudged at load", nudges.length === 0); work(1) },
            () => check("carries on at 21", br.workMin === 21 && nudges.length === 0, br.workMin + " " + br.restRun + " lt=" + br.lastTick + " clock=" + clock + " tot=" + br.lastTotal + " sum=" + sumNow + " st=" + slurp(dir + "/state/breaks-state.json")),
            () => { work(28) },
            () => { check("49 after the reload", br.workMin === 49 && nudges.length === 0); reload() },
            () => 300,
            () => { root.brOn = true },
            () => 600,
            () => { work(1) },
            () => { check("reload at 49: the next minute nudges once", nudges.length === 1 && nudges[0] === 50, JSON.stringify(nudges)); reload() },
            () => 300,
            () => { root.brOn = true },
            () => 600,
            () => { check("reload after a nudge: still no nudge at load", nudges.length === 1); work(1) },
            () => check("and the snooze survived: the next minute is quiet", nudges.length === 1 && br.workMin === 51, JSON.stringify(nudges)),
            () => 400
        ] },
        { name: "breaks: reload after a long time away starts over", steps: [
            () => { reload() },
            () => 300,
            () => { sh("sed -i 's/\"lastTick\":[0-9]*/\"lastTick\":" + (clock - 3 * 3600000) + "/' '" + dir + "/state/breaks-state.json'") },
            () => { root.brOn = true },
            () => 600,
            () => { clock += 60000; sumNow += 1; br.step(clock, sumNow) },
            () => check("three hours later the old stretch is gone", br.workMin === 1 && nudges.length === 1, br.workMin)
        ] },
        { name: "breaks: IPC-style commands", steps: [
            () => {
                check("bad key", br.setKey("colour", "red").indexOf("unknown key") === 0)
                check("bad number", br.setKey("workMinutes", "abc").indexOf("whole number") >= 0 && br.setKey("workMinutes", "0").indexOf("whole number") >= 0 && br.setKey("restMinutes", "601").indexOf("whole number") >= 0 && br.workMinutes === 50)
                check("bad switch", br.setKey("enabled", "maybe").indexOf("on or off") >= 0 && br.enabled)
                br.setKey("restMinutes", "7")
                check("set restMinutes", br.restMinutes === 7 && br.status().indexOf("break 7") > 0, br.status())
            },
            () => 300,
            () => {
                check("saved to the file", JSON.parse(slurp(dir + "/breaks.json")).restMinutes === 7)
                br.setKey("restMinutes", "5")
                br.reset(); check("reset", br.workMin === 0 && br.line === "")
                br.setKey("enabled", "off")
                check("off", !br.enabled && br.status().indexOf("off") === 0)
                const n = br.workMin; work(60)
                check("off again: nothing counts", br.workMin === n && br.workMin === 0)
            },
            () => 300,
            () => check("file says disabled", JSON.parse(slurp(dir + "/breaks.json")).enabled === false)
        ] },
        { name: "breaks: the real counter files (polled, totals only)", steps: [
            () => { root.brOn = false },
            () => 300,
            () => { sh("rm -f '" + dir + "/state/breaks-state.json'; mkdir -p '" + dir + "/stats'; echo '{\"keys\":{\"KEY_A\":10,\"Ctrl+KEY_C\":2},\"bigrams\":{\"KEY_A KEY_B\":99},\"saved\":\"2026-11-14 09:00\"}' > '" + dir + "/stats/counts.json'; echo '{\"actions\":{\"touchpad tap on desktop -> nothing\":5},\"targets\":{\"x\":500}}' > '" + dir + "/stats/mouse.json'") },
            () => { root.brOn = true },
            () => 600,
            () => { br.setKey("enabled", "on"); br.poll() },
            () => 400,
            () => { check("first poll: baseline of keys 12 + mouse 5, no work", br.keyTotal === 12 && br.mouseTotal === 5 && br.workMin === 0, br.keyTotal + "/" + br.mouseTotal + "/" + br.workMin) },
            () => { sh("echo '{\"keys\":{\"KEY_A\":10,\"Ctrl+KEY_C\":2},\"bigrams\":{\"KEY_A KEY_B\":99},\"saved\":\"2026-11-14 09:01\"}' > '" + dir + "/stats/counts.json'") },
            () => 300,
            () => { br.poll() },
            () => 400,
            () => { check("file rewritten with new mtime and 'saved', same counts: not activity", br.workMin === 0 && br.restRun === 2, br.workMin + "/" + br.restRun); sh("echo '{\"actions\":{\"touchpad tap on desktop -> nothing\":6},\"targets\":{\"x\":501}}' > '" + dir + "/stats/mouse.json'") },
            () => 300,
            () => { br.poll() },
            () => 400,
            () => check("one more click: active minute", br.workMin === 1 && br.restRun === 0, br.workMin + "/" + br.restRun),
            () => { sh("rm -f '" + dir + "/stats/counts.json'") },
            () => 300,
            () => { br.poll() },
            () => 400,
            () => check("a missing counter file counts as zero, is not activity and does not wedge it", br.keyTotal === 0 && br.waiting === 0 && br.workMin === 1, br.keyTotal + "/" + br.waiting + "/" + br.workMin)
        ] },
        { name: "breaks: presenting file is read", steps: [
            () => { br.reset(); nudges = []; sh("touch '" + dir + "/run/presenting'"); br.setKey("workMinutes", "5") },
            () => 300,
            () => { br.checkPresenting() },
            () => 400,
            () => { check("file seen", br.presenting); work(6); check("held back while the file exists", nudges.length === 0 && br.reason === "presenting"); sh("rm -f '" + dir + "/run/presenting'") },
            () => 300,
            () => { br.checkPresenting() },
            () => 400,
            () => { check("file gone", !br.presenting); work(1) },
            () => { check("nudge after", nudges.length === 1, JSON.stringify(nudges)); br.setKey("workMinutes", "50"); br.setKey("enabled", "off") },
            () => 300
        ] }
    ]

    property var all: []
    property int ci: -1
    property int si: -1
    Timer {
        id: tick
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (root.ci >= 0 && root.ci < root.all.length) {
                const c = root.all[root.ci]
                if (root.si === -1) {
                    console.log("PWRTEST case: " + c.name)
                    if (c.name.indexOf("travel") === 0 && !root.trOn) { root.trOn = true; interval = 500; return }
                    if (c.name.indexOf("breaks") === 0 && !root.brOn) { root.brOn = true; interval = 700; return }
                    root.si = 0; interval = 50; return
                }
                if (root.si < c.steps.length) {
                    let w = 120
                    try { const r = c.steps[root.si](); if (typeof r === "number") w = r } catch (e) { root.check(c.name + " step " + root.si + " threw", false, e) }
                    root.si++; interval = w; pf.interval = Math.max(20, w - 80); pf.restart(); return
                }
                root.ci++; root.si = -1; interval = 50; return
            }
            if (root.ci >= root.all.length) {
                console.log("PWRTEST RESULT pass " + root.passed + " fail " + root.failed)
                Qt.quit()
            }
        }
    }
    Component.onCompleted: { all = chargeCases.concat(travelCases, breakCases); ci = 0; si = -1 }
}
