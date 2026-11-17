// Focus profiles: the logic behind the Profiles singleton (kept apart so the test harness can
// build a second copy and call it a shell reload).
//
// ~/.config/shell/profiles.json (or $PROFILES_FILE; created with these three when missing, hand
// edits apply live, unknown keys are kept):
//   { "profiles": [
//       { "name": "Teaching",
//         "dnd": "on",            on | off | leave       Do Not Disturb (Notif)
//         "wallpaper": "still",   moving | still | leave the wallpaper's motion (WallState)
//         "island": "leave",      on | off | leave       the island's messages
//         "petCalm": "on",        on | off | leave       the pet: no wandering, chasing, moths
//         "keepAwake": "on",      on | off | leave       the screen does not dim or lock
//         "breaks": "leave",      on | off | leave       break reminders (~/.config/shell/breaks.json "enabled")
//         "apps": ["firefox", "org.gnome.Nautilus@3"],   desktop ids to open; "@N": on desktop N
//         "desk": 0 } ] }         the desktop to go to afterwards; 0 stays where you are
//   A missing key is "leave".
//
// apply(name): every switch the profile names is set, but only one whose value differs is
// remembered as changed (with what it was before). Applying another profile while one is on
// carries the earlier "before" values over and gives back what only the first one changed.
// end(): each remembered switch goes back to its "before" value, unless it no longer holds the
// value the profile gave it: then you changed it by hand, and it is left as you set it. Apps
// stay open. The desktop goes back only if you are still on the profile's desktop.
// The record lives in $XDG_STATE_HOME/profile-state.json, so a shell reload in the middle keeps
// it. Keep awake does not survive a reload by itself (Sys.keepAwake is not saved), so the
// profile sets it again after one.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: core

    property var island: null               // shell.qml's island (an id there, not a singleton): set by the shell
    property int appGapMs: 1500             // between apps meant for different desktops
    property var launch: function(id) { Sys.run("uwsm app -- '" + String(id).replace(/'/g, "") + (String(id).endsWith(".desktop") ? "" : ".desktop") + "'") }

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
    readonly property string profilesPath: Quickshell.env("PROFILES_FILE") || home + "/.config/shell/profiles.json"
    readonly property string breaksPath: Quickshell.env("BREAKS_FILE") || home + "/.config/shell/breaks.json"
    readonly property string statePath: stateHome + "/profile-state.json"

    readonly property var defaultProfiles: [
        { name: "Teaching", dnd: "on", wallpaper: "still", island: "leave", petCalm: "on", keepAwake: "on", breaks: "leave", apps: [], desk: 0 },
        { name: "Grading", dnd: "on", wallpaper: "leave", island: "off", petCalm: "leave", keepAwake: "leave", breaks: "on", apps: [], desk: 0 },
        { name: "Writing", dnd: "on", wallpaper: "still", island: "off", petCalm: "leave", keepAwake: "leave", breaks: "leave", apps: [], desk: 0 }
    ]
    // the switches a profile can hold, in the order they are shown; values are the profile's words
    readonly property var fields: [
        { key: "dnd", label: "Do Not Disturb", values: ["on", "off", "leave"] },
        { key: "wallpaper", label: "Wallpaper", values: ["moving", "still", "leave"] },
        { key: "island", label: "Island", values: ["on", "off", "leave"] },
        { key: "petCalm", label: "Pet calm", values: ["on", "off", "leave"] },
        { key: "keepAwake", label: "Keep awake", values: ["on", "off", "leave"] },
        { key: "breaks", label: "Break reminders", values: ["on", "off", "leave"] }
    ]

    JsonFile { id: file; path: core.profilesPath; create: true; defaults: ({ profiles: core.defaultProfiles }) }
    JsonFile { id: breaks; path: core.breaksPath; defaults: ({ enabled: false, workMinutes: 50, restMinutes: 5, snoozeMinutes: 10 }) }
    property alias profilesFile: file

    // ---- the profiles, cleaned up (a missing or odd value reads as "leave") ----
    function word(v, allowed) { v = String(v === true ? "on" : v === false ? "off" : v || "leave").toLowerCase(); return allowed.indexOf(v) >= 0 ? v : "leave" }
    function appsOf(a) {
        return (Array.isArray(a) ? a : []).map(x => typeof x === "string" ? x : x && x.id ? x.id + (x.desk ? "@" + x.desk : "") : "")
                                          .filter(s => s.trim() !== "").map(s => s.trim())
    }
    function clean(p) {
        const o = { name: String(p.name || "").trim(), apps: appsOf(p.apps), desk: Math.max(0, Math.min(10, parseInt(p.desk) || 0)) }
        for (const f of fields) o[f.key] = word(p[f.key], f.values)
        return o
    }
    readonly property var list: (Array.isArray(file.values.profiles) ? file.values.profiles : []).filter(p => p && p.name).map(clean)
    readonly property var names: list.map(p => p.name)
    function find(name) { const n = String(name || "").toLowerCase(); return list.find(p => p.name.toLowerCase() === n) || null }
    function describe(p) {
        const bits = []
        for (const f of fields) if (p[f.key] !== "leave") bits.push(f.label + " " + p[f.key])
        if (p.apps.length) bits.push(p.apps.length + (p.apps.length === 1 ? " app" : " apps"))
        if (p.desk > 0) bits.push("desktop " + p.desk)
        return bits.length ? bits.join(", ") : "changes nothing"
    }

    // ---- editing (the settings page): the file's other profiles and keys are kept ----
    function rawList() { return (Array.isArray(file.values.profiles) ? file.values.profiles : []).slice() }
    function edit(name, key, value) {
        const l = rawList(), i = l.findIndex(p => p && String(p.name).toLowerCase() === String(name).toLowerCase())
        if (i < 0) return false
        const p = Object.assign({}, l[i]); p[key] = value; l[i] = p
        return file.set("profiles", l)
    }
    function add(name) {
        name = String(name || "").trim()
        if (name === "" || find(name)) return false
        const p = { name: name, apps: [], desk: 0 }
        for (const f of fields) p[f.key] = "leave"
        return file.set("profiles", rawList().concat([p]))
    }
    function remove(name) {
        if (active.toLowerCase() === String(name).toLowerCase()) return false      // end it first
        return file.set("profiles", rawList().filter(p => !p || String(p.name).toLowerCase() !== String(name).toLowerCase()))
    }

    // ---- the switches themselves: read now, set ----
    function current(key) {
        if (key === "dnd") return Notif.dnd ? "on" : "off"
        if (key === "wallpaper") return WallState.cfg.hidden ? "plain" : WallState.cfg.running ? "moving" : "still"
        if (key === "island") return island ? (island.enabled ? "on" : "off") : ""
        if (key === "petCalm") return Pet.calm ? "on" : "off"
        if (key === "keepAwake") return Sys.keepAwake ? "on" : "off"
        if (key === "breaks") return breaks.values.enabled === true ? "on" : "off"
        return ""
    }
    function put(key, v) {
        const on = v === "on"
        if (key === "dnd") Notif.setDnd(on)
        else if (key === "wallpaper") { if (v === "plain") WallState.cfg.hidden = true; else { WallState.cfg.hidden = false; WallState.cfg.running = v === "moving" } }
        else if (key === "island") { if (island) island.setEnabled(on) }
        else if (key === "petCalm") Pet.setCalm(on)
        else if (key === "keepAwake") Sys.keepAwake = on
        else if (key === "breaks") breaks.set("enabled", on)
    }
    readonly property var volatileKeys: ["keepAwake"]      // not saved by their owner: set again after a reload

    // ---- what is on (saved) ----
    property string active: ""
    property double since: 0
    property var changed: ({})              // key -> { before, set }; "desk" too
    property bool stateLoaded: false

    function save() {
        if (stateLoaded) stateFile.setText(JSON.stringify({ active: active, since: since, changed: changed }, null, 1) + "\n")
    }
    FileView {
        id: stateFile
        path: core.statePath
        blockWrites: true
        printErrors: false
        onLoaded: {
            try {
                const o = JSON.parse(text())
                core.active = typeof o.active === "string" ? o.active : ""
                core.since = Number(o.since) || 0
                core.changed = core.active !== "" && o.changed && typeof o.changed === "object" ? o.changed : {}
            } catch (e) {}
            core.stateLoaded = true
            core.reassert()
        }
        onLoadFailed: core.stateLoaded = true
    }
    function reassert() {
        for (const k of volatileKeys) { const c = changed[k]; if (active !== "" && c && current(k) !== c.set) put(k, c.set) }
    }

    function apply(name) {
        const p = find(name)
        if (!p) return "no profile called " + name + " (" + names.join(", ") + ")"
        if (active !== "" && active.toLowerCase() === p.name.toLowerCase()) return p.name + " is already on"
        const old = changed, next = {}, done = []
        for (const f of fields) {
            const want = p[f.key], was = old[f.key]
            if (want === "leave") continue
            const now = current(f.key)
            if (now === "") continue                         // not available (no island yet)
            if (was && now === was.set) {                    // the earlier profile's change still holds
                if (want !== was.before) { next[f.key] = { before: was.before, set: want }; if (now !== want) put(f.key, want) }
                else put(f.key, want)                         // the new profile wants it as it was: give it back, nothing to remember
                done.push(f.key)
            } else if (now !== want) { next[f.key] = { before: now, set: want }; put(f.key, want); done.push(f.key) }
        }
        // what only the earlier profile changed goes back as end() would
        for (const k in old) if (k !== "desk" && !(k in next) && done.indexOf(k) < 0) restoreOne(k, old[k])
        const deskBefore = old.desk ? old.desk.before : Sys.desktop
        if (p.desk > 0 && Sys.desktop !== p.desk) next.desk = { before: deskBefore, set: p.desk }
        else if (old.desk && p.desk === 0) restoreOne("desk", old.desk)
        active = p.name
        since = Date.now()
        changed = next
        save()
        openApps(p)
        return "focus: " + p.name + " (" + describe(p) + ")"
    }
    function restoreOne(k, c) {
        if (k === "desk") { if (Sys.desktop === c.set && c.before > 0) Sys.goDesktop(c.before); return Sys.desktop === c.set }
        if (current(k) === c.set) { put(k, c.before); return true }
        return false
    }
    function end() {
        if (active === "") return "no focus profile is on"
        const back = [], kept = []
        for (const k in changed) (restoreOne(k, changed[k]) ? back : kept).push(k)
        const was = active
        active = ""; since = 0; changed = {}
        save()
        return "ended " + was + (back.length ? "; put back: " + back.join(" ") : "") + (kept.length ? "; left as you set them: " + kept.join(" ") : "")
    }
    function status() {
        if (active === "") return "off"
        const keys = Object.keys(changed)
        return active + " since " + Qt.formatTime(new Date(since), "HH:mm") + (keys.length ? "; changed: " + keys.map(k => k + " " + changed[k].before + "->" + changed[k].set).join(", ") : "; changed nothing")
    }
    function listText() { return list.map(p => (p.name === active ? "* " : "  ") + p.name + "\t" + describe(p)).join("\n") }

    // ---- apps: grouped by desktop, each group opened while that desktop is focused ----
    property var appQueue: []               // [{ desk, ids }]
    function openApps(p) {
        const groups = {}, plain = []
        for (const a of p.apps) {
            const m = /^(.*)@(\d+)$/.exec(a)
            if (m && parseInt(m[2]) > 0) (groups[m[2]] = groups[m[2]] || []).push(m[1]); else plain.push(a)
        }
        const q = Object.keys(groups).map(d => ({ desk: parseInt(d), ids: groups[d] }))
        if (p.desk > 0 || plain.length) q.push({ desk: p.desk, ids: plain })
        appQueue = q
        appTimer.stop()
        nextApps()
    }
    function nextApps() {
        if (appQueue.length === 0) return
        const g = appQueue[0]
        appQueue = appQueue.slice(1)
        if (g.desk > 0 && Sys.desktop !== g.desk) Sys.goDesktop(g.desk)
        for (const id of g.ids) launch(id)
        if (appQueue.length) appTimer.restart()
    }
    Timer { id: appTimer; interval: core.appGapMs; onTriggered: core.nextApps() }

    // ---- the launcher: rows for "focus" or a profile's name (LaunchView providers) ----
    function launcherRows(q, view) {
        q = String(q || "").trim().toLowerCase()
        if (q === "") return []
        const all = /^f(o(c(us?)?)?)?$/.test(q) || q.startsWith("focus")
        const rest = q.startsWith("focus") ? q.slice(5).trim() : ""
        const close = () => { if (view && view.close) view.close() }
        const rows = []
        for (const p of list) {
            const n = p.name.toLowerCase()
            if (!((all && (rest === "" || n.startsWith(rest))) || (q.length >= 2 && n.startsWith(q)))) continue
            const on = p.name === active
            rows.push({ label: (on ? "End focus: " : "Focus: ") + p.name, sub: on ? "put back what it changed" : describe(p),
                        icon: "", glyph: "󰽥",
                        run: on ? () => { close(); core.end() } : () => { close(); core.apply(p.name) } })
        }
        if (active !== "" && all && !rows.some(r => r.label.startsWith("End"))) rows.push({ label: "End focus: " + active, sub: "put back what it changed", icon: "", glyph: "󰽥", run: () => { close(); core.end() } })
        return rows
    }
}
