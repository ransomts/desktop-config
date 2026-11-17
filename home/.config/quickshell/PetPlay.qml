// The pet and its friend playing together: one shared scene at a time, across the two sprites
// (PetSprite.qml, who 0 and who 1) of the surface that is showing (a bar, or the desktop).
//   tag    one chases the other along the open stretch; caught, they swap; then both sit, pleased
//   ball   the ball game for two: the nearer one goes for the ball and knocks it on; a dog
//          fetches it and brings it to the other, who bats it away
//   perch  a bird flies over and rides on the other's back for a while, then hops off
//          (a dog, a cat, or any animal listed in `perches` or with `perch: true` in Pet.kinds)
//   food   when they are fed, the friend comes over and they eat side by side
// A scene starts only while both are idle and free (not busy, carried or chasing the pointer)
// and never in calm mode. By themselves they play now and then (the friend's idle timer asks
// `maybe`), less on battery, more or less with the liveliness habit. Scroll and "Play ball"
// start the shared ball game when the friend is there; feeding starts the food scene.
// Anything that comes between them ends it at once and frees both: a change of mood, the
// pointer, a pat, one picked up or leaving the surface (PetSprite.reset), the friend sent
// away, the animal or coat changed. `stop` is that one way out.
//   qs ipc call pet scene tag|ball|perch|food     says why not when it cannot
//   qs ipc call pet scene stop                    ends the one in progress
//   qs ipc call pet scene ""                      what is playing, and how the last one ended
// Movement is the sprites' own walkTo (their gaits); the only clock here is `step`, a 50 ms
// timer that runs while a scene does and nothing else.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "assets/pet-anchors.js" as Heads

