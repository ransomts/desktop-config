// The pet's long arc (Pet.qml is its mind from moment to moment): how long you have been
// together, what you have done with it over the weeks, and a short diary. Nothing here
// fades or is taken away: days apart are simply not counted, and it never asks for anything.
//   days        days the pet was on your bar (the shell running, the pet shown), counted once a day
//   counts      pats, meals, ball games, tricks done, focus timers sat through, welcomes back;
//               counted the way the bond counts them (Pet.bump), so a burst of clicks is one pat
//   milestones  each reached once: written in the diary and celebrated with a star (a pat
//               with another glyph) the next time it is awake and free, never while it sleeps,
//               focuses or reminds you of a meeting
//   unlocks     hats to wear: a flower after a week together, a bow after ten focus timers, a
//               crown after a month (Pet.hats adds them; nothing that was there is taken away)
//   anniversary on the day you met, a year on, it wears the party hat (hat on auto)
// Read it in its menu (Journal) and on the dashboard card.
//   qs ipc call pet journal          all of it, as text
//   qs ipc call pet celebrate ID     show a milestone's celebration again ("" the latest); records nothing
// Kept in ~/.local/state/pet-arc.json (Pet.qml's own file is left alone).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: arc

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/pet-arc.json"
        blockLoading: true
        blockWrites: true           // a change made while an unfinished write was in flight used to be undone when it landed
        printErrors: false
        onAdapterUpdated: saveSoon.restart()
        JsonAdapter {
            id: store
            property string adopted: ""         // the day you met, yyyy-MM-dd
            property string lastDay: ""         // the last day counted
            property int days: 0                // days together
            property int pats: 0
            property int meals: 0
            property int games: 0
            property int tricks: 0
            property int focus: 0               // focus timers sat through
            property int greets: 0              // welcomes back after unlocking the screen
            property string reached: ""         // milestone ids, space separated
            property string diary: "[]"         // JSON [{ d: "yyyy-MM-dd", t: "what happened" }], newest first
            property string seenTop: ""         // the newest diary line already looked at in the menu
        }
    }
    Timer { id: saveSoon; interval: 300; onTriggered: file.writeAdapter() }

    // Pet.qml uses this singleton in its bindings, so nothing here touches Pet until a few
    // seconds after start: reaching back into it while it is still being built is asking for trouble.
    property bool ready: false
    Timer { interval: 5000; running: true; onTriggered: { arc.ready = true; arc.start() } }

    // the date, moving on with the bar clock (Sys.nowHM ticks once a minute; no timer of our own)
    readonly property string today: { Sys.nowHM; return Qt.formatDate(new Date(), "yyyy-MM-dd") }
    onTodayChanged: if (ready) newDay()

    // ---- milestones: `of` names a count in the store, `n` how many; `hat` is earned with it ----
    readonly property var milestones: [
        { id: "week",     of: "days",   n: 7,    short: "7 days",     say: "A week together: a flower to wear", hat: "flower" },
        { id: "month",    of: "days",   n: 30,   short: "30 days",    say: "A month together: a crown to wear", hat: "crown" },
        { id: "days100",  of: "days",   n: 100,  short: "100 days",   say: "100 days together" },
        { id: "days365",  of: "days",   n: 365,  short: "365 days",   say: "365 days together" },
        { id: "pats100",  of: "pats",   n: 100,  short: "100 pats",   say: "100 pats" },
        { id: "pats1000", of: "pats",   n: 1000, short: "1000 pats",  say: "1000 pats" },
        { id: "meals50",  of: "meals",  n: 50,   short: "50 meals",   say: "50 meals" },
        { id: "games25",  of: "games",  n: 25,   short: "25 games",   say: "25 ball games" },
        { id: "tricks25", of: "tricks", n: 25,   short: "25 tricks",  say: "25 tricks done" },
        { id: "focus1",   of: "focus",  n: 1,    short: "a focus timer", say: "First focus timer sat through" },
        { id: "focus10",  of: "focus",  n: 10,   short: "10 focus timers", say: "10 focus timers: a bow to wear", hat: "bow" },
        { id: "focus50",  of: "focus",  n: 50,   short: "50 focus timers", say: "50 focus timers" }
    ]
    // the ones that are not counts (reached in note() and noticeWorld()), and how each is celebrated
    readonly property var glyphs: ({ hearts: "♥", rain: Icons.drop, snow: Icons.flake, friend: "♥" })
    function glyphFor(id) { return glyphs[id] || (id.indexOf("met") === 0 ? "♥" : "★") }

    function has(id) { return (" " + store.reached + " ").indexOf(" " + id + " ") >= 0 }
    readonly property var hats: milestones.filter(m => m.hat && arc.has(m.id)).map(m => m.hat)
    readonly property bool anniversary: store.adopted !== "" && today !== store.adopted && today.slice(5) === store.adopted.slice(5)

    // what Pet.bump counts, by the name it is given there
    readonly property var countOf: ({ pat: "pats", feed: "meals", play: "games", trick: "tricks", focus: "focus", greet: "greets" })
    // Pet.bump calls this each time something counts toward the bond (after its cooldowns)
    function note(what, bond) {
        const c = countOf[what]
        if (c) store[c] = store[c] + 1
        if (bond >= 100) reach("hearts", "Five hearts for the first time")
        check()
    }
    function check() { for (const m of milestones) if (store[m.of] >= m.n) reach(m.id, m.say) }
    function reach(id, say) {
        if (has(id)) return
        store.reached = (store.reached + " " + id).trim()
        write(say)
        pending = pending.concat([glyphFor(id)])
        tries = 0
        announce.restart()
    }

    function start() {
        if (store.adopted === "") { store.adopted = today; write("Came to live on your bar") }
        newDay()
        noticeWorld()
        if (pending.length) announce.restart()
    }
    function newDay() {
        if (!ready || !Pet.enabled || store.lastDay === today) return
        store.lastDay = today
        store.days = store.days + 1
        if (anniversary) {
            const years = parseInt(today.slice(0, 4)) - parseInt(store.adopted.slice(0, 4))
            reach("met" + today.slice(0, 4), years === 1 ? "A year since we met" : years + " years since we met")
        }
        check()
    }
    // firsts that come from the world around it (not the pretend weather of `wallpaper weather`)
    function noticeWorld() {
        if (!ready || !Pet.enabled) return
        if (WallState.wxDemo === "" && Pet.weather === "rain") reach("rain", "First rain together")
        if (WallState.wxDemo === "" && Pet.weather === "snow") reach("snow", "First snow together")
        if (Pet.friend !== "") reach("friend", "Made a friend: a " + Pet.friend)
    }
    Connections {
        target: arc.ready ? Pet : null
        function onEnabledChanged() { arc.newDay(); arc.noticeWorld(); if (arc.pending.length) { arc.tries = 0; announce.restart() } }
        function onWeatherChanged() { arc.noticeWorld() }
        function onFriendChanged() { arc.noticeWorld() }
        function onNameChanged() { arc.write("Named " + Pet.name) }
        function onMoodChanged() { if (arc.pending.length) { arc.tries = 0; announce.restart() } }
    }

    // ---- the celebration: the shown sprite (and its friend) do a pat with this glyph if they
    // are free (PetSprite sets `taken`); otherwise it tries again a little later, and after
    // that whenever the mood changes ----
    signal celebrate(string glyph)
    property bool taken: false
    property var pending: []
    property int tries: 0
    Timer {
        id: announce
        interval: 3200          // after whatever reached it (a pat, a meal, the cheer) has finished
        onTriggered: {
            if (!arc.ready || arc.pending.length === 0) return
            const m = Pet.mood
            if (!Pet.enabled || Pet.hiding || m === "asleep" || m === "focus" || m === "meeting" || m === "remind") return     // a mood change tries again
            arc.taken = false
            arc.celebrate(arc.pending[0])
            if (arc.taken) { arc.pending = arc.pending.slice(1); arc.tries = 0 }
            else if (++arc.tries >= 6) return                       // nobody free for twenty seconds: wait for a mood change
            if (arc.pending.length) announce.restart()              // the next one, or the same one again
        }
    }
    function cheer(glyph) { pending = pending.concat([glyph]); tries = 0; announce.restart() }     // a star for something else (PetSecrets.qml)
    function replay(id) {           // for scripts: celebrate again, record nothing
        if (id === "") { const r = store.reached.split(" "); id = r[r.length - 1] }
        if (id === "") return "nothing reached yet"
        taken = false
        celebrate(glyphFor(id))
        const m = milestones.find(x => x.id === id)
        return (m ? m.say : id) + (taken ? "" : " (no pet free to show it)")
    }

    // ---- the diary: the last forty notable things, newest first ----
    readonly property var entries: { try { return JSON.parse(store.diary) } catch (e) { return [] } }
    function write(t) {
        const e = entries
        if (e.length > 0 && e[0].t === t) return
        store.diary = JSON.stringify([{ d: today, t: t }].concat(e.slice(0, 39)))
    }
    readonly property bool unseen: entries.length > 0 && entries[0].d + " " + entries[0].t !== store.seenTop
    function markSeen() { if (entries.length > 0) store.seenTop = entries[0].d + " " + entries[0].t }

    // ---- for the menu and the dashboard ----
    readonly property int days: store.days
    readonly property var counts: ({ pats: store.pats, meals: store.meals, games: store.games, tricks: store.tricks, focus: store.focus, greets: store.greets })
    readonly property string daysText: store.days + (store.days === 1 ? " day" : " days")
    function pretty(d, brief) {     // brief: an older year gives month and year only (the diary's narrow column)
        if (!d) return ""
        const t = new Date(d + "T12:00:00")
        return Qt.formatDate(t, t.getFullYear() === new Date().getFullYear() ? "MMM d" : brief ? "MMM yyyy" : "MMM d, yyyy")
    }
    readonly property string since: pretty(store.adopted)
    // the count milestone it is furthest along toward
    readonly property var next: {
        let best = null, far = -1
        for (const m of milestones) {
            if (arc.has(m.id)) continue
            const f = store[m.of] / m.n
            if (f > far) { far = f; best = m }
        }
        return best
    }
    readonly property string nextLabel: next ? next.short : ""
    readonly property string nextDetail: next ? store[next.of] + " so far" : ""
    readonly property string summary: daysText + " together" + (entries.length > 0 ? ". " + pretty(entries[0].d) + ": " + entries[0].t : "")

    function report() {
        return "adopted " + store.adopted + ", " + daysText + " together (last counted " + store.lastDay + ")"
            + "\npats " + store.pats + "  meals " + store.meals + "  games " + store.games + "  tricks " + store.tricks
            + "  focus " + store.focus + "  greets " + store.greets
            + "\nreached: " + (store.reached || "nothing yet") + "\nhats earned: " + (hats.join(" ") || "none")
            + (next ? "\nnext: " + next.short + " (" + store[next.of] + ")" : "")
            + (anniversary ? "\ntoday is the anniversary" : "")
            + "\nwaiting to celebrate: " + pending.length + (unseen ? "\nnew in the diary" : "")
            + "\ndiary:" + entries.map(e => "\n  " + e.d + " " + e.t).join("")
    }
}
