// Reminders for the bar pet: "remind me in 20 minutes" or "at 14:45", with a short note.
// When one comes due a notification goes out with the note, and the pet (Pet.mood "remind")
// runs to the clock and sits there with a mark until you acknowledge it: a click on the pet,
// opening the Reminders page of its menu, or `qs ipc call pet reminddone`. Then a line goes
// in its diary (PetArc.qml).
//
// A due reminder gets the pet up even when it is napping, asleep for the night or asleep
// because Do Not Disturb is on: you set it on purpose. The nap and Do Not Disturb are left as
// they were, so it goes back to sleep once you have seen it. While Do Not Disturb is on the
// notification goes to the list without a popup (only critical ones pop up then) and the
// note is left out of its tooltip and menu, in case the screen is being shared.
//
// No polling: one Timer is armed for the next one due (at most an hour ahead, then it looks
// again) and re-armed when one is added, cancelled, acknowledged, and at start. The bar clock
// (Sys.nowHM, once a minute) also re-arms it, which catches up after the laptop has slept.
// Ones that came due while the shell was down fire one at a time, starting a few seconds
// after start, each after the one before has been acknowledged.
//
//   qs ipc call pet remind WHEN TEXT   WHEN: 20m, 20 min, 1h30, 90s, 14:45, 9:05, 2:30pm, noon
//                                      (a time already past today means tomorrow); prints
//                                      what it understood, or "error: ..." if it did not
//   qs ipc call pet reminders          the pending ones, numbered
//   qs ipc call pet remindcancel N     cancel number N from that list ("all": every one)
//   qs ipc call pet reminddone         acknowledge the one it is showing you
// Kept in ~/.local/state/pet-reminders.json.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: rem

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/pet-reminders.json"
        blockLoading: true
        blockWrites: true           // a change made while an unfinished write was in flight used to be undone when it landed
        printErrors: false
        onAdapterUpdated: saveSoon.restart()
        JsonAdapter {
            id: store
            property string list: "[]"          // JSON [{ id, at: ms since the epoch, note }]
        }
    }
    Timer { id: saveSoon; interval: 300; onTriggered: file.writeAdapter() }

    // ---- what is pending, soonest first ----
    readonly property var pending: {
        let l = []
        try { l = JSON.parse(store.list) } catch (e) {}
        if (!Array.isArray(l)) l = []
        return l.filter(r => r && typeof r.at === "number").sort((a, b) => a.at - b.at)
    }
    readonly property int count: pending.length
    function save(l) { store.list = JSON.stringify(l) }

    // the one it is showing you now ("" none); not kept on disk: after a restart it fires again
    property string ringingId: ""
    readonly property var current: ringingId === "" ? null : (pending.find(r => r.id === ringingId) || null)
    readonly property bool ringing: current !== null
    readonly property string doing: !ringing ? ""
        : Notif.dnd ? "reminding you of something (click it when done)"
        : "reminding you: " + current.note + " (click it when done)"

    // ---- reading WHEN: a pure function, so it can be tested without a clock ----
    // Returns { at, label } or { error }. `now` is ms since the epoch.
    function parseWhen(text, now) {
        const raw = String(text === undefined ? "" : text)
        let s = raw.trim().toLowerCase().replace(/\s+/g, " ")
        if (s === "") return { error: "say when: 20m, 1h30, 14:45 or 2:30pm" }
        const nope = { error: "not understood: \"" + raw.trim().slice(0, 30) + "\". Try 20m, 1h30, 14:45 or 2:30pm" }

        // a time of day: 14:45, 9:05, 2:30pm, 2pm, 2 pm, 14.45, noon, midnight
        let at = s.replace(/^at /, "")
        if (at === "noon") at = "12:00"
        if (at === "midnight") at = "0:00"
        let m = at.match(/^(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a|p|a\.m\.|p\.m\.)?$/)
        if (m && (m[2] !== undefined || m[3] !== undefined)) {
            let h = parseInt(m[1], 10)
            const mi = m[2] !== undefined ? parseInt(m[2], 10) : 0
            const ap = m[3] ? m[3].charAt(0) : ""
            if (mi > 59) return nope
            if (ap !== "") {
                if (h < 1 || h > 12) return nope
                h = h % 12 + (ap === "p" ? 12 : 0)
            } else if (h > 23) return nope
            const d = new Date(now)
            d.setHours(h, mi, 0, 0)
            let tomorrow = false
            if (d.getTime() <= now) { d.setDate(d.getDate() + 1); tomorrow = true }
            return { at: d.getTime(), label: "at " + Qt.formatTime(d, "HH:mm") + (tomorrow ? " tomorrow" : "") }
        }

        // a length of time: 20m, 20 min, 1h30, 1h 30m, 1.5h, 90s, 2 hours, "in 20 minutes", or a bare 20 (minutes)
        let r = s.replace(/^in /, "").replace(/ and /g, " ").replace(/ ?(from now|later)$/, "")
        const re = /(\d+(?:\.\d+)?)\s*([a-z]*)\s*/g
        let ms = 0, pos = 0, last = "", t
        while ((t = re.exec(r)) !== null) {
            if (t.index !== pos || t[0] === "") break
            pos = re.lastIndex
            const n = parseFloat(t[1]), u = t[2]
            let unit
            if (/^(h|hr|hrs|hour|hours)$/.test(u)) unit = "h"
            else if (/^(m|min|mins|minute|minutes)$/.test(u)) unit = "m"
            else if (/^(s|sec|secs|second|seconds)$/.test(u)) unit = "s"
            else if (u === "") unit = last === "h" ? "m" : last === "m" ? "s" : last === "" ? "m" : "?"
            else return nope
            if (unit === "?" || unit === last || (last === "m" && unit === "h") || (last === "s")) return nope
            ms += n * (unit === "h" ? 3600000 : unit === "m" ? 60000 : 1000)
            last = unit
        }
        if (last === "" || pos !== r.length) return nope
        ms = Math.round(ms)
        if (ms < 1000) return { error: "that is no time at all" }
        if (ms > 86400000) return { error: "a day ahead at most" }
        const d = new Date(now + ms)
        return { at: now + ms, label: "in " + span(ms) + " (at " + Qt.formatTime(d, ms < 120000 ? "HH:mm:ss" : "HH:mm") + ")" }
    }
    function span(ms) {
        const s = Math.round(ms / 1000)
        if (s < 120) return s + " s"
        const mi = Math.round(s / 60), h = Math.floor(mi / 60)
        return h === 0 ? mi + " min" : h + " h" + (mi % 60 ? " " + mi % 60 + " min" : "")
    }

    // ---- adding, cancelling, acknowledging ----
    function add(when, note) {
        const p = parseWhen(when, Date.now())
        if (p.error) return "error: " + p.error
        note = String(note || "").replace(/[\x00-\x1f\x7f]+/g, " ").trim().slice(0, 120)
        if (note === "") note = "something you asked me to remind you of"
        const id = Date.now().toString(36) + Math.random().toString(36).slice(2, 6)
        save(pending.concat([{ id: id, at: p.at, note: note }]))
        arm()
        return p.label + ": " + note
    }
    function cancel(id) {
        save(pending.filter(r => r.id !== id))
        if (id === ringingId) { ringingId = ""; gapUntil = Date.now() + 3000 }
        arm()
    }
    function cancelNth(which) {          // for the IPC: 1-based, as `reminders` numbers them, or "all"
        const w = String(which).trim()
        if (w === "all") { const n = count; save([]); ringingId = ""; arm(); return n + " cancelled" }
        const i = parseInt(w, 10) - 1
        if (!(i >= 0 && i < count)) return "error: no reminder " + w + " (there " + (count === 1 ? "is 1" : "are " + count) + ")"
        const r = pending[i]
        cancel(r.id)
        return "cancelled: " + whenText(r) + " " + r.note
    }
    function done() {
        const r = current
        if (!r) return "nothing to acknowledge"
        ringingId = ""
        save(pending.filter(x => x.id !== r.id))
        PetArc.write("Reminded you: " + r.note.slice(0, 60))
        gapUntil = Date.now() + 3000           // the next one waiting (if any) a moment later, not in the same breath
        arm()
        return "done: " + r.note
    }
    function whenText(r) {
        const d = new Date(r.at), today = new Date()
        return Qt.formatTime(d, "HH:mm") + (d.toDateString() === today.toDateString() ? "" : " tmrw")
    }
    function list() {
        if (count === 0) return "no reminders"
        return pending.map((r, i) => (i + 1) + ". " + whenText(r) + "  " + r.note + (r.id === ringingId ? "  (now)" : "")).join("\n")
    }

    // ---- going off ----
    // Single quotes around user-typed text, with any quote inside closed, escaped and reopened:
    // nothing in it ($(...), backticks, ;) reaches the shell as anything but text.
    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    // the notification body is shown as styled text: keep its markup characters literal
    function plain(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    function fire(r) {
        ringingId = r.id
        const app = (Pet.name || "Pet").replace(/[^\w .-]/g, "") || "Pet"
        Sys.run("notify-send -a " + shq(app) + " -i alarm-symbolic " + shq("Reminder") + " " + shq(plain(r.note)))
        Sys.sound("message")
    }

    property bool ready: false
    property double gapUntil: 0
    Timer {
        id: due
        onTriggered: {
            if (rem.ringing) return
            const r = rem.pending.length ? rem.pending[0] : null
            if (r && r.at <= Date.now() + 250) rem.fire(r)
            else rem.arm()
        }
    }
    function arm() {
        due.stop()
        if (ringingId !== "" && !ringing) ringingId = ""      // it was cancelled or is gone
        if (!ready || ringing || count === 0) return
        const now = Date.now()
        const wait = Math.max(pending[0].at - now, gapUntil - now, 0)
        due.interval = Math.max(20, Math.min(wait, 3600000))
        due.start()
    }
    // start a few seconds in, once the bars are laid out (and so a burst of overdue ones does not land on start-up)
    Timer { interval: 5000; running: true; onTriggered: { rem.ready = true; rem.gapUntil = Date.now() + 2000; rem.arm() } }
    Connections {
        target: rem.count > 0 && !rem.ringing ? Sys : null
        function onNowHMChanged() { rem.arm() }
    }
}
