pragma Singleton
// (pragma first: the singleton scanner gives up on a long comment header above it)
// Is every background job on this laptop still working? One answer for the bar's health pill
// and its popup (HealthList.qml). Runs ~/.local/bin/shell-health every two minutes and on
// refresh(); nothing else runs here.
//
//   Health.worst     "ok" | "stale" | "failed"   over the jobs not ignored
//   Health.jobs      every job shell-health reported, bad ones first (state ok|stale|failed|off)
//   Health.bad       the stale and failed ones that are not ignored
//   Health.newFailure(job)   a job went from ok to stale/failed since the last look. Not on
//                    every poll, and not for what was already bad when the shell started,
//                    unless it only just went bad (last worked under 10 minutes before).
//                    The island says it (hook in shell.qml); the pill shows what is bad either way.
//   Health.ignore(id) / Health.unignore(id)   "ignore until it recovers", kept in
//                    $XDG_STATE_HOME/health-ignore.json as { id: epoch-ms }; an entry goes
//                    when its job is seen working again.
//
//   Health.notices   the second kind of row, "worth knowing" (state "notice": pending updates, firmware,
//                    a restart, low disk; shell-health folds them in). They never touch worst, bad or the
//                    jobs list. Each: {id, name, why, count, cmd, actionable, say, group}.
//   Health.attention true while some notice is actionable (security updates, a restart, low disk, more
//                    than updatesNag packages, old lists): the pill then shows one quiet dot, nothing else.
//   Health.noticeSay(row)   low disk or a restart needed, once per boot per notice (remembered in
//                    $XDG_STATE_HOME/health-notices.json with the boot id). The island says it (hook in shell.qml).
//   Health.hiddenJobs   [{id, name}] the person stopped watching (the "hidden" list in
//                    ~/.config/shell/health.json, edited in Settings > Health, honoured by shell-health).
//   Health.openTerminal(row)   a notice's cmd in ghostty (the person asked by clicking; never run on its own)
//
//   qs ipc call health status | refresh | list
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: health

    property bool active: true                  // the poll runs only while this is true
    property var jobs: []
    property var ignored: ({})                  // id -> when it was ignored
    property bool loaded: false                 // a first answer has arrived
    property bool busy: false
    property var cmd: Sys.clean.concat([Sys.bin + "shell-health", "--json"])    // tests swap this
    property var clock: function() { return Date.now() }                         // tests swap this
    readonly property int recentMs: 10 * 60 * 1000
    property var prev: ({})                     // id -> state at the previous answer
    signal newFailure(var job)
    signal noticeSay(var row)
    property var notices: []
    property var hiddenJobs: []
    readonly property bool attention: notices.some(n => n.actionable)
    property string bootId: ""                  // tests set it
    property var said: ({ boot: "", ids: [] })
    property bool stateLoaded: false
    property bool bootLoaded: false

    readonly property var bad: jobs.filter(j => (j.state === "failed" || j.state === "stale") && !ignored[j.id])
    readonly property var ignoredBad: jobs.filter(j => (j.state === "failed" || j.state === "stale") && ignored[j.id])
    readonly property var good: jobs.filter(j => j.state === "ok")
    readonly property string worst: bad.some(j => j.state === "failed") ? "failed" : bad.length > 0 ? "stale" : "ok"

    function refresh(force) {
        if (!proc.running) { busy = true; proc.command = force === true ? cmd.concat(["--refresh"]) : cmd; proc.running = true }
    }

    // one answer from shell-health (JSON text); the Process calls this, and so can a test
    function ingest(text) {
        let o
        try { o = JSON.parse(text) } catch (e) { console.warn("Health: bad JSON from shell-health -", String(text).slice(0, 200)); return false }
        const rank = { failed: 0, stale: 1, ok: 2, off: 3 }
        const all = o.jobs || []
        const note = all.filter(j => j.state === "notice")
        const rows = all.filter(j => j.state !== "notice").map((j, i) => [j, i]).sort((a, b) => ((rank[a[0].state] ?? 4) - (rank[b[0].state] ?? 4)) || a[1] - b[1]).map(p => p[0])
        const now = clock()
        const first = !loaded
        const seen = {}
        let ign = ignored, changed = false
        for (const j of rows) {
            const isBad = j.state === "failed" || j.state === "stale"
            const was = prev[j.id]
            if (j.state === "ok" && ign[j.id]) { if (ign === ignored) ign = Object.assign({}, ign); delete ign[j.id]; changed = true }
            seen[j.id] = j.state
            if (!isBad || ign[j.id]) continue
            let fresh = false
            if (first) {
                const t = j.since ? Date.parse(j.since) : NaN
                fresh = !isNaN(t) && now - t < recentMs
            } else {
                fresh = was === "ok"
            }
            if (fresh) newFailure(j)
        }
        prev = seen
        jobs = rows
        notices = note
        hiddenJobs = Array.isArray(o.hidden) ? o.hidden : []
        loaded = true
        sayNotices()
        if (changed) { ignored = ign; saveSoon.restart() }
        return true
    }

    // low disk and "restart needed" go to the island once per boot each; everything else stays in the popup
    function sayNotices() {
        if (!stateLoaded || !bootLoaded || bootId === "") return
        let s = said
        if (s.boot !== bootId) s = { boot: bootId, ids: [] }
        let changed = s !== said
        for (const n of notices) {
            if (!n.say || s.ids.indexOf(n.id) >= 0) continue
            s = { boot: s.boot, ids: s.ids.concat([n.id]) }
            changed = true
            noticeSay(n)
        }
        if (changed) { said = s; saidSoon.restart() }
    }
    function ignore(id) { const m = Object.assign({}, ignored); m[id] = clock(); ignored = m; saveSoon.restart() }
    function unignore(id) { const m = Object.assign({}, ignored); delete m[id]; ignored = m; saveSoon.restart() }

    // ---- plain text for IPC and tooltips ----
    function ago(iso) {
        if (!iso) return "unknown"
        const t = Date.parse(iso)
        if (isNaN(t)) return "unknown"
        const s = Math.max(0, (clock() - t) / 1000)
        if (s < 90) return "just now"
        if (s < 5400) return Math.round(s / 60) + " min ago"
        if (s < 36 * 3600) return Math.round(s / 3600) + " h ago"
        return Math.round(s / 86400) + " days ago"
    }
    function summary() {
        if (!loaded) return "unknown (no answer yet)"
        if (bad.length === 0) return "ok" + (ignoredBad.length > 0 ? " (" + ignoredBad.length + " ignored)" : "")
        return worst + ": " + bad.map(j => j.name + " (" + j.why + ")").join("; ")
    }
    function table() {
        if (!loaded) return "no answer yet"
        return "worst: " + worst + "\n" + jobs.filter(j => j.state !== "off").map(j =>
            (ignored[j.id] && j.state !== "ok" ? "IGNORED" : j.state.toUpperCase()).padEnd(8) + j.name.padEnd(26) + j.why + "  [last worked " + ago(j.since) + "]").join("\n")
            + notices.map(n => "\n" + "NOTICE".padEnd(8) + n.name.padEnd(26) + n.why + (n.actionable ? "  [worth a look]" : "")).join("")
    }
    function tooltip() {
        return bad.map(j => "<b>" + j.name + "</b>: " + j.why).join("\n")
    }

    // ---- actions for the popup ----
    function quote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function openLog(job) { if (job.log) Sys.run("ghostty -e sh -c " + quote(job.log + "; read _")) }
    function openTerminal(row) { if (row.cmd) Sys.run("ghostty -e sh -c " + quote(row.cmd + "; read _")) }
    function runNow(job) { if (job.run) { Sys.run(job.run); recheck.restart() } }
    Timer { id: recheck; interval: 5000; onTriggered: health.refresh() }

    Timer {
        interval: 120000
        running: health.active
        repeat: true
        triggeredOnStart: true
        onTriggered: health.refresh()
    }
    Process {
        id: proc
        stdout: StdioCollector { onStreamFinished: { health.busy = false; health.ingest(text) } }
        onRunningChanged: if (!running) health.busy = false
    }

    // ---- ignore list ----
    readonly property string ignoreFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/health-ignore.json"
    FileView {
        id: file
        path: health.ignoreFile
        blockWrites: true
        printErrors: false
        onLoaded: { try { const o = JSON.parse(text()); if (o && typeof o === "object") health.ignored = o.ignored || {} } catch (e) {} }
    }
    // ---- once-per-boot memory for the island ----
    readonly property string saidFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/health-notices.json"
    FileView {
        id: saidView
        path: health.saidFile
        blockWrites: true
        printErrors: false
        onLoaded: {
            try { const o = JSON.parse(text()); if (o && typeof o.boot === "string" && Array.isArray(o.ids)) health.said = { boot: o.boot, ids: o.ids } } catch (e) {}
            health.stateLoaded = true; health.sayNotices()
        }
        onLoadFailed: { health.stateLoaded = true; health.sayNotices() }
    }
    Timer { id: saidSoon; interval: 300; onTriggered: saidView.setText(JSON.stringify(health.said)) }
    FileView {
        path: "/proc/sys/kernel/random/boot_id"
        printErrors: false
        onLoaded: { if (health.bootId === "") health.bootId = text().trim(); health.bootLoaded = true; health.sayNotices() }
        onLoadFailed: { health.bootLoaded = true }
    }
    Timer { id: saveSoon; interval: 300; onTriggered: file.setText(JSON.stringify({ ignored: health.ignored })) }
}
