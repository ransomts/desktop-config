// How long until the next calendar event (and how long the one going on has left), under the date on the lock screen. LockView.qml
// loads this through a Loader by its file name (as LockPet.qml), so a mistake in here leaves
// an empty line, never a broken lock.
//
// The events are today's and tomorrow's timed ones from ~/.local/bin/agenda-day (the Org
// calendars, as the bar reads them). Only the time is shown, never the title: anyone can
// read a lock screen. Nothing is shown when there is no timed event before tomorrow night.
// No timer of its own: it follows LockView's minute clock (`now`), and reads the calendars
// again every quarter of an hour of it, so a long lock does not go stale.
// LOCK_AGENDA=/path/to/script stands in for agenda-day (to try it on a day with no events).
import QtQuick
import Quickshell
import Quickshell.Io

Text {
    id: next
    property date now: new Date()           // LockView binds its clock here
    property var events: []                 // [{ at, until: ms since the epoch (until 0 if it has no end), start, end: "HH:mm", tomorrow: bool }], in order
    readonly property var upcoming: { const t = now.getTime(); return events.find(e => e.at > t) || null }
    readonly property var current: { const t = now.getTime(); return events.find(e => e.at <= t && e.until > t) || null }
    readonly property int mins: upcoming ? Math.max(1, Math.ceil((upcoming.at - now.getTime()) / 60000)) : 0

    function span(m) { const h = Math.floor(m / 60), r = m % 60; return h === 0 ? r + " min" : r === 0 ? h + " h" : h + " h " + r + " min" }
    readonly property string nextText: upcoming ? "in " + span(mins) + "  (" + upcoming.start + (upcoming.tomorrow ? " tomorrow" : "") + ")" : ""
    text: current ? "Now until " + current.end + (upcoming ? "  \u00B7  next " + nextText : "")
        : upcoming ? "Next event " + nextText : ""
    color: "#b8b2ab"
    style: Text.Outline; styleColor: "#16161a"
    font { family: "FiraCode Nerd Font"; pixelSize: 14 }

    function day(offset) { const d = new Date(); return Qt.formatDate(new Date(d.getFullYear(), d.getMonth(), d.getDate() + offset), "yyyy-MM-dd") }
    function read() {
        if (agenda.running) return
        agenda.command = ["env", "-u", "LD_LIBRARY_PATH", "-u", "LIBGL_DRIVERS_PATH", "-u", "LIBVA_DRIVERS_PATH", "sh", "-c",
                          'a="${LOCK_AGENDA:-$HOME/.local/bin/agenda-day}"; "$a" "$1"; echo; "$a" "$2"', "sh", day(0), day(1)]
        agenda.running = true
    }
    Process {
        id: agenda
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [], today = next.day(0)
                for (const line of text.split("\n")) {
                    let list = []
                    try { list = JSON.parse(line) } catch (e) { continue }
                    if (!Array.isArray(list)) continue
                    for (const e of list) {
                        const d = /^(\d{4})-(\d\d)-(\d\d)$/.exec(e.date || ""), t = /^(\d\d):(\d\d)$/.exec(e.start || "")
                        if (e.allday || !d || !t) continue
                        const u = /^(\d\d):(\d\d)$/.exec(e.end || "")
                        const at = new Date(+d[1], d[2] - 1, +d[3], +t[1], +t[2]).getTime()
                        let until = u ? new Date(+d[1], d[2] - 1, +d[3], +u[1], +u[2]).getTime() : 0
                        if (u && until <= at) until += 86400000          // it runs past midnight
                        out.push({ at: at, until: until, start: e.start, end: e.end || "", tomorrow: e.date !== today })
                    }
                }
                out.sort((a, b) => a.at - b.at)
                next.events = out
            }
        }
    }
    Component.onCompleted: read()
    onNowChanged: if (now.getMinutes() % 15 === 0) read()
}
