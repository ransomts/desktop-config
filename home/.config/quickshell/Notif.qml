pragma Singleton
// Notifications: Quickshell is the notification daemon (in place of mako).
// Popups are drawn by NotifPopups.qml (cards from NotifStack.qml), the list under
// the bell pill by NotifList.qml, the control panel's recent list by NotifGroups.qml.
//   qs ipc call notif dnd | setDnd true|false | toggleDnd | clear | forget N | dismissAll
//   qs ipc call notif rule APP mute|list|normal | rules | snoozed
//
// Every incoming notification enters through ingest(n) (the server's handler calls it;
// tests call it with stand-in objects). Per notification:
//   appName "osd"            -> osdNote (Osd.qml), nothing else
//   app rule "mute"          -> dropped entirely, unless critical
//   transient                -> popup only, never in history
//   DND, or app rule "list"  -> history only, no popup, unless critical
//   otherwise                -> history + popup (grouped by app when they come close together)
// Repeats (same app, title, body and urgency as one already in the history or on screen)
// are counted, not shown again: the entry moves to the top with repeat N, its popup is
// replaced by the new one (old one closed as expired), and no second sound plays while it
// is still on screen. The journal record (shell-log) still gets every one.
//
// State files in $XDG_STATE_HOME (all written only after they were read once):
//   notif-history.json  [ {id, app, summary, body, critical, seen, time, at, urgency,
//                           actions: [{id, text}], image, appIcon, snoozed?, repeat}, ... ] newest first
//                         (older entries with only {app, summary, body, critical, seen, time} load fine)
//   notif-snoozed.json  [ {id, app, summary, body, critical, urgency, image, appIcon, time, due}, ... ]
//   notif-rules.json    { "App Name": "mute" | "list" | "normal", ... }  (hand edits are picked up)
//   notif-dnd           on | off
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Singleton {
    id: notif

    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"

    // ---- Do Not Disturb: only critical notifications pop up; the rest go straight to the list ----
    property bool dnd: false
    readonly property string dndFile: stateDir + "/notif-dnd"
    function setDnd(on) {
        if (dnd === on) return
        dnd = on
        Quickshell.execDetached(["sh", "-c", "echo " + (on ? "on" : "off") + " > '" + dndFile + "'"])
        Sys.refreshSoon()
    }
    FileView {
        path: notif.dndFile
        printErrors: false
        onLoaded: notif.dnd = text().trim() === "on"
    }

    signal osdNote(string text, int percent)

    property int seq: 0
    function newId() { seq++; return "n" + Date.now().toString(36) + "-" + seq }

    // ---- recent notifications, newest first; saved so a restart doesn't lose them ----
    readonly property int historyCap: 40
    property var history: []
    // unseen: arrived since the list was last opened (bell pill popup or control panel); the pill shows the count
    readonly property int unseen: history.filter(e => e.seen === false).length
    readonly property bool unseenCritical: history.some(e => e.seen === false && e.critical)
    function markSeen() {
        if (unseen === 0) return
        history = history.map(e => e.seen === false ? Object.assign({}, e, { seen: true }) : e)
        save()
    }
    function clear() { history = []; save() }
    function forget(index) { const h = history.slice(); h.splice(index, 1); history = h; save() }
    function forgetGroup(app) { history = history.filter(e => e.app !== app); save() }
    // Nothing is written until the saved list has been read: a notification that
    // arrives in the moment after a reload would otherwise save a list of one
    // over the whole history (lost that way on 2026-11-11).
    property bool loaded: false
    function save() { if (loaded) historyFile.setText(JSON.stringify(history)) }
    function reloadHistory() { historyFile.reload() }        // tests: read the file again (a no-op once loaded)
    // an entry from the file, in today's shape (fields added 2026-11-14 get defaults)
    function migrate(e) {
        const str = v => typeof v === "string" ? v : ""
        const critical = !!e.critical
        return {
            id: str(e.id) !== "" ? e.id : newId(),
            app: str(e.app), summary: str(e.summary), body: str(e.body),
            critical: critical,
            seen: e.seen === false ? false : true,
            time: str(e.time),
            at: typeof e.at === "number" ? e.at : 0,
            urgency: typeof e.urgency === "number" ? e.urgency : critical ? 2 : 1,
            actions: Array.isArray(e.actions) ? e.actions.filter(a => a && a.id !== undefined).map(a => ({ id: String(a.id), text: String(a.text || "") })) : [],
            image: str(e.image), appIcon: str(e.appIcon),
            snoozed: e.snoozed === true,
            repeat: typeof e.repeat === "number" && e.repeat > 1 ? Math.floor(e.repeat) : 1
        }
    }
    FileView {
        id: historyFile
        path: notif.stateDir + "/notif-history.json"
        blockWrites: true
        printErrors: false
        onLoaded: {
            if (notif.loaded) return
            let saved = []
            try { const h = JSON.parse(text()); if (Array.isArray(h)) saved = h.filter(e => e && typeof e === "object").map(e => notif.migrate(e)) } catch (e) {}
            const early = notif.history                   // any that arrived before the file was read
            const ids = early.map(e => e.id)
            notif.loaded = true
            notif.history = early.concat(saved.filter(e => ids.indexOf(e.id) < 0)).slice(0, notif.historyCap)
            if (early.length > 0) notif.save()
        }
        onLoadFailed: notif.loaded = true                 // no file yet: start one
    }
    // a path stays valid across restarts; image://… (pixel data held by this process) does not
    // the same message again: same app, title, body and urgency
    function sameMsg(a, b) {
        return !!a && !!b && (a.app || "") === (b.app || "") && (a.summary || "") === (b.summary || "")
            && (a.body || "") === (b.body || "") && !!a.critical === !!b.critical
    }
    function keptImage(s) { s = s || ""; return s.startsWith("/") || s.startsWith("file://") ? s : "" }
    function remember(n) {
        if (n.transient) return null
        const acts = []
        for (const a of (n.actions || [])) acts.push({ id: String(a.identifier), text: String(a.text || "") })
        const entry = {
            id: newId(),
            app: n.appName || "", summary: n.summary || "", body: n.body || "",
            critical: n.urgency === NotificationUrgency.Critical,
            seen: false,
            time: Qt.formatDateTime(new Date(), "ddd HH:mm"),
            at: Date.now(),
            urgency: Number(n.urgency),
            actions: acts,
            image: keptImage(n.image),
            appIcon: (n.appIcon || "").startsWith("image:") ? "" : (n.appIcon || ""),
            repeat: 1
        }
        const prev = history.find(e => sameMsg(e, entry))
        if (prev) { entry.id = prev.id; entry.repeat = (prev.repeat || 1) + 1 }
        history = [entry].concat(history.filter(e => e !== prev)).slice(0, historyCap)
        save()
        return entry
    }

    // history grouped by app, newest group first (by its newest entry); each entry carries
    // its index in history (for forget). {app, count, unseen, critical, rule, entries}
    readonly property var groups: {
        const out = [], by = {}
        history.forEach((e, i) => {
            let g = by[e.app]
            if (!g) { g = { app: e.app, count: 0, unseen: 0, critical: false, rule: ruleFor(e.app), entries: [] }; by[e.app] = g; out.push(g) }
            g.entries.push(Object.assign({ index: i }, e))
            g.count++
            if (e.seen === false) g.unseen++
            if (e.critical) g.critical = true
        })
        return out
    }
    // apps seen in history (and any with a rule), most notifications first: {app, count, rule}
    readonly property var apps: {
        const counts = {}
        for (const e of history) counts[e.app] = (counts[e.app] || 0) + 1
        for (const a in rules) if (!(a in counts)) counts[a] = 0
        return Object.keys(counts).map(a => ({ app: a, count: counts[a], rule: ruleFor(a) }))
                     .sort((x, y) => y.count - x.count || x.app.localeCompare(y.app))
    }

    // ---- Bluetooth devices whose blueman connect/disconnect notices are dropped (by device name) ----
    readonly property var quietBluetooth: ["BT_LED"]

    // ---- per-app rules: mute (dropped, except critical), list (no popup), normal ----
    property var rules: ({})
    property bool rulesLoaded: false
    function ruleFor(app) { const r = rules[app]; return r === "mute" || r === "list" ? r : "normal" }
    function setRule(app, rule) {
        if (!app || ["mute", "list", "normal"].indexOf(rule) < 0) return false
        const r = Object.assign({}, rules)
        if (rule === "normal") delete r[app]; else r[app] = rule
        rules = r
        if (rulesLoaded) rulesFile.setText(JSON.stringify(r, null, 2) + "\n")
        // its popups go: muted ones entirely, list-only ones to the list (they are already there)
        if (rule !== "normal") for (const it of live.filter(i => i.app === app && !i.critical)) dismissItem(it)
        return true
    }
    function rulesText() {
        const keys = Object.keys(rules).filter(a => ruleFor(a) !== "normal").sort()
        return keys.length === 0 ? "no rules (every app normal)" : keys.map(a => ruleFor(a) + "\t" + a).join("\n")
    }
    FileView {
        id: rulesFile
        path: notif.stateDir + "/notif-rules.json"
        blockWrites: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let saved = {}
            try { const r = JSON.parse(text()); if (r && typeof r === "object" && !Array.isArray(r)) saved = r } catch (e) {}
            const clean = {}
            for (const a in saved) if (saved[a] === "mute" || saved[a] === "list") clean[a] = saved[a]
            if (!notif.rulesLoaded) {                     // set before the file was read: those win
                const early = notif.rules
                notif.rulesLoaded = true
                notif.rules = Object.assign(clean, early)
                if (Object.keys(early).length > 0) rulesFile.setText(JSON.stringify(notif.rules, null, 2) + "\n")
            } else notif.rules = clean
        }
        onLoadFailed: notif.rulesLoaded = true
    }

    // ---- the popups currently on screen: {id, n, app, summary, body, critical, low, image, appIcon, at, snoozed} ----
    // n is the live Notification (null for one brought back from snooze); id matches its history entry
    property var live: []
    readonly property var shown: live
    function isLive(id) { return live.some(i => i.id === id && i.n !== null) }
    function liveItem(id) { return live.find(i => i.id === id) || null }
    function invokeAction(id, actionId) {
        const it = liveItem(id)
        if (!it || !it.n) return false
        const a = (it.n.actions || []).find(x => String(x.identifier) === actionId)
        if (!a) return false
        a.invoke()
        return true
    }
    function track(n, id, repeat) {
        const item = {
            id: id, n: n, app: n.appName || "", summary: n.summary || "", body: n.body || "",
            critical: n.urgency === NotificationUrgency.Critical, low: n.urgency === NotificationUrgency.Low,
            image: n.image || "", appIcon: n.appIcon || "", at: Date.now(), snoozed: false,
            repeat: repeat > 1 ? repeat : 1
        }
        // by object, not id: a repeat takes over its predecessor's id, and the old one's close must not drop it
        n.closed.connect(() => { if (notif.live.some(i => i.n === n)) notif.live = notif.live.filter(i => i.n !== n) })
        live = live.concat([item])
        return item
    }
    function drop(id) { if (live.some(i => i.id === id)) live = live.filter(i => i.id !== id) }
    function dismissItem(it) { if (it.n) it.n.dismiss(); drop(it.id) }
    function expireItem(it) { if (it.n) it.n.expire(); drop(it.id) }
    function dismissAll() { for (const it of live.slice()) dismissItem(it) }

    // popups grouped: several from one app, each within groupWindowMs of the one before,
    // make one card. Critical ones and snoozed ones returning never join an ordinary card.
    // Newest group first: {key, app, items (oldest first), critical, snoozed}
    readonly property int groupWindowMs: 120000
    readonly property var popupGroups: {
        const out = [], open = {}
        for (const it of live) {
            const k = it.app + "|" + (it.snoozed ? "z" : "")
            const g = open[k]
            if (g && !it.critical && it.at - g.last <= groupWindowMs) { g.items.push(it); g.last = it.at; continue }
            const ng = { key: it.id, app: it.app, items: [it], last: it.at, critical: it.critical, snoozed: it.snoozed }
            out.push(ng)
            if (!it.critical) open[k] = ng
        }
        return out.reverse()
    }
    function groupByKey(key) { return popupGroups.find(g => g.key === key) || null }
    function dismissGroup(key) { const g = groupByKey(key); if (g) for (const it of g.items) dismissItem(it) }
    function expireGroup(key) { const g = groupByKey(key); if (g) for (const it of g.items) expireItem(it) }

    // ---- the permanent record: every notification (muted and transient ones too, not osd levels)
    // goes to the user journal and ~/.local/state/shell-messages.jsonl through shell-log.
    // The 40-entry history above is only the bell's recent list.
    //   journalctl --user -t notification -t island
    function record(n, critical, how) {
        Sys.launch([Quickshell.env("HOME") + "/.local/bin/shell-log", "notification", String(n.summary || ""), String(n.body || ""),
                    "app=" + (n.appName || ""), "outcome=" + how,
                    "urgency=" + (critical ? "critical" : n.urgency === NotificationUrgency.Low ? "low" : "normal"),
                    "transient=" + (n.transient ? "yes" : "no")])
    }

    // ---- the one way in ----
    function ingest(n) {
        if (n.appName === "osd") {                        // level-style notes go to Osd.qml
            const v = n.hints ? n.hints["value"] : undefined
            notif.osdNote(n.summary + (n.body !== "" ? ": " + n.body : ""), v === undefined ? -1 : v)
            return "osd"
        }
        const critical = n.urgency === NotificationUrgency.Critical
        // per-device quiet: the GVM video lights (gvm, gvm-gui) connect and disconnect all the time,
        // and blueman announces every one; headphones and the rest still pop up (2026-11-17)
        if (n.appName === "blueman" && quietBluetooth.indexOf(String(n.summary || "")) >= 0 && !critical) {
            record(n, critical, "muted")
            return "muted"
        }
        const rule = ruleFor(n.appName)
        record(n, critical, rule === "mute" && !critical ? "muted" : (dnd || rule === "list") && !critical ? "listed" : "popup")
        if (rule === "mute" && !critical) return "muted"  // untracked: closed, never listed
        const entry = remember(n)
        if ((dnd || rule === "list") && !critical) return "listed"   // untracked: closed without a popup
        // a repeat of one still on screen replaces it: one card, counted
        const dup = live.find(i => sameMsg(i, { app: n.appName, summary: n.summary, body: n.body, critical: critical })) || null
        if (dup) { live = live.filter(i => i !== dup); if (dup.n) dup.n.expire() }
        n.tracked = true
        track(n, entry ? entry.id : dup ? dup.id : newId(), entry ? entry.repeat : dup ? (dup.repeat || 1) + 1 : 1)
        if (!dup && !(n.hints && n.hints["suppress-sound"])) Sys.sound(critical ? "dialog-warning" : "message")
        return dup ? "repeat" : "popup"
    }

    // ---- snooze: off the screen and out of the count, back as a popup at its time ----
    property var snoozed: []
    property bool snoozedLoaded: false
    readonly property real nextDue: snoozed.length === 0 ? 0 : Math.min.apply(null, snoozed.map(s => s.due))
    // "15m", "1h", "tomorrow" (08:00 the next day), or a time in ms since the epoch
    function dueFor(when) {
        const now = new Date()
        if (typeof when === "number") return when
        if (when === "15m") return now.getTime() + 15 * 60000
        if (when === "1h") return now.getTime() + 3600000
        if (when === "tomorrow") { const t = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 8, 0, 0); return t.getTime() }
        return 0
    }
    function snooze(id, when) {
        const due = dueFor(when)
        if (due <= 0) return false
        const e = history.find(x => x.id === id) || liveItem(id) || snoozed.find(x => x.id === id)     // the last: snoozed again
        if (!e) return false
        const rec = { id: id, app: e.app, summary: e.summary, body: e.body, critical: !!e.critical,
                      urgency: typeof e.urgency === "number" ? e.urgency : e.critical ? 2 : 1,
                      image: keptImage(e.image), appIcon: (e.appIcon || "").startsWith("image:") ? "" : (e.appIcon || ""),
                      time: e.time || "", due: due, repeat: e.repeat > 1 ? e.repeat : 1 }
        snoozed = snoozed.filter(s => s.id !== id).concat([rec])
        saveSnoozed()
        if (history.some(x => x.id === id)) { history = history.filter(x => x.id !== id); save() }
        const it = liveItem(id)
        if (it) dismissItem(it)
        armSnooze()
        return true
    }
    function snoozeGroup(key, when) { const g = groupByKey(key); if (g) for (const it of g.items.slice()) snooze(it.id, when) }
    function wakeSnoozed() { snoozed = snoozed.map(s => Object.assign({}, s, { due: 0 })); deliverDue() }
    function saveSnoozed() { if (snoozedLoaded) snoozedFile.setText(JSON.stringify(snoozed)) }
    function reloadSnoozed() { snoozedFile.reload() }      // tests: what a restart reads
    function deliverDue() {
        const now = Date.now()
        const due = snoozed.filter(s => s.due <= now).sort((a, b) => a.due - b.due)
        if (due.length > 0) {
            snoozed = snoozed.filter(s => s.due > now)
            saveSnoozed()
            let h = history
            const back = []
            for (const s of due) {
                const entry = migrate(s)
                entry.seen = false; entry.snoozed = true; entry.at = now
                entry.time = Qt.formatDateTime(new Date(), "ddd HH:mm")
                h = [entry].concat(h.filter(x => x.id !== s.id))
                if (!(dnd || ruleFor(s.app) === "list") || entry.critical)
                    back.push({ id: entry.id, n: null, app: entry.app, summary: entry.summary, body: entry.body,
                                critical: entry.critical, low: entry.urgency === 0, image: entry.image,
                                appIcon: entry.appIcon, at: now, snoozed: true, repeat: entry.repeat })
            }
            history = h.slice(0, historyCap)
            save()
            if (back.length > 0) {
                live = live.filter(i => !back.some(b => b.id === i.id)).concat(back)
                Sys.sound(back.some(b => b.critical) ? "dialog-warning" : "message")
            }
        }
        armSnooze()
    }
    // One timer, armed for the next due time only (and re-armed on each change). The minute
    // clock Sys already keeps catches a due time missed while the laptop slept (a Timer's
    // clock stops during suspend); it is only listened to while something is snoozed.
    function armSnooze() {
        snoozeTimer.stop()
        if (snoozed.length === 0) return
        snoozeTimer.interval = Math.max(50, Math.min(nextDue - Date.now(), 2000000000))
        snoozeTimer.start()
    }
    Timer { id: snoozeTimer; repeat: false; onTriggered: notif.deliverDue() }
    Connections {
        target: Sys
        enabled: notif.snoozed.length > 0
        function onNowHMChanged() { if (Date.now() >= notif.nextDue) notif.deliverDue() }
    }
    FileView {
        id: snoozedFile
        path: notif.stateDir + "/notif-snoozed.json"
        blockWrites: true
        printErrors: false
        onLoaded: {
            let saved = []
            try { const s = JSON.parse(text()); if (Array.isArray(s)) saved = s.filter(x => x && typeof x.id === "string" && typeof x.due === "number") } catch (e) {}
            const ids = notif.snoozed.map(s => s.id)
            notif.snoozed = notif.snoozed.concat(saved.filter(s => ids.indexOf(s.id) < 0))
            notif.snoozedLoaded = true
            notif.deliverDue()                            // due while the shell was down: delivered once (and removed from the file)
        }
        onLoadFailed: { notif.snoozedLoaded = true; if (notif.snoozed.length > 0) notif.saveSnoozed() }
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true
        onNotification: n => notif.ingest(n)
    }
    // after a reload (keepOnReload) the popups still open belong to this new instance
    Component.onCompleted: {
        for (const n of server.trackedNotifications.values) if (!live.some(i => i.n === n)) track(n, newId())
    }
}
