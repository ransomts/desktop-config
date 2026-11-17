.pragma library
// Pure helpers behind Clocks.qml: reading what the user typed ("10m tea", "6:45am weekdays stand-up"),
// working out when an alarm next rings, formatting, and the launcher rows. No QML, no clock of its
// own: every function that needs "now" is given it (ms since the epoch), so the tests can use any time.
// Dates are the process's local time (Date's local getters).

var DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
var DAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
var MAX_TIMER = 7 * 24 * 3600          // seconds
var MISSED_MS = 10 * 60 * 1000         // an alarm still rings this long after its minute (reload, wake)
var NAMED = { monday: 0, mon: 0, tuesday: 1, tue: 1, tues: 1, wednesday: 2, wed: 2, thursday: 3, thu: 3, thur: 3, thurs: 3,
              friday: 4, fri: 4, saturday: 5, sat: 5, sunday: 6, sun: 6 }

function pad(n) { return (n < 10 ? "0" : "") + n }
function ymd(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }
function dayIndex(d) { return (d.getDay() + 6) % 7 }                 // Monday = 0

// ---------- durations ----------
var UNIT = { h: 3600, hr: 3600, hrs: 3600, hour: 3600, hours: 3600, m: 60, min: 60, mins: 60, minute: 60, minutes: 60,
             s: 1, sec: 1, secs: 1, second: 1, seconds: 1 }
// "10m" "1h30" "1h30m" "25" (minutes) "90s" "1.5h" "45 min" "1 hour 15 minutes" "1:30" (m:ss) "1:02:03" (h:m:s) -> seconds, or null
function parseDuration(text) {
    var s = String(text === undefined || text === null ? "" : text).trim().toLowerCase().replace(/,/g, ".")
    if (s === "") return null
    var m = s.match(/^(\d{1,3}):(\d{1,2})(?::(\d{1,2}))?$/)
    if (m) {
        var secs = m[3] === undefined ? parseInt(m[1], 10) * 60 + parseInt(m[2], 10) : parseInt(m[1], 10) * 3600 + parseInt(m[2], 10) * 60 + parseInt(m[3], 10)
        return secs > 0 && secs <= MAX_TIMER && (m[3] === undefined ? parseInt(m[2], 10) < 60 : parseInt(m[2], 10) < 60 && parseInt(m[3], 10) < 60) ? secs : null
    }
    var re = /(\d+(?:\.\d+)?)(\s*[a-z]+)?\s*/g
    var pos = 0, total = 0, prevUnit = "", groups = 0, g
    while (pos < s.length) {
        re.lastIndex = pos
        g = re.exec(s)
        if (!g || g.index !== pos) return null
        var num = parseFloat(g[1])
        var unitWord = g[2] === undefined ? "" : g[2]
        var spaced = /^\s/.test(unitWord)
        var u = unitWord.trim()
        var mult
        if (u === "") {
            if (groups === 0) mult = 60                                   // a bare number is minutes
            else if (prevUnit === "h" && !spaced && pos > 0 && s[pos - 1] !== " ") mult = 60      // 1h30
            else if (prevUnit === "m" && !spaced && pos > 0 && s[pos - 1] !== " ") mult = 1        // 1m30
            else return null
        } else {
            mult = UNIT[u]
            if (mult === undefined) return null
        }
        total += num * mult
        prevUnit = mult === 3600 ? "h" : mult === 60 ? "m" : "s"
        groups++
        pos = re.lastIndex
        if (groups > 4) return null
    }
    total = Math.round(total)
    return total > 0 && total <= MAX_TIMER ? total : null
}

// "10m tea" -> { seconds: 600, label: "tea" }; the duration is the longest run of words that reads as one
function parseTimer(spec) {
    var s = String(spec === undefined || spec === null ? "" : spec).trim().replace(/^for\s+/i, "")
    if (s === "") return { error: "say how long: 10m, 1h30, 25 (minutes), 90s" }
    var words = s.split(/\s+/)
    for (var k = Math.min(words.length, 4); k >= 1; k--) {
        var secs = parseDuration(words.slice(0, k).join(" "))
        if (secs !== null) return { seconds: secs, label: words.slice(k).join(" ").slice(0, 60) }
    }
    return { error: "not understood: \"" + s.slice(0, 30) + "\". Try 10m, 1h30, 25 (minutes) or 90s" }
}

