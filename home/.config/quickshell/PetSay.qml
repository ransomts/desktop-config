// What the bar pet (Pet.qml) can tell you when asked "What's up?": a short briefing of
// the next event and how long until it, unread mail, unread notifications, the battery,
// the weather, and anything that is wrong (offline, battery low, a disk or memory nearly
// full, running hot, 95°C and up). Drawn by PetBrief.qml on the "say" page of its menu.
// Ask it: "What's up?" at the top of its menu, middle-click on it, or
//   qs ipc call pet say          open its menu on the briefing (a key can be bound to this); prints it too
//   qs ipc call pet brief        the briefing as text, nothing opened
//   qs ipc call pet remark battery|event      make one of its remarks now (to see what it looks like)
// Mail and weather come from ~/.local/bin/dashboard-data (the same script as the dashboard),
// run only when asked and kept for a minute, so asking twice does not ask twice.
// While Do Not Disturb is on (a shared screen, a class) mail is counts only: no senders
// or subjects, the same rule as the dashboard.
//
// By itself it says two things, each once, and never while it is calm, asleep, hiding,
// or busy with a meeting, a focus timer or a notification (it waits until it is free):
//   battery    on battery and under 20%: once until the charger goes in again
//   event      the first timed event of the day is 30 minutes off or less: once a day
// A remark is a hop and a few characters beside its head; the hover tooltip has the sentence.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Singleton {
    id: say

    // ---- the data, fetched only when asked ----
    property var feeds: ({})                // dashboard-data feeds: weather, mail, tomorrow
    property var sysState: ({})             // dashboard-data sys: disks, memory, temperature
    property double feedsAt: 0
    property double sysAt: 0
    readonly property bool loading: feedsRun.running || sysRun.running
    function refresh() {
        const t = Date.now()
        if (t - feedsAt > 60000 && !feedsRun.running) feedsRun.running = true
        if (t - sysAt > 20000 && !sysRun.running) sysRun.running = true
    }
    Process {
        id: feedsRun
        command: Sys.clean.concat([Sys.bin + "dashboard-data", "feeds"])
        stdout: StdioCollector { onStreamFinished: { try { say.feeds = JSON.parse(text); say.feedsAt = Date.now() } catch (e) {} } }
    }
    Process {
        id: sysRun
        command: Sys.clean.concat([Sys.bin + "dashboard-data", "sys"])
        stdout: StdioCollector { onStreamFinished: { try { say.sysState = JSON.parse(text); say.sysAt = Date.now() } catch (e) {} } }
    }

    // open its menu on the briefing, on the focused screen (a second call closes it)
    function ask() {
        refresh()
        Pet.menuPage = "say"
        Sys.popupRequest("pet")
        return asText()
    }

    // ---- small helpers ----
    function minutes(m) {
        if (m < 60) return m + " min"
        const h = Math.floor(m / 60), r = m % 60
        return h + " h" + (r > 0 ? " " + r + " min" : "")
    }
    function seconds(s) { return s > 0 ? minutes(Math.max(1, Math.round(s / 60))) : "" }

    // ---- the battery (UPower; nothing to say on a machine without one) ----
    readonly property var bat: UPower.displayDevice
    readonly property bool hasBattery: !!bat && bat.isLaptopBattery
    readonly property int pct: hasBattery ? Math.round(bat.percentage * 100) : 100
    readonly property bool batLow: hasBattery && UPower.onBattery && pct < 20
    readonly property bool charging: hasBattery && bat.state === UPowerDeviceState.Charging

    // ---- what is wrong: things known live, and what the last `sys` said ----
    readonly property bool offline: Sys.netKind === "offline"
    readonly property var fullDisks: (sysState.disks || []).filter(d => d.used >= 0.9)
    readonly property bool memFull: (sysState.mem || 0) >= 0.9
    readonly property bool hot: (sysState.temp || 0) >= 95
    readonly property bool alarm: offline || batLow || fullDisks.length > 0 || memFull || hot

    // ---- the briefing: [{ glyph, text, sub: [lines], bad }], what is wrong first ----
    readonly property var items: {
        const out = []
        const now = Pet.mins(Sys.nowHM)

        // what is wrong
        if (offline) out.push({ glyph: Icons.offline, text: "Offline: no network", bad: true })
        for (const d of fullDisks)
            out.push({ glyph: Icons.disk, text: d.name + " disk " + Math.round(d.used * 100) + "% full, " + d.free_gb + " GB free", bad: true })
        if (memFull) out.push({ glyph: Icons.warn, text: "Memory " + Math.round(sysState.mem * 100) + "% used", bad: true })
        if (hot) out.push({ glyph: Icons.warn, text: "Running hot: " + sysState.temp + "°C", bad: true })

        // the calendar
        const cur = Sys.currentEvent, next = Sys.nextEvent
        const allDay = Sys.today.filter(e => e.allday).map(e => e.title)
        if (cur) out.push({ glyph: Icons.calendar, text: "Now: " + cur.title + ", until " + cur.end, sub: [] })
        if (next) {
            const later = Sys.today.filter(e => !e.allday && e.start > next.start).length
            out.push({ glyph: Icons.clock, text: next.title + " in " + minutes(Pet.mins(next.start) - now) + " (" + next.start + ")",
                       sub: (later > 0 ? ["then " + later + " more today"] : []).concat(allDay.length > 0 ? ["All day: " + allDay.join(", ")] : []) })
        } else {
            const tom = feeds.tomorrow ? (feeds.tomorrow.events || []).filter(e => !e.allday) : []
            out.push({ glyph: Icons.clock, text: cur ? "Nothing after that today" : "Nothing more today",
                       sub: (tom.length > 0 ? [feeds.tomorrow.name + " " + tom[0].start + ": " + tom[0].title] : [])
                            .concat(allDay.length > 0 ? ["All day: " + allDay.join(", ")] : []) })
        }

        // mail: counts always; the newest sender and subject per inbox only without Do Not Disturb
        const mail = feeds.mail
        if (!mail) out.push({ glyph: Icons.envelope, text: loading ? "Mail: looking..." : "Mail: not known", sub: [] })
        else if (mail.boxes.length === 0) out.push({ glyph: Icons.envelope, text: "Mail: no mail index", sub: [] })
        else {
            const total = mail.boxes.reduce((n, b) => n + b.unread, 0)
            const sub = []
            if (Notif.dnd) { if (total > 0) sub.push("Senders hidden while Do Not Disturb is on") }
            else for (const b of mail.boxes) {
                const m = mail.latest.find(l => l.box === b.name)
                if (m) sub.push(m.from + ": " + m.subject)
            }
            out.push({ glyph: Icons.envelope, text: total === 0 ? "No unread mail"
                                                    : "Unread mail: " + mail.boxes.map(b => b.name + " " + b.unread).join(", "), sub: sub })
        }

        // notifications
        out.push({ glyph: Notif.dnd ? Icons.bellOff : Icons.bell,
                   text: (Notif.unseen > 0 ? Notif.unseen + " unread notification" + (Notif.unseen === 1 ? "" : "s") : "No new notifications")
                         + (Notif.dnd ? ", Do Not Disturb on" : ""), sub: [] })

        // battery
        if (hasBattery) {
            const left = UPower.onBattery ? seconds(bat.timeToEmpty) : "", full = charging ? seconds(bat.timeToFull) : ""
            out.push({ glyph: charging ? Icons.batCharging : !UPower.onBattery ? Icons.batPlugged : Icons.battery[Math.min(4, Math.floor(pct / 20))],
                       text: "Battery " + pct + "%" + (charging ? ", charging" + (full !== "" ? ", full in " + full : "")
                                                       : UPower.onBattery ? (left !== "" ? ", " + left + " left" : ", on battery") : ", plugged in"),
                       bad: batLow, sub: [] })
        }

        // weather, in a few words
        const wx = feeds.weather
        if (wx && wx.ok) {
            const today = (wx.days || [])[0]
            out.push({ glyph: wx.glyph || Icons.sun, text: wx.temp + "° and " + (wx.words || "").toLowerCase() + (wx.stale ? " (last known)" : ""),
                       sub: today ? ["Today " + today.lo + "° to " + today.hi + "°" + (today.rain >= 30 ? ", " + today.rain + "% rain" : "")] : [] })
        } else if (feeds.weather) out.push({ glyph: Icons.sun, text: "No weather (offline?)", sub: [] })

        return out.filter(i => i.bad).concat(out.filter(i => !i.bad))
    }
    readonly property int worries: items.filter(i => i.bad).length
    readonly property string headline: loading && feedsAt === 0 ? "Asking around..."
                                        : worries === 0 ? "Nothing is wrong" : worries === 1 ? "One thing to look at" : worries + " things to look at"

    // the briefing as plain text (for `qs ipc call pet say` and `pet brief`)
    function asText() {
        return headline + "\n" + items.map(i => (i.bad ? "! " : "  ") + i.text + (i.sub || []).map(s => "\n    " + s).join("")).join("\n")
    }

    // ---- remarks it makes by itself ----
    signal remark(string glyph)                 // PetSprite: a hop and these few characters beside its head
    PersistentProperties {                      // what it has said, kept across a reload so it is not said twice
        id: said
        reloadableId: "petSay"
        property bool battery: false            // said since the charger was last plugged in
        property string event: ""               // the day it last spoke of the first event
        property string lastText: ""
        property double lastAt: 0
    }
    Connections { target: UPower; function onOnBatteryChanged() { if (!UPower.onBattery) said.battery = false } }

    property bool ready: false                  // give the bar a moment to lay out after a start or reload
    Timer { interval: 8000; running: true; onTriggered: say.ready = true }
    readonly property bool canSpeak: ready && Pet.enabled && !Pet.calm && !Pet.hiding
                                 && (Pet.mood === "idle" || Pet.mood === "dance" || Pet.mood === "tired")
    readonly property string dayKey: { Sys.nowHM; return Qt.formatDate(new Date(), "yyyy-MM-dd") }
    readonly property var firstEvent: {
        const timed = Sys.today.filter(e => !e.allday)
        return timed.length > 0 ? timed.reduce((a, b) => a.start <= b.start ? a : b) : null
    }
    readonly property int toFirst: firstEvent ? Pet.mins(firstEvent.start) - Pet.mins(Sys.nowHM) : -1
    // within five minutes the meeting mood takes over, so the remark is for 6 to 30 minutes out
    readonly property string due: !canSpeak ? "" : batLow && !said.battery ? "battery"
                                  : toFirst > 5 && toFirst <= 30 && said.event !== dayKey ? "event" : ""
    onDueChanged: if (due !== "") Qt.callLater(say.speak)
    function speak() { if (due !== "") sayNow(due) }
    function sayNow(what) {
        let glyph = "", sentence = ""
        if (what === "battery") {
            said.battery = true
            const left = seconds(bat ? bat.timeToEmpty : 0)
            glyph = Icons.battery[0] + pct + "%"
            sentence = "Battery is down to " + pct + "%" + (left !== "" ? ", about " + left + " left" : "")
        } else if (what === "event") {
            said.event = dayKey
            const e = firstEvent
            if (!e) return "no event today"
            const m = Math.max(0, toFirst)
            glyph = Icons.calendar + m + "m"
            sentence = "First event of the day in " + minutes(m) + ": " + e.title + " at " + e.start
        } else return "battery | event"
        said.lastText = sentence
        said.lastAt = Date.now()
        remark(glyph)
        return sentence
    }
    // a line for the pet's hover tooltip: how to ask, and the last remark if it was lately
    readonly property string tipLine: { Sys.nowHM; return "\nMiddle-click: what's up?" + (said.lastText !== "" && Date.now() - said.lastAt < 15 * 60000 ? "\n" + said.lastText : "") }
}
