// Pure rules for Quiet.qml (calendar-aware Do Not Disturb) and its tests: which events
// are "quiet" events, and the stretch of time they cover. No QML, no clock: the caller
// passes the time in minutes since midnight.
.pragma library

var DEFAULTS = { enabled: true, titles: ["lecture", "class", "exam", "office hours"], calendars: [], tags: ["quiet"], lead: 0 }

function mins(hm) { return parseInt(hm.slice(0, 2)) * 60 + parseInt(hm.slice(3, 5)) }
function key(e) { return (e.date || "") + "|" + (e.start || "") + "|" + (e.title || "") }
function strs(a, dflt) { return Array.isArray(a) ? a.filter(function (s) { return typeof s === "string" && s !== "" }) : dflt }

// Fill in anything missing or of the wrong kind from the defaults.
function normalize(r) {
    r = (r && typeof r === "object") ? r : {}
    var lead = parseInt(r.lead)
    return {
        enabled: r.enabled !== false,
        titles: strs(r.titles, DEFAULTS.titles),
        calendars: strs(r.calendars, DEFAULTS.calendars),
        tags: strs(r.tags, DEFAULTS.tags),
        lead: isNaN(lead) || lead < 0 ? 0 : Math.min(lead, 120)
    }
}

// A timed event with a start and an end whose title, calendar or tags match the rules.
function matches(e, rules) {
    if (!e || e.allday || !e.start || !e.end) return false
    var title = (e.title || "").toLowerCase()
    if (rules.titles.some(function (p) { return title.indexOf(p.toLowerCase()) >= 0 })) return true
    var cal = (e.calendar || "").toLowerCase()
    if (cal !== "" && rules.calendars.some(function (c) { return c.toLowerCase() === cal })) return true
    var tags = (e.tags || []).map(function (t) { return String(t).toLowerCase() })
    return rules.tags.some(function (t) { return tags.indexOf(t.toLowerCase()) >= 0 })
}

// The quiet events that are current at `now` (inside [start - lead, end)).
function current(events, now, rules, skipped) {
    return events.filter(function (e) {
        return matches(e, rules) && (skipped || []).indexOf(key(e)) < 0
            && mins(e.start) - rules.lead <= now && now < mins(e.end)
    })
}

// null, or { end: "HH:MM", title } for the stretch that `now` is in: the current quiet
// events plus any that start before the stretch ends (back to back, or overlapping).
function stretch(events, now, rules, skipped) {
    var cur = current(events, now, rules, skipped)
    if (cur.length === 0) return null
    var all = events.filter(function (e) { return matches(e, rules) && (skipped || []).indexOf(key(e)) < 0 })
    var end = 0, title = cur[0].title
    cur.forEach(function (e) { if (mins(e.end) > end) end = mins(e.end) })
    var grew = true
    while (grew) {
        grew = false
        all.forEach(function (e) { if (mins(e.start) <= end && mins(e.end) > end) { end = mins(e.end); grew = true } })
    }
    var p = function (n) { return (n < 10 ? "0" : "") + n }
    return { end: p(Math.floor(end / 60)) + ":" + p(end % 60), title: title }
}

// The next quiet event after `now` (for `quiet status`), or null.
function next(events, now, rules, skipped) {
    var later = events.filter(function (e) { return matches(e, rules) && (skipped || []).indexOf(key(e)) < 0 && mins(e.start) - rules.lead > now })
    later.sort(function (a, b) { return mins(a.start) - mins(b.start) })
    return later.length ? later[0] : null
}
