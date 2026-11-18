// Drives the lock screen (lockscreen.qml + LockView, LockNext, LockInfo, LockPet) for
// qml-overlays-test. The runner copies lockscreen.qml with the session lock switched off (locked:
// false; there is no compositor) and this driver added inside its ShellRoot as `LockDriver { ctl:
// root }`. It shows the real LockView on two screens as plain windows, types into the one with the
// password field, and checks what is drawn and what lockscreen.qml decides. pam-check is a stand-in
// in the temporary HOME. QO_LOCK says which run: "wrong" (dark, fixtures, three failed checks ->
// handover) or "right" (light, empty fixtures, the right password -> unlocked).
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

Scope {
    id: drv
    required property var ctl
    readonly property string run: Quickshell.env("QO_LOCK")
    readonly property string callsPath: Quickshell.env("QO_CALLS")
    property int passed: 0
    property int failed: 0
    function check(what, ok, detail) {
        if (ok) passed++; else failed++
        console.log("QTEST " + (ok ? "PASS " : "FAIL ") + "lock " + run + ": " + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
    }

    readonly property var formScreen: Quickshell.screens.find(s => s.name === "eDP-1") || null
    readonly property var otherScreen: Quickshell.screens.find(s => s.name === "DP-3") || null
    FloatingWindow {
        id: formWin
        visible: true
        implicitWidth: 1920; implicitHeight: 1080
        color: "#16161a"
        LockView { id: formView; anchors.fill: parent; ctl: drv.ctl; screenObj: drv.formScreen }
    }
    FloatingWindow {
        id: otherWin
        visible: true
        implicitWidth: 1440; implicitHeight: 900
        color: "#16161a"
        LockView { id: otherView; anchors.fill: parent; ctl: drv.ctl; screenObj: drv.otherScreen }
    }
    TestEvent { id: ev }
    FileView { id: hand; printErrors: false; blockLoading: true }
    function calls() { hand.path = ""; hand.path = callsPath; return hand.text().split("\n").filter(l => l !== "") }

    function walk(item, f) { if (!item) return; f(item); const k = item.children || []; for (let i = 0; i < k.length; i++) walk(k[i], f) }
    function isText(o) { return o && ("elide" in o) && ("truncated" in o) && ("contentWidth" in o) }
    function texts(item) { const out = []; walk(item, o => { if (isText(o) && o.visible && o.opacity > 0 && String(o.text).trim() !== "") out.push(String(o.text)) }); return out }
    function has(list, s) { return list.some(t => t.indexOf(s) >= 0) }
    function find(item, pred) { let r = null; walk(item, o => { if (!r && pred(o)) r = o }); return r }
    function field(view) { return find(view, o => o.count !== undefined && o.border !== undefined && o.width === 340) }
    // dots drawn: the field's Repeater (old delegates linger as children until deleted)
    function dots(view) { const f = field(view); const r = find(f, o => o.itemAt !== undefined && o.count !== undefined); return r && r.parent.visible ? r.count : 0 }
    function nextItem() { return find(formView, o => o.nextText !== undefined && o.upcoming !== undefined) }
    function infoItem() { return find(formView, o => o.mail !== undefined && o.notes !== undefined && o.track !== undefined) }
    function petItem() { return find(formView, o => o.sheetUrl !== undefined && o.napping !== undefined) }
    function activate() { const q = formView.Window.window; if (q && !q.active) q.requestActivate() }
    function type(s) { activate(); for (const c of s) ev.keyClickChar(c, Qt.NoModifier, -1) }
    function key(k, mods) { activate(); ev.keyClick(k, mods || Qt.NoModifier, -1) }
    function at(h, m) { const d = new Date(); return new Date(d.getFullYear(), d.getMonth(), d.getDate(), h, m) }
    readonly property bool ledOn: Quickshell.env("QO_LED_ON") === "1"

    function common() {
        const t = texts(formView), o = texts(otherView)
        const now = new Date()
        check("both screens draw the clock and date", has(t, Qt.formatDateTime(now, "dddd, MMMM d")) && has(o, Qt.formatDateTime(now, "dddd, MMMM d"))
              && t.some(x => /^\d\d:\d\d$/.test(x)) && o.some(x => /^\d\d:\d\d$/.test(x)), t.join("|"))
        check("the laptop screen has the password field", formView.form && field(formView).visible)
        check("the other screen has no field, no notes", !otherView.form && !field(otherView).visible)
        check("faded in", Math.abs(formView.opacity - 1) < 0.01, formView.opacity)
        check("the field asks for the password", has(t, "Type your password"))
        check("unknown scene falls back to contours", formView.scene === "contours", formView.scene)
    }

    property var steps: run === "wrong" ? wrongSteps : rightSteps
    readonly property var wrongSteps: [
        () => 600,
        () => {
            common()
            check("dark: accent is Clemson orange", Qt.colorEqual(formView.accent, "#f56600"))
            check("Caps Lock (Hyprland says so) is shown", ctl.caps === true && has(texts(formView), "Caps Lock is on"))
            return { until: () => nextItem() && nextItem().events.length > 0 && infoItem() && infoItem().mail > 0, max: 3000 }
        },
        () => {
            const n = nextItem()
            check("next event: read today's and tomorrow's timed events only", n.events.length === 4, n.events.length)
            n.now = at(9, 0)
            const a = n.text
            n.now = at(10, 15)
            const b = n.text
            n.now = at(16, 0)
            const c = n.text
            check("next event: before the first", a === "Next event in 1 h  (10:00)", a)
            check("next event: during one, with the next", b === "Now until 11:00  \u00B7  next in 4 h 15 min  (14:30)", b)
            check("next event: after the last, tomorrow's", c === "Next event in 18 h  (10:00 tomorrow)", c)
            n.now = at(13, 55)
            check("next event: minutes only when under an hour", n.text === "Next event in 35 min  (14:30)", n.text)
            check("next event: never the title (anyone can read a lock screen)", !has(texts(formView), "Secret budget") && !has(texts(formView), "Dentist"))
            const i = infoItem()
            check("info: unread mail summed over inboxes, unseen notifications counted", i.mail === 3 && i.notes === 2, i.mail + "/" + i.notes)
            check("info: counts only, no senders or subjects", has(texts(formView), "3") && !has(texts(formView), "Dean's Office") && !has(texts(formView), "Spring schedule"))
            check("info: nothing playing, no track line", i.track === "")
            const p = petItem()
            check("pet: drawn from pet.json beside the clock", p && p.shown && p.visible, p ? p.shown + "/" + p.visible : "none")
            check("pet: not on the other screen", find(otherView, o => o.sheetUrl !== undefined) === null)
            type("abc")
            check("typing: one dot per character", ctl.typed === "abc" && dots(formView) === 3, ctl.typed.length + "/" + dots(formView))
            check("typing: the prompt text goes", !has(texts(formView), "Type your password"))
            key(Qt.Key_Backspace)
            check("typing: Backspace takes one off", ctl.typed === "ab" && dots(formView) === 2)
            key(Qt.Key_Escape)
            check("typing: Escape clears", ctl.typed === "")
            type("xy"); key(Qt.Key_U, Qt.ControlModifier)
            check("typing: Ctrl+U clears", ctl.typed === "")
            key(Qt.Key_Return)
            check("Enter with nothing typed does nothing", ctl.phase === "idle" && calls().filter(c => c.indexOf("pam-check") === 0).length === 0)
            type("boom"); key(Qt.Key_Return)
            check("Enter: checking, field cleared", ctl.phase === "checking" && ctl.typed === "" && has(texts(formView), "Checking…"))
            return { until: () => ctl.phase !== "checking", max: 3000 }
        },
        () => {
            check("a check that cannot run: error, and says so", ctl.phase === "error" && ctl.fails === 1 && has(texts(formView), "The password check could not run"))
            const pc = calls().filter(c => c.indexOf("pam-check") === 0)
            check("pam-check got the line on stdin, service hyprlock", pc.length === 1 && pc[0] === "pam-check hyprlock len=4 exit=2", pc.join(","))
            check("the password is not kept once sent", ctl.pending === "" && ctl.typed === "")
            type("s")
            check("typing after an error calms the message", ctl.phase === "idle" && ctl.typed === "s")
            type("low"); key(Qt.Key_Return)
            type("zz")
            check("keys while checking are ignored", ctl.phase === "checking" && ctl.typed === "", ctl.typed)
            return { until: () => ctl.phase === "wrong", max: 3000 }
        },
        () => 300,
        () => {
            const t = texts(formView)
            check("wrong: the field's outline turns red", Qt.colorEqual(field(formView).border.color, formView.red), field(formView).border.color)
            check("wrong twice: says one more try, then the standard lock", ctl.fails === 2 && has(t, "That password didn't match (one more try, then the standard lock screen)"), t.join("|"))
            check("wrong: the pet looks puzzled or cross", (() => { const p = petItem(); return p && p.visible })())
            return { until: () => ctl.phase === "idle", max: 3000 }
        },
        () => {
            check("the message calms down by itself", ctl.phase === "idle" && !has(texts(formView), "didn't match"))
            type("nope"); key(Qt.Key_Return)
            return { until: () => ctl.fails === 3, max: 3000 }
        },
        () => {
            check("a third miss hands over (no unlock)", ctl.fails === 3 && !ctl.unlocking)
            return "end"
        }
    ]
    readonly property var rightSteps: [
        () => 600,
        () => {
            common()
            check("light: accent is the light orange", Qt.colorEqual(formView.accent, "#ff8f2e"))
            if (!ledOn) check("Caps Lock off: no warning", ctl.caps === false && !has(texts(formView), "Caps Lock"))
            return { until: () => calls().some(c => c.indexOf("dashboard-data feeds") === 0) && calls().some(c => c.indexOf("agenda") === 0), max: 3000 }
        },
        () => 300,
        () => {
            const n = nextItem(), i = infoItem(), p = petItem()
            check("empty: no events, no next-event line", n && n.events.length === 0 && n.text === "")
            check("empty: no mail, no notifications, no corner line", i && i.mail === 0 && i.notes === 0 && !has(texts(formView), "󰂚"))
            check("empty: no pet.json, no pet", !p || !p.visible)
            type("open sesame")
            check("typing: 11 dots", dots(formView) === 11, dots(formView))
            key(Qt.Key_Enter)
            return { until: () => ctl.unlocking, max: 3000 }
        },
        () => 200,
        () => {
            check("the right password unlocks", ctl.unlocking && ctl.fails === 0)
            check("welcome back, green outline", has(texts(formView), "Welcome back") && Qt.colorEqual(field(formView).border.color, "#5fb36a"))
            type("x")
            check("keys after unlocking are ignored", ctl.typed === "")
            return "end"
        }
    ]
    // lockscreen.qml quits by itself after a handover or an unlock; if it has not in 5 s, say so and stop
    Timer { id: stuck; interval: 5000; onTriggered: { console.log("QTEST note: lock " + drv.run + ": still running 5 s after the end"); Qt.quit() } }
    property int step: 0
    property var waiting: null
    property double waitUntil: 0
    Timer {
        interval: 50; running: true
        onTriggered: {
            if (drv.waiting) {
                let ok = false
                try { ok = drv.waiting() } catch (e) {}
                if (!ok && Date.now() < drv.waitUntil) { restart(); return }
                if (!ok) console.log("QTEST note: lock " + drv.run + ": waited in vain at step " + drv.step)
                drv.waiting = null
            }
            let r = "end"
            if (drv.step < drv.steps.length) {
                try { r = drv.steps[drv.step++]() } catch (e) { drv.failed++; console.log("QTEST FAIL lock " + drv.run + ": step " + drv.step + " threw: " + e + " " + e.stack); r = "end" }
            }
            if (r === "end") { console.log("QTEST RESULT pass " + drv.passed + " fail " + drv.failed); stuck.start(); return }
            if (typeof r === "object") { drv.waiting = r.until; drv.waitUntil = Date.now() + r.max; interval = 40 }
            else interval = r
            restart()
        }
    }
}