// ---------- times of day ----------
// "7:30" "07:30" "7.30" "0730" "6:45am" "6pm" "7" "noon" "midnight" -> "HH:MM", or "" when not a time
function parseTime(text, suffix) {
    var s = String(text === undefined || text === null ? "" : text).trim().toLowerCase()
    if (suffix) s += String(suffix).toLowerCase()
    if (s === "noon") return "12:00"
    if (s === "midnight") return "00:00"
    var m = s.match(/^(\d{1,2})(?:[:.](\d{2}))?(am|pm|a|p)?$/)
    if (!m) { m = s.match(/^(\d{2})(\d{2})$/); if (m) m = [s, m[1], m[2], undefined] }
    if (!m) return ""
    var h = parseInt(m[1], 10), mi = m[2] === undefined ? 0 : parseInt(m[2], 10)
    var ap = m[3] === undefined ? "" : m[3][0]
    if (mi > 59) return ""
    if (ap !== "") { if (h < 1 || h > 12) return ""; h = h % 12 + (ap === "p" ? 12 : 0) }
    else if (h > 23) return ""
    return pad(h) + ":" + pad(mi)
}

function dateFromYmd(s) { var m = String(s).match(/^(\d{4})-(\d{2})-(\d{2})$/); return m ? new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10)) : null }
function validYmd(s) { var d = dateFromYmd(s); return !!d && ymd(d) === s }

// "7:30" "6:45am weekdays stand-up" "tomorrow 9" "mon wed fri 7" "7:30 2026-11-20 flight" "every day 6am"
// -> { time: "07:30", days: [] | ["mon"..], date: "" | "2026-11-15", label }, or { error }
function parseAlarm(spec, nowMs) {
    var s = String(spec === undefined || spec === null ? "" : spec).trim().replace(/^(at|for)\s+/i, "")
    var bad = { error: "say a time: 7:30, 6:45am weekdays, tomorrow 9" }
    if (s === "") return bad
    var words = s.split(/\s+/)
    var now = new Date(nowMs === undefined ? Date.now() : nowMs)
    var time = "", days = [], date = "", recurring = false, i = 0, err = ""
    function addDay(n) { if (days.indexOf(DAYS[n]) < 0) days.push(DAYS[n]) }
    for (; i < words.length; i++) {
        var w = words[i].toLowerCase().replace(/[,;]+$/, "")
        var next = i + 1 < words.length ? words[i + 1].toLowerCase() : ""
        var t
        if (w === "at" || w === "on" || w === "and") continue
        if (w === "every") { recurring = true; if (/^(day|weekday|weekdays|weekend|weekends)$/.test(next)) { /* handled next round */ } continue }
        if (time === "" && /^\d{1,2}([:.]\d{2})?$/.test(w) && /^(am|pm|a\.m\.|p\.m\.)$/.test(next) && (t = parseTime(w, next.replace(/\./g, ""))) !== "") { time = t; i++; continue }
        if (time === "" && (t = parseTime(w)) !== "") { time = t; continue }
        if (w === "daily" || w === "everyday") { recurring = true; for (var a = 0; a < 7; a++) addDay(a); continue }
        if (w === "day") { if (recurring) { for (var a2 = 0; a2 < 7; a2++) addDay(a2); continue } break }
        if (w === "weekday" || w === "weekdays") { recurring = true; for (var b = 0; b < 5; b++) addDay(b); continue }
        if (w === "weekend" || w === "weekends") { recurring = true; addDay(5); addDay(6); continue }
        var rg = w.match(/^([a-z]+)-([a-z]+)$/)
        if (rg && NAMED[rg[1]] !== undefined && NAMED[rg[2]] !== undefined) {
            recurring = true
            var from = NAMED[rg[1]], to = NAMED[rg[2]]
            for (var c = from, n = 0; n < 7; c = (c + 1) % 7, n++) { addDay(c); if (c === to) break }
            continue
        }
        var list = w.split(",")
        if (list.length > 1 && list.every(function (x) { return NAMED[x] !== undefined })) { recurring = true; list.forEach(function (x) { addDay(NAMED[x]) }); continue }
        if (NAMED[w] !== undefined) { addDay(NAMED[w]); continue }
        var plural = w.match(/^([a-z]+)s$/)
        if (plural && NAMED[plural[1]] !== undefined && w.length > 4) { recurring = true; addDay(NAMED[plural[1]]); continue }
        if (w === "today" || w === "tomorrow") {
            if (date !== "") { err = "one date only"; break }
            var d0 = new Date(now.getFullYear(), now.getMonth(), now.getDate() + (w === "tomorrow" ? 1 : 0))
            date = ymd(d0); continue
        }
        if (/^\d{4}-\d{2}-\d{2}$/.test(w)) {
            if (!validYmd(w)) { err = "not a date: " + w; break }
            if (date !== "") { err = "one date only"; break }
            date = w; continue
        }
        break
    }
    if (err !== "") return { error: err }
    if (time === "") return bad
    var label = words.slice(i).join(" ").slice(0, 60)
    if (date !== "" && days.length > 0) return { error: "a date or weekdays, not both" }
    if (days.length > 1 && !recurring) recurring = true            // "mon wed": every Monday and Wednesday
    if (days.length > 0 && recurring) {
        days.sort(function (x, y) { return DAYS.indexOf(x) - DAYS.indexOf(y) })
        return { time: time, days: days, date: "", label: label }
    }
    if (days.length === 1) {                                        // "monday 8": the next one, once
        var target = DAYS.indexOf(days[0])
        var hh = parseInt(time.slice(0, 2), 10), mm = parseInt(time.slice(3), 10)
        for (var k = 0; k < 8; k++) {
            var cand = new Date(now.getFullYear(), now.getMonth(), now.getDate() + k, hh, mm)
            if (dayIndex(cand) === target && cand.getTime() > now.getTime()) return { time: time, days: [], date: ymd(cand), label: label }
        }
    }
    if (date === "") {                                              // today if still ahead, else tomorrow
        var h2 = parseInt(time.slice(0, 2), 10), m2 = parseInt(time.slice(3), 10)
        var today = new Date(now.getFullYear(), now.getMonth(), now.getDate(), h2, m2)
        date = ymd(today.getTime() > now.getTime() ? today : new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1))
    }
    if (at(dateFromYmd(date), time) <= now.getTime()) return { error: "that time has already passed (" + date + " " + time + ")" }
    return { time: time, days: [], date: date, label: label }
}