Singleton {
    id: play

    // ---- lengths (settable, so the tests can be short) ----
    property int tagSwaps: 0                // times they swap roles in tag (0: three or four)
    property int ballKnocks: 0              // times the ball is sent on (0: five or six)
    property int rideMs: 7000               // how long the bird rides (half as long again on a turtle)
    property int eatMs: 1600                // eating side by side
    property int longest: 26000             // a scene still going after this is ended (under the sprites' 30 s watchdog)
    property real chance: 1                 // times the chance of a scene by themselves (0: never)
    // animals a bird may ride, besides any with `perch: true` in Pet.kinds; one that flies or hops never carries
    property var perches: ["dog", "cat", "turtle", "fox", "tortoise"]

    readonly property var names: ["tag", "ball", "perch", "food"]
    property string scene: ""               // the one in progress, "" for none
    property string last: ""                // how the last one ended
    property var a: null                    // the pet (who 0) in the scene
    property var b: null                    // its friend
    property int gen: 0                     // bumped at every start and end: callbacks of an older scene do nothing
    property double startedAt: 0
    property int n: 0

    // ---- the sprites: each joins when it is made (PetSprite.qml) ----
    property var sprites: []
    function join(s) { if (sprites.indexOf(s) < 0) sprites = sprites.concat([s]) }
    function forget(s) { left(s); sprites = sprites.filter(x => x !== s) }
    // a sprite dropped everything (PetSprite.reset: picked up, gone from this surface, the watchdog)
    function left(s) { if (scene !== "" && (s === a || s === b)) stop("left the scene", s) }

    function pair() {                       // the pet and its friend where they are shown, or null
        const p = sprites.find(s => s.who === 0 && s.active)
        const f = p ? sprites.find(s => s.who === 1 && s.active && s.parent === p.parent) : null
        return f ? [p, f] : null
    }
    function other(s) { return s === a ? b : a }
    function pulled(s) { return Pet.chase && !Pet.calm && s.ptr >= 0 }      // the pointer is on its surface: it would chase it
    function canCarry(s) {
        const k = Pet.kinds[s.animal]
        if (!k || k.flies || k.hops) return false
        return k.perch === true || perches.indexOf(s.animal) >= 0
    }
    function perchPair(pr) {                // [rider, carrier] or null
        if (!pr) return null
        if (pr[0].kind.flies && canCarry(pr[1])) return [pr[0], pr[1]]
        if (pr[1].kind.flies && canCarry(pr[0])) return [pr[1], pr[0]]
        return null
    }

    function whyNot(name) {
        if (names.indexOf(name) < 0) return "no scene called \"" + name + "\" (" + names.join(" ") + ")"
        if (Pet.friend === "") return "no friend"
        const pr = pair()
        if (!pr) return "they are not both shown"
        if (Pet.calm) return "calm mode"
        if (scene !== "") return "already playing " + scene
        for (const s of pr) {
            const who = s.who ? "the friend" : "the pet"
            if (s.mood !== "idle") return "not idle (" + s.mood + ")"
            if (s.carried) return who + " is being carried"
            if (s.busy) return who + " is busy"
            if (s.lured || pulled(s)) return who + " is after the pointer"
            if (!s.home) return "no room"
        }
        if (name === "perch" && !perchPair(pr)) return "a perch needs a bird and one to ride (" + perches.join(" ") + ")"
        return ""
    }

    // ---- ways in ----
    function start(name) {                  // `pet scene NAME`
        if (name === "stop") return stop("asked")
        if (name === "") return (scene !== "" ? "playing " + scene : "nothing playing") + (last !== "" ? "; last: " + last : "")
        const why = whyNot(name)
        if (why !== "") return "no: " + why
        begin(name, pair())
        return "ok " + name
    }
    function ballFor(s) {                   // the ball was asked for (scroll, menu, `pet play`): the shared game if it can be
        if (s.who !== 0 || whyNot("ball") !== "" || pair()[0] !== s) return false
        begin("ball", pair())
        return true
    }
    function feeding(s) {                   // both hear Pet.feed: true while s eats with the other one
        if (scene === "food" && (s === a || s === b)) return true
        if (scene !== "" && (s === a || s === b)) stop("food came")
        if (whyNot("food") !== "" || pair().indexOf(s) < 0) return false
        begin("food", pair())
        return true
    }
    function maybe(s) {                     // the friend's idle timer: now and then they play by themselves
        if (s.who !== 1 || scene !== "" || Pet.calm || Pet.weather === "rain") return false
        const p = 0.02 * chance * PetPrefs.roamScale * PetPrefs.ambientChance / 0.6 * (UPower.onBattery ? 0.25 : 1)
        if (Math.random() >= p) return false
        const pick = ["tag", "ball"]
        if (perchPair(pair())) pick.push("perch", "perch")
        return start(pick[Math.floor(Math.random() * pick.length)]).indexOf("ok") === 0
    }

    // ---- the one way out ----
    // Frees both (unless `spare`, a sprite or list of them, is already looking after itself),
    // takes away the ball and the ride, and drops every callback of the scene.
    function stop(why, spare) {
        if (scene === "") return "nothing playing"
        const was = scene, ps = [a, b]
        const spared = spare ? [].concat(spare) : []
        scene = ""; gen++; pending = null; rolling = false; riding = false; tagHold = false
        a = null; b = null
        last = was + " ended: " + why
        for (const s of ps) {
            if (!s) continue
            s.lift = 0; s.carrying = false; s.ballOut = false
            if (spared.indexOf(s) >= 0) continue
            s.afterWalk = null; s.stopMoving(); s.walking = false; s.hop = 0
            if (s.busy && !s.carried) { s.bubble = ""; s.endBusy() }       // endBusy: it goes back to what its mood wants
        }
        return "stopped " + was
    }
    function finish() {                     // a scene played out: both sit, pleased (a pat frees each in its own time)
        const ps = [a, b], was = scene
        scene = ""; gen++; pending = null; rolling = false; riding = false; tagHold = false
        a = null; b = null
        last = was + " done"
        for (const s of ps) {
            s.lift = 0; s.carrying = false; s.ballOut = false
            s.faceLeft = (s === ps[0] ? ps[1] : ps[0]).x < s.x
            s.patted("♥")
        }
    }
    Connections {
        target: Pet
        function onMoodChanged() { play.stop("the mood changed") }
        function onCalmChanged() { if (Pet.calm) play.stop("calm mode") }
        function onAnimalChanged() { play.stop("the animal changed") }
        function onCoatChanged() { play.stop("the coat changed") }
        function onFriendChanged() { play.stop("the friend changed") }
        function onFriendCoatChanged() { play.stop("the coat changed") }
        function onPat(who) { play.stop("a pat", [play.a, play.b].filter(s => s && (who < 0 || s.who === who))) }      // the one patted frees itself
        function onCheer() { play.stop("a cheer", [play.a, play.b]) }
    }

    // ---- the clock of a scene: checks, a pending pause, the ball rolling, the chase ----
    property var pending: null              // { at, f }: one pause at a time
    function wait(ms, f) { const g = gen; pending = { at: Date.now() + ms, f: function() { if (g === play.gen) f() } } }
    function walk(s, to, speed, then) {     // walkTo by its own gait; the callback only if the scene is still on
        const g = gen
        s.walkTo(to, speed, function() { if (g === play.gen && play.scene !== "") { if (then) then(); else s.frame = s.fStand } })
    }
    Timer {
        id: step
        interval: 50; repeat: true
        running: play.scene !== ""
        onTriggered: {
            play.n++
            if (play.rolling) play.rollStep()
            if (play.n % 4 === 0 && !play.check()) return
            if (play.pending && Date.now() >= play.pending.at) { const f = play.pending.f; play.pending = null; f() }
            if (play.scene === "tag" && play.n % 4 === 0) play.tagStep()
        }
    }
    function check() {                      // still both in it, idle, free of the pointer?
        if (Date.now() - startedAt > longest) { stop("too long"); return false }
        if (Pet.calm) { stop("calm mode"); return false }
        for (const s of [a, b]) {
            if (!s.active) { stop("left the surface", s); return false }
            if (s.carried) { stop("picked up", s); return false }
            if (!s.busy) { stop("something else came up", s); return false }      // a pat, a cheer: it went its own way
            if (s.mood !== "idle") { stop("the mood changed"); return false }
            if (pulled(s)) { stop("the pointer"); return false }
        }
        return true
    }
    function begin(name, pr) {
        gen++
        scene = name; a = pr[0]; b = pr[1]
        startedAt = Date.now(); n = 0; pending = null
        for (const s of pr) {
            s.stopMoving(); s.walking = false; s.afterWalk = null
            s.busy = true; s.grooming = false; s.bubble = ""; s.hop = 0; s.lift = 0
            s.frame = s.fStand
        }
        if (name === "tag") startTag()
        else if (name === "ball") startBall()
        else if (name === "perch") startPerch()
        else startFood()
    }

    // ---- tag ----
    property var chaser: null
    property var runner: null
    property int swapsLeft: 0
    property bool tagHold: false            // a moment's head start after a swap
    function startTag() {
        swapsLeft = tagSwaps > 0 ? tagSwaps : 3 + Math.floor(Math.random() * 2)
        chaser = Math.random() < 0.5 ? a : b
        runner = other(chaser)
        chaser.bubble = "!"
        flee()
    }
    function flee() {                       // the runner makes for the end of the stretch away from the chaser
        const r = runner, h = r.home
        let far = chaser.x < r.x ? h.to - r.size : h.from
        if (Math.abs(far - r.x) < 40 * r.k) far = far === h.from ? h.to - r.size : h.from      // cornered: it dodges past
        tagHold = true
        wait(700, function() { play.tagHold = false; play.chaser.bubble = "" })
        walk(r, far, 100, function() { r.frame = r.fSit; r.faceLeft = play.chaser.x < r.x })     // at the end: it waits to be caught
    }
    function tagStep() {
        if (tagHold) return
        const c = chaser, r = runner, reach = 26 * c.k
        if (Math.abs(c.x - r.x) < reach) { tagged(); return }
        const t = r.x + (r.x < c.x ? 1 : -1) * reach * 0.6
        if (!c.walking || Math.abs(c.walkTarget - t) > 12 * c.k) walk(c, c.clampX(t), 170, null)
    }
    function tagged() {
        const c = chaser, r = runner
        for (const s of [c, r]) { s.stopMoving(); s.walking = false; s.afterWalk = null }
        c.faceLeft = r.x < c.x; r.faceLeft = c.x < r.x
        c.frame = c.kind.pounces ? c.fPounce : c.fStand
        r.frame = r.fSit
        r.bubble = "!"
        tagHold = true
        chaser = r; runner = c
        if (--swapsLeft <= 0) { wait(500, finish); return }
        wait(500, function() { c.bubble = ""; r.frame = r.fStand; play.flee() })
    }

    // ---- the ball, for two ----
    property real ballPos: 0                // bar coordinates
    property var holder: null               // the sprite that draws it
    property int knocksLeft: 0
    property bool rolling: false
    property real rollFrom: 0
    property real rollTo: 0
    property double rollAt: 0
    property var rollThen: null
    function holdBall(s) {                  // one sprite draws the ball at a time
        holder = s
        for (const p of [a, b]) p.ballOut = p === s
        s.ballX = ballPos
    }
    function rollStep() {                   // stepped with the rest of the scene, eased out over half a second
        const t = Math.min(1, (Date.now() - rollAt) / 520)
        ballPos = rollFrom + (rollTo - rollFrom) * (1 - Math.pow(1 - t, 3))
        holder.ballX = ballPos
        if (t >= 1) { rolling = false; const f = rollThen; rollThen = null; if (f) f() }
    }
    function startBall() {
        knocksLeft = ballKnocks > 0 ? ballKnocks : 5 + Math.floor(Math.random() * 2)
        ballPos = a.x + a.size / 2
        holdBall(a)
        knock(a)
    }
    function knock(s) {                     // s sends it on: a paw, or (the dog) a nose
        const h = s.home
        let to = ballPos
        for (let i = 0; i < 8 && Math.abs(to - ballPos) < 90 * s.k; i++) to = h.from + 6 * s.k + Math.random() * (h.to - h.from - 12 * s.k)
        s.faceLeft = to < s.x + s.size / 2
        s.frame = s.kind.fetches ? s.fEat : s.fPounce
        knocksLeft--
        rollFrom = ballPos; rollTo = to; rollAt = Date.now(); rollThen = goFor; rolling = true
    }
    function goFor() {
        const g = gen
        if (knocksLeft <= 0) { wait(300, finish); return }
        const s = Math.abs(a.x + a.size / 2 - ballPos) <= Math.abs(b.x + b.size / 2 - ballPos) ? a : b     // the nearer one
        other(s).frame = other(s).fSit
        other(s).faceLeft = ballPos < other(s).x + other(s).size / 2
        holdBall(s)
        walk(s, s.clampX(ballPos - s.size / 2 + (ballPos > s.x + s.size / 2 ? -12 : 12) * s.k), 190, function() {
            s.faceLeft = play.ballPos < s.x + s.size / 2
            if (s.kind.fetches) fetchIt(s)
            else { s.frame = s.fPounce; wait(320, function() { play.knock(s) }) }
        })
    }
    function fetchIt(s) {                   // the dog takes it to the other one
        const o = other(s)
        s.carrying = true
        o.frame = o.fSit; o.faceLeft = s.x < o.x
        const side = s.x < o.x ? -1 : 1
        let spot = o.nearestSpot(o.x + side * 30 * o.k)
        if (Math.abs(spot - o.x) < 20 * o.k) spot = o.nearestSpot(o.x - side * 30 * o.k)
        walk(s, spot, 150, function() {
            s.faceLeft = o.x < s.x
            s.carrying = false
            s.frame = s.fSit
            ballPos = s.x + s.size / 2 + (s.faceLeft ? -1 : 1) * s.size * 0.4
            s.ballX = ballPos
            o.faceLeft = ballPos < o.x + o.size / 2
            wait(450, function() { play.holdBall(o); play.knock(o) })        // the other bats it away
        })
    }

    // ---- the perch: a bird rides on the other's back ----
    property var rider: null
    property var carrier: null
    property bool riding: false
    property double mountedAt: 0
    function back(c) {                      // [x, y] of the middle of its back in this frame, sprite pixels, facing right
        const bs = Heads.backs ? Heads.backs[c.animal] : undefined
        const v = bs ? bs[c.frame] : undefined
        if (v) return v
        const h = (Heads.heads[c.animal] || [])[c.frame] || [12, 2]      // not drawn yet: lower than the head and behind it
        return [h[0] - 6, Math.min(12, h[1] + 5)]
    }
    function seatX(c) {                     // where the rider's x goes for the carrier as it is now
        const bk = back(c)
        return c.x + ((c.faceLeft ? 16 - bk[0] : bk[0]) - (c.faceLeft ? 6 : 10)) * c.px * c.k      // the bird's feet are a little behind its middle
    }
    function ride() {                       // the rider moves with the carrier: called on each of its steps
        if (!riding) return
        const bk = back(carrier)
        rider.faceLeft = carrier.faceLeft
        rider.x = seatX(carrier)
        rider.lift = Math.max(0, (14 - bk[1]) * carrier.px * carrier.k)     // its feet (row 14) on the back, a row sunk in
    }
    Connections {
        target: play.riding ? play.carrier : null
        function onXChanged() { play.ride() }
        function onFrameChanged() { play.ride() }
        function onFaceLeftChanged() { play.ride() }
    }
    function startPerch() {
        const pp = perchPair([a, b])
        rider = pp[0]; carrier = pp[1]
        carrier.frame = carrier.fSit
        carrier.faceLeft = rider.x < carrier.x
        walk(rider, seatX(carrier), 200, function() {
            rider.frame = rider.fSit
            rider.hop = 0
            riding = true
            mountedAt = Date.now()
            ride()
            wait(600, amble)
        })
    }
    function amble() {                      // the carrier strolls about with the bird aboard
        const c = carrier
        if (Date.now() - mountedAt >= rideMs * (c.animal === "turtle" || c.animal === "tortoise" ? 1.5 : 1)) { getOff(); return }
        const h = c.home
        let to = c.x
        for (let i = 0; i < 8 && Math.abs(to - c.x) < 80 * c.k; i++) to = h.from + Math.random() * (h.to - h.from - c.size)
        walk(c, to, 50, function() { c.frame = c.fStand; play.wait(900, play.amble) })
    }
    function getOff() {
        const r = rider, c = carrier
        riding = false
        r.hop = -r.lift / r.k               // held where it was, then its own hop brings it down
        r.lift = 0
        const side = c.faceLeft ? 1 : -1    // off behind it
        let to = r.nearestSpot(c.x + side * 28 * c.k)
        if (Math.abs(to - c.x) < 16 * c.k) to = r.nearestSpot(c.x - side * 28 * c.k)
        walk(r, to, 60, function() { r.hop = 0; play.wait(300, play.finish) })
    }

    // ---- food: the friend comes over and they eat side by side ----
    function startFood() {
        const p = a, f = b
        p.frame = p.fSit
        p.bubble = p.kind.food
        f.bubble = f.kind.food
        const side = f.x < p.x ? -1 : 1
        let spot = p.nearestSpot(p.x + side * 34 * p.k)
        if (Math.abs(spot - p.x) < 28 * p.k) spot = p.nearestSpot(p.x - side * 34 * p.k)      // against the end of the stretch: the other side
        p.faceLeft = spot < p.x
        walk(f, spot, 110, eatTogether)
    }
    function eatTogether() {
        for (const s of [a, b]) {
            s.stopMoving(); s.walking = false
            s.frame = s.fEat; s.hop = 0
            s.bubble = s.kind.food
            s.faceLeft = other(s).x < s.x
        }
        wait(eatMs, finish)
    }
}
