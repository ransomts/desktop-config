// Calendar-aware Do Not Disturb: the logic behind the Quiet singleton (kept apart so the
// test harness can build a second copy and call it a shell reload).
//
// While a quiet event is current (rules in ~/.config/shell/quiet.json, below) Do Not
// Disturb is on; when the stretch ends the earlier state comes back. A stretch is one or
// more quiet events that touch or overlap. Rules:
//   - DND already on when the stretch starts: left alone, and left on at the end.
//   - DND turned off by hand during the stretch: stays off, for the rest of the stretch.
//   - Otherwise DND goes on at the start and off at the end.
// Where the state lives: $XDG_STATE_HOME/quiet-state.json holds "I switched it on", so a
// shell reload in the middle of a class neither loses it nor restores twice.
//
// ~/.config/shell/quiet.json (created with these defaults when missing, edits apply live):
//   { "enabled": true,                                  switch for the whole feature
//     "titles": ["lecture", "class", "exam", "office hours"],   case-insensitive substrings of the event title
//     "calendars": [],                                  any event from these calendar files (base name, e.g. "clemson")
//     "tags": ["quiet"],                                any event carrying one of these Org tags
//     "lead": 0 }                                       start this many minutes before the event
// Only timed events count; all-day events never silence anything.
//
// Hooks: signal announce(title, sub) fires at the start of a stretch (the shell shows it
// on the island).
import QtQuick
import Quickshell
import Quickshell.Io
import "quiet.js" as Rules

Item {
    id: core

    // ---- what it reads ----
    readonly property string hm: Sys.nowHM                  // "HH:MM"
    readonly property var events: Sys.today                 // agenda-day rows
    readonly property bool dataReady: Sys.todayLoaded !== false      // Sys.todayLoaded: set once agenda-day first answered (absent: only the settle delay applies)
    property int settleMs: 3000                             // Notif.dnd is read from its file a moment after a (re)load

    // ---- rules ----
    property var rules: Rules.normalize(null)
    readonly property bool enabled: rules.enabled
    readonly property string rulesPath: Quickshell.env("QUIET_RULES") || Quickshell.env("HOME") + "/.config/shell/quiet.json"

    // ---- the stretch in progress (saved) ----
    property bool active: false
    property bool weSet: false          // we switched DND on, so we switch it off
    property bool released: false       // the user switched it off during the stretch
    property string until: ""
    property string title: ""
    property var skipped: []
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quiet-state.json"

    property bool settled: false
    property bool stateLoaded: false
    property bool rulesLoaded: false
    readonly property bool ready: settled && stateLoaded && rulesLoaded && dataReady

    signal announce(string title, string sub)

    function mnow() { return Rules.mins(hm) }
    function evaluate() {
        if (!ready) return
        const s = enabled ? Rules.stretch(events, mnow(), rules, skipped) : null
        if (s && !active) begin(s)
        else if (s && active) { if (until !== s.end || title !== s.title) { until = s.end; title = s.title; save() } }
        else if (!s && active) finish()
    }
    function begin(s) {
        active = true
        released = false
        weSet = !Notif.dnd
        if (weSet) Notif.setDnd(true)
        until = s.end
        title = s.title
        save()
        announce("Quiet until " + s.end, s.title)
    }
    function finish() {
        if (weSet && !released && Notif.dnd) Notif.setDnd(false)
        active = false; weSet = false; released = false; until = ""; title = ""
        save()
    }
    // DND changed under us: if we had switched it on and it is now off, the user did it.
    function dndMoved() {
        if (!ready || !active) return
        if (!Notif.dnd && weSet) { weSet = false; released = true; save() }
    }
    // Something else (ending a presentation) switched DND off during a stretch: put it back.
    function resync() {
        if (!ready || !active || !enabled) return
        if (!Notif.dnd) { Notif.setDnd(true); weSet = true; released = false; save() }
    }
    function skip() {
        const cur = Rules.current(events, mnow(), rules, skipped)
        if (cur.length === 0) return "no quiet event is current"
        skipped = skipped.concat(cur.map(Rules.key)).slice(-60)
        evaluate()
        save()
        return "skipped: " + cur.map(e => e.title).join(", ")
    }
    function setEnabled(on) {
        rules = Object.assign({}, rules, { enabled: on })
        rulesFile.setText(JSON.stringify(rules, null, 2) + "\n")
        evaluate()
    }
    function status() {
        if (!enabled) return "off"
        if (active) return "quiet until " + until + " (" + title + ")" + (weSet ? "" : released ? ", Do Not Disturb was turned off by hand" : ", Do Not Disturb was already on")
        const n = Rules.next(events, mnow(), rules, skipped)
        return "on, nothing quiet now" + (n ? "; next " + n.start + " " + n.title : "")
    }

    onHmChanged: evaluate()
    onEventsChanged: evaluate()
    onReadyChanged: evaluate()
    onRulesChanged: evaluate()
    Connections { target: Notif; function onDndChanged() { core.dndMoved() } }
    Timer { interval: core.settleMs; running: true; onTriggered: core.settled = true }

    function save() {
        if (!stateLoaded) return
        stateFile.setText(JSON.stringify({ active: active, weSet: weSet, released: released, until: until, title: title, skipped: skipped }))
    }
    FileView {
        id: stateFile
        path: core.statePath
        printErrors: false
        onLoaded: {
            try {
                const o = JSON.parse(text())
                core.active = o.active === true
                core.weSet = core.active && o.weSet === true
                core.released = core.active && o.released === true
                core.until = core.active ? String(o.until || "") : ""
                core.title = core.active ? String(o.title || "") : ""
                core.skipped = Array.isArray(o.skipped) ? o.skipped.filter(s => typeof s === "string").slice(-60) : []
            } catch (e) {}
            core.stateLoaded = true
        }
        onLoadFailed: core.stateLoaded = true
    }

    FileView {
        id: rulesFile
        path: core.rulesPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let r = null
            try { r = JSON.parse(text()) } catch (e) { console.warn("Quiet: bad JSON in", core.rulesPath) }
            core.rules = Rules.normalize(r)
            core.rulesLoaded = true
        }
        onLoadFailed: {                          // no file yet: write the defaults for the user to edit
            core.rules = Rules.normalize(null)
            core.rulesLoaded = true
            Quickshell.execDetached(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && [ -e \"$1\" ] || printf '%s\\n' \"$2\" > \"$1\"",
                "sh", core.rulesPath, JSON.stringify(Rules.DEFAULTS, null, 2)])
        }
    }
}