// ---------- when an alarm rings ----------
function at(dateObj, time) { return new Date(dateObj.getFullYear(), dateObj.getMonth(), dateObj.getDate(), parseInt(time.slice(0, 2), 10), parseInt(time.slice(3, 5), 10)).getTime() }
// the first ring strictly after `afterMs`, or 0 (a one-off date already past)
function nextOccurrence(alarm, afterMs) {
    if (!alarm || parseTime(alarm.time) === "") return 0
    if (alarm.date) { var d = dateFromYmd(alarm.date); if (!d) return 0; var t = at(d, alarm.time); return t > afterMs ? t : 0 }
    var days = alarm.days || []
    if (days.length === 0) return 0
    var base = new Date(afterMs)
    for (var i = 0; i < 9; i++) {
        var day = new Date(base.getFullYear(), base.getMonth(), base.getDate() + i)
        if (days.indexOf(DAYS[dayIndex(day)]) < 0) continue
        var t2 = at(day, alarm.time)
        if (t2 > afterMs) return t2
    }
    return 0
}
// the latest ring at or before `nowMs` (today or yesterday), or 0
function lastOccurrence(alarm, nowMs) {
    if (!alarm || parseTime(alarm.time) === "") return 0
    if (alarm.date) { var d = dateFromYmd(alarm.date); if (!d) return 0; var t = at(d, alarm.time); return t <= nowMs ? t : 0 }
    var days = alarm.days || []
    var base = new Date(nowMs)
    for (var i = 0; i < 2; i++) {
        var day = new Date(base.getFullYear(), base.getMonth(), base.getDate() - i)
        if (days.indexOf(DAYS[dayIndex(day)]) < 0) continue
        var t2 = at(day, alarm.time)
        if (t2 <= nowMs) return t2
    }
    return 0
}

