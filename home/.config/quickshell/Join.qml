// "Join the next meeting": the meeting with a web link that is under way or starts within
// ten minutes (join.js; ~/.local/bin/join-meeting is the same rule for the command line).
//   Join.event       the meeting, or null          Join.phase   "now" | "soon" | ""
//   Join.row()       a launcher row (label, sub, glyph, run), or null
//   Join.open(url)   open a meeting link (http/https only)
//   signal soon(var ev)   two minutes before a meeting that has a link (the shell puts it on the island)
//   qs ipc call join status | open
pragma Singleton
import QtQuick
import Quickshell
import "join.js" as J

Singleton {
    id: join
    signal soon(var ev)
    readonly property var picked: J.pick(Sys.today, J.mins(Sys.nowHM), 10)
    readonly property var event: picked ? picked.event : null
    readonly property string phase: picked ? picked.state : ""

    function open(url) {
        if (!J.isUrl(url)) return false
        Sys.launch(["xdg-open", url])
        return true
    }
    function row() {
        const e = event
        if (!e) return null
        const left = J.mins(e.start) - J.mins(Sys.nowHM)
        return {
            label: "Join: " + e.title,
            sub: phase === "now" ? e.start + (e.end ? "-" + e.end : "") + "  ·  under way" : "starts " + e.start + "  ·  in " + left + " min",
            glyph: Icons.calendar,
            run: function () { join.open(e.url) }
        }
    }
    function status() { return event ? (phase + ": " + event.start + " " + event.title) : "none" }

    // two minutes before a meeting with a link (a minute's slack, since Sys's clock ticks every 60 s)
    property bool settled: false
    property var told: []
    Timer { interval: 5000; running: true; onTriggered: join.settled = true }
    readonly property string minute: Sys.nowHM
    onMinuteChanged: {
        if (!settled) return
        const now = J.mins(minute)
        for (const e of Sys.today) {
            if (e.allday || !e.start || !J.isUrl(e.url)) continue
            const d = J.mins(e.start) - now
            const k = e.date + "|" + e.start + "|" + e.title
            if (d >= 1 && d <= 2 && told.indexOf(k) < 0) { told = told.concat([k]).slice(-20); soon(e); return }
        }
    }
}
