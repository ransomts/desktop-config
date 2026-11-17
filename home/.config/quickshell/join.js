// Which meeting "Join" means: shared by Join.qml and mirrored by ~/.local/bin/join-meeting
// (the two are tested with the same cases). Times are minutes since midnight.
.pragma library

function mins(hm) { return parseInt(hm.slice(0, 2)) * 60 + parseInt(hm.slice(3, 5)) }
function isUrl(u) { return typeof u === "string" && /^https?:\/\/\S+$/.test(u) }

// A timed event with a web URL that is under way, or starts within `ahead` minutes.
// Under way wins (the one that began last); otherwise the soonest to start.
// An event without an end is taken to last an hour. Returns { event, state } or null.
function pick(events, now, ahead) {
    if (ahead === undefined) ahead = 10
    var under = [], soon = []
    events.forEach(function (e) {
        if (!e || e.allday || !e.start || !isUrl(e.url)) return
        var s = mins(e.start), end = e.end ? mins(e.end) : s + 60
        if (s <= now && now < end) under.push(e)
        else if (s > now && s - now <= ahead) soon.push(e)
    })
    under.sort(function (a, b) { return mins(b.start) - mins(a.start) })
    soon.sort(function (a, b) { return mins(a.start) - mins(b.start) })
    if (under.length) return { event: under[0], state: "now" }
    if (soon.length) return { event: soon[0], state: "soon" }
    return null
}