// ---------- words for things ----------
function daysText(days) {
    var d = (days || []).slice().sort(function (a, b) { return DAYS.indexOf(a) - DAYS.indexOf(b) })
    if (d.length === 0) return ""
    if (d.length === 7) return "daily"
    if (d.join() === "mon,tue,wed,thu,fri") return "weekdays"
    if (d.join() === "sat,sun") return "weekends"
    return d.map(function (x) { return DAY_NAMES[DAYS.indexOf(x)] }).join(" ")
}
function whenText(alarm, nowMs) {
    if (alarm.date) {
        var d = dateFromYmd(alarm.date), n = new Date(nowMs)
        var today = new Date(n.getFullYear(), n.getMonth(), n.getDate())
        var diff = Math.round((d.getTime() - today.getTime()) / 86400000)
        return diff === 0 ? "today" : diff === 1 ? "tomorrow" : diff > 1 && diff < 7 ? DAY_NAMES[dayIndex(d)] : alarm.date
    }
    return daysText(alarm.days)
}
function fmtLeft(sec) {                         // 252 -> "4:12", 3725 -> "1:02:05"
    sec = Math.max(0, Math.ceil(sec))
    var h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60
    return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s)
}
function fmtElapsed(ms) { return fmtLeft(Math.floor(Math.max(0, ms) / 1000)) }
function fmtDuration(sec) {                     // 600 -> "10 min", 5400 -> "1 h 30 min"
    sec = Math.round(sec)
    if (sec < 60) return sec + " s"
    var h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60
    if (h === 0) return m + " min" + (s ? " " + s + " s" : "")
    return h + " h" + (m ? " " + m + " min" : "")
}
function clockText(ms) { var d = new Date(ms); return pad(d.getHours()) + ":" + pad(d.getMinutes()) }
function minutesLeftText(ms) {                  // for the bar tooltip, which only refreshes once a minute
    var m = Math.ceil(ms / 60000)
    return m <= 0 ? "under a minute" : m === 1 ? "1 min" : m < 60 ? m + " min" : Math.floor(m / 60) + " h " + (m % 60 ? m % 60 + " min" : "")
}

// ---------- timers ----------
function timerLeftMs(t, nowMs) { return t.pausedLeft > 0 ? t.pausedLeft : Math.max(0, t.endsAt - nowMs) }
function timerRunning(t) { return !t.done && !(t.pausedLeft > 0) }
// "Timer: tea 4 min left" for the soonest running timer (minute resolution), "" when none
function tipText(timers, nowMs) {
    var run = (timers || []).filter(timerRunning).sort(function (a, b) { return a.endsAt - b.endsAt })
    if (run.length === 0) return ""
    var t = run[0]
    return "Timer: " + (t.label ? t.label + " " : "") + minutesLeftText(t.endsAt - nowMs) + " left" + (run.length > 1 ? " (+" + (run.length - 1) + " more)" : "")
}
// the single line in the collapsed panel
function summary(st, nowMs) {
    var parts = []
    var n = (st.timers || []).filter(function (t) { return !t.done }).length
    if (n > 0) parts.push(n + (n === 1 ? " timer" : " timers"))
    var best = 0
    for (var i = 0; i < (st.alarms || []).length; i++) {
        var a = st.alarms[i]
        if (!a.enabled) continue
        var o = nextOccurrence(a, Math.max(nowMs, a.lastFired || 0))
        if (o > 0 && (best === 0 || o < best)) best = o
    }
    if (best > 0) {
        var d = new Date(best), n0 = new Date(nowMs)
        var sameDay = ymd(d) === ymd(n0)
        var tomorrow = ymd(d) === ymd(new Date(n0.getFullYear(), n0.getMonth(), n0.getDate() + 1))
        parts.push("next alarm " + (sameDay ? "" : tomorrow ? "tomorrow " : DAY_NAMES[dayIndex(d)] + " ") + clockText(best))
    }
    if (st.stopwatch && st.stopwatch.running) parts.push("stopwatch running")
    return parts.length ? parts.join(" · ") : "Timers, alarms, clocks"
}

// ---------- the world clock ----------
// local time in a zone, from its UTC offset in seconds. -> { time: "14:05", dayShift: -1|0|1, diffHours }
function worldTime(nowMs, offsetSec, localOffsetSec) {
    var d = new Date(nowMs + offsetSec * 1000)                      // read with the UTC getters: the offset is already added
    var l = new Date(nowMs + localOffsetSec * 1000)
    var dayKey = function (x) { return Date.UTC(x.getUTCFullYear(), x.getUTCMonth(), x.getUTCDate()) }
    return { time: pad(d.getUTCHours()) + ":" + pad(d.getUTCMinutes()), dayShift: Math.round((dayKey(d) - dayKey(l)) / 86400000),
             diffHours: (offsetSec - localOffsetSec) / 3600, weekday: DAY_NAMES[(d.getUTCDay() + 6) % 7] }
}
function diffText(h) { return h === 0 ? "same time" : (h > 0 ? "+" : "−") + (Math.abs(h) % 1 === 0 ? Math.abs(h) : Math.abs(h).toFixed(2).replace(/0+$/, "")) + " h" }
// a zone name as the world clock accepts it: Area/City, UTC, GMT, Etc/GMT+5, no spaces or dots up the tree
function tzShape(s) { return /^[A-Za-z][A-Za-z0-9_+\-]*(\/[A-Za-z0-9_+\-]+){0,2}$/.test(String(s)) && String(s).indexOf("..") < 0 }

// ---------- launcher rows ----------
// st = { timers, alarms, stopwatch }; each row { label, sub, act } where act is null (nothing happens) or
// { type: "timer", seconds, label } | { type: "alarm", time, days, date, label } | { type: "pause"|"cancel"|"reset", id }
// | { type: "alarmtoggle"|"alarmdelete", id } | { type: "stopwatch", action: "start"|"stop"|"lap"|"reset" }
function launcherRows(query, st, nowMs) {
    var q = String(query === undefined || query === null ? "" : query).trim()
    var m = q.match(/^(timers?|alarms?|stopwatch|sw|clocks?)(?:\s+(.*))?$/i)
    if (!m) return []
    var word = m[1].toLowerCase(), arg = (m[2] || "").trim()
    var rows = []
    if (word === "timer") {
        if (arg === "") return [{ label: "Timer", sub: "type a time: 10m tea, 1h30, 25 (minutes), 90s", act: null }]
        var p = parseTimer(arg)
        if (p.error) return [{ label: "Timer: " + arg, sub: p.error, act: null }]
        return [{ label: "Timer " + fmtDuration(p.seconds) + (p.label ? ": " + p.label : ""), sub: "Enter starts it  ·  rings at " + clockText(nowMs + p.seconds * 1000),
                  act: { type: "timer", seconds: p.seconds, label: p.label } }]
    }
    if (word === "timers" || word === "clock" || word === "clocks") {
        var ts = (st.timers || [])
        if (ts.length === 0 && word === "timers") return [{ label: "No timers running", sub: "timer 10m tea starts one", act: null }]
        ts.forEach(function (t) {
            var name = t.label || fmtDuration(t.total / 1000)
            if (t.done) rows.push({ label: name + ": done", sub: "Enter removes it", act: { type: "cancel", id: t.id } })
            else {
                var left = fmtLeft(timerLeftMs(t, nowMs) / 1000)
                var paused = t.pausedLeft > 0
                rows.push({ label: (paused ? "Resume " : "Pause ") + name, sub: left + (paused ? " left, paused" : " left"), act: { type: "pause", id: t.id } })
                rows.push({ label: "Cancel " + name, sub: left + " left", act: { type: "cancel", id: t.id } })
            }
        })
        if (word !== "timers") rows = rows.concat(stopwatchRows(st))
        return rows
    }
    if (word === "alarm") {
        if (arg === "") return [{ label: "Alarm", sub: "type a time: 7:30, 6:45am weekdays stand-up, tomorrow 9", act: null }]
        var a = parseAlarm(arg, nowMs)
        if (a.error) return [{ label: "Alarm: " + arg, sub: a.error, act: null }]
        var tmp = { time: a.time, days: a.days, date: a.date }
        return [{ label: "Alarm " + a.time + (a.label ? ": " + a.label : ""), sub: "Enter sets it  ·  " + whenText(tmp, nowMs), act: { type: "alarm", time: a.time, days: a.days, date: a.date, label: a.label } }]
    }
    if (word === "alarms") {
        var al = st.alarms || []
        if (al.length === 0) return [{ label: "No alarms", sub: "alarm 7:30 sets one", act: null }]
        al.forEach(function (x) {
            rows.push({ label: x.time + (x.label ? " " + x.label : "") + (x.enabled ? "" : " (off)"), sub: whenText(x, nowMs) + "  ·  Enter turns it " + (x.enabled ? "off" : "on"), act: { type: "alarmtoggle", id: x.id } })
        })
        return rows
    }
    return stopwatchRows(st)
}
function stopwatchRows(st) {
    var sw = st.stopwatch || {}
    var el = fmtElapsed(sw.elapsed || 0)
    if (sw.running) return [{ label: "Stop stopwatch", sub: el + " so far", act: { type: "stopwatch", action: "stop" } },
                            { label: "Lap", sub: el, act: { type: "stopwatch", action: "lap" } },
                            { label: "Reset stopwatch", sub: "", act: { type: "stopwatch", action: "reset" } }]
    if ((sw.elapsed || 0) > 0) return [{ label: "Resume stopwatch", sub: el + " stopped", act: { type: "stopwatch", action: "start" } },
                                       { label: "Reset stopwatch", sub: el, act: { type: "stopwatch", action: "reset" } }]
    return [{ label: "Start stopwatch", sub: "", act: { type: "stopwatch", action: "start" } }]
}
