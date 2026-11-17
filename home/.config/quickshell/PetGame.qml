// Treat catch: a game with the pet on an empty desktop (Wallpaper.qml holds one per screen,
// over the pet; PetScore.qml starts it and keeps the best score). For 30 seconds treats fall
// from the top of the screen; the pet runs after the pointer and catches what reaches it.
//   its own food (the cat's fish, the dog's bone, the frog's and bird's bug)   3 points
//   the other foods                                                            1 point
//   a raindrop: to be dodged                     costs 2 (the frog loves rain: 1 point)
//
// While a game runs it owns the pet: the sprite is `busy` (so the mood, the idle life, the
// pointer chase and the watchdog leave it alone) and `inGame` (so a pat or a tongue flick in
// between does not free it). This file moves it, with no dead zone and faster than its idle
// chase, each animal in its own gait:
//   cat, dog   run straight at the pointer (the dog a little faster: its pace)
//   bird       hops near the pointer, flies (half again as fast) when it is further off
//   frog       hops after it, slower than the others, but snaps treats with its tongue from
//              well to either side, so it hardly needs to stand under them
//
// Cheap on purpose: nothing runs and nothing is drawn unless a game is on (or its result is
// showing). During a game one 50 ms timer steps the pet and at most `maxTreats` glyphs: the
// wallpaper is redrawn 20 times a second, as when the pet walks, never every frame.
//
// For tests: `autoSpawn: false` and drop(x, what) place treats by hand; `length` and `fallMs`
// shorten the game.
import QtQuick

Item {
    id: game
    property bool here: false               // the pet is down on this desktop (wall.petHere)
    property real pointerX: -1              // the pointer's x over this desktop, else -1
    property Item pet: null                 // the desk pet (who 0); found among the siblings when not given
    property int length: 30000              // ms
    property int fallMs: 3200               // ms for a treat to fall the whole height, at the start
    property bool autoSpawn: true
    property int maxTreats: 5

    property bool running: false
    property int score: 0
    property int secsLeft: 0
    property string resultText: ""
    visible: running || resultShown.running

    readonly property real k: pet ? pet.k : 2
    readonly property var glyphs: ({ fish: Icons.fish, bone: Icons.bone, bug: Icons.bug, drop: Icons.drop })
    readonly property var colors: ({ fish: "#f0a050", bone: "#ece4cc", bug: "#9cc96b", drop: "#5aa0e6" })

    onHereChanged: { register(); if (!here && running) finish("left") }
    Component.onCompleted: register()
    Component.onDestruction: if (PetScore.host === game) PetScore.host = null
    function register() {
        if (here) PetScore.host = game
        else if (PetScore.host === game) PetScore.host = null
    }

    function findPet() {
        if (pet) return pet
        const kids = parent ? parent.children : []
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i]
            if (c !== game && c.inGame !== undefined && c.spotTag !== undefined && c.who === 0) return c
        }
        return null
    }
    function petReady() { const s = findPet(); return here && s !== null && s.active }

    // ---- start and end ----
    property double startedAt: 0
    property double spawnAt: 0
    property double holdUntil: 0            // the pet is gulping or snapping: it does not move until then
    property double bubbleUntil: 0
    function begin() {
        const s = findPet()
        if (!s || running) return
        pet = s
        resultShown.stop()
        resultText = ""
        score = 0
        secsLeft = Math.ceil(length / 1000)
        hopAir = 0; hopRest = 0; holdUntil = 0; bubbleUntil = 0
        clearTreats()
        s.reset()                           // whatever it was doing (ball, moth, a walk) is dropped
        s.busy = true
        s.inGame = true
        s.frame = s.fSit
        startedAt = Date.now()
        spawnAt = startedAt + 500
        running = true
    }
    function finish(reason) {
        if (!running) return
        running = false
        clearTreats()
        hopAir = 0; hopRest = 0
        const s = pet, n = score
        const best = PetScore.record(n)
        resultText = best && n > 0 ? "New best: " + n + " ★" : n + (n === 1 ? " point" : " points") + "    best " + PetScore.best
        resultShown.restart()
        if (!s) return
        s.inGame = false
        s.walking = false; s.flying = false; s.hop = 0
        if (!s.active) { s.reset(); return }            // gone from this desktop: a clean slate
        Pet.setSpot(s.spotKey, s.x)
        if (n > 0) {
            Pet.bump("play", 3)
            s.patted(best ? "★" : "♥")                  // its own pat ends by itself and frees it
            if (best) PetSound.play("tada")             // stays quiet unless pet sounds are on
        } else { s.bubble = ""; s.endBusy() }
    }
    Timer { id: resultShown; interval: 5000 }

    // ---- the treats: a small fixed pool of glyphs ----
    function clearTreats() { for (let i = 0; i < pool.count; i++) { const t = pool.itemAt(i); if (t) t.on = false } }
    function live() { let n = 0; for (let i = 0; i < pool.count; i++) if (pool.itemAt(i).on) n++; return n }
    // a treat starts falling at x (this item's coordinates); what: fish bone bug drop, or "own"
    // for the pet's own food. Returns false when the pool is full or no game runs.
    function drop(x, what) {
        const s = pet
        if (!running || !s) return false
        if (what === "own" || glyphs[what] === undefined) what = s.kind.food === Icons.bone ? "bone" : s.kind.food === Icons.bug ? "bug" : "fish"
        for (let i = 0; i < pool.count; i++) {
            const t = pool.itemAt(i)
            if (t.on) continue
            const p = Math.min(1, (Date.now() - startedAt) / length)
            t.what = what
            t.pts = what === "drop" ? (s.kind.rain === "loves" ? 1 : -2) : glyphs[what] === s.kind.food ? 3 : 1
            t.cx = x
            t.cy = -10 * k
            t.vy = (height - s.floorGap + 10 * k) / (fallMs * (1 - 0.3 * p)) * tick.interval      // quicker as the game goes on
            t.on = true
            return true
        }
        return false
    }
    function spawn() {
        const s = pet
        const lo = s.home ? s.home.from + s.size / 2 : 40, hi = s.home ? s.home.to - s.size / 2 : width - 40
        const r = Math.random()
        const what = r < 0.3 ? "own" : r < 0.82 ? ["fish", "bone", "bug"][Math.floor(Math.random() * 3)] : "drop"
        drop(lo + Math.random() * (hi - lo), what)
    }

    Repeater {
        id: pool
        model: game.maxTreats
        Text {
            property bool on: false
            property string what: "fish"
            property int pts: 1
            property real cx: 0
            property real cy: 0
            property real vy: 0
            visible: on
            x: cx - width / 2; y: cy - height / 2
            text: game.glyphs[what]
            color: game.colors[what]
            style: Text.Outline; styleColor: Theme.solidBg
            font { family: Theme.font; pixelSize: 13 * game.k }
        }
    }

    // ---- the score while it runs, and the result for a few seconds after ----
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.min(64, parent.height / 4)
        width: hud.implicitWidth + 28; height: hud.implicitHeight + 12; radius: height / 2
        color: Theme.solidBg
        opacity: 0.92
        border.width: 1
        border.color: Theme.accentBg
        Text {
            id: hud
            anchors.centerIn: parent
            text: game.running ? "★ " + game.score + "    " + game.secsLeft + " s" : game.resultText
            color: Theme.fg
            font { family: Theme.font; pixelSize: 20; bold: true }
        }
    }

    // ---- one step: 20 a second, only while a game runs ----
    Timer {
        id: tick
        interval: 50; repeat: true
        running: game.running
        onTriggered: game.step()
    }
    function step() {
        const s = pet, now = Date.now()
        if (!here || !s || !s.active) { finish("left"); return }
        if (Pet.mood === "asleep" || Pet.focusing) { finish("stopped"); return }
        const gone = now - startedAt
        if (gone >= length) { finish("time"); return }
        const left = Math.ceil((length - gone) / 1000)
        if (left !== secsLeft) secsLeft = left
        if (!s.busy && !s.carried) s.busy = true          // something freed it in between: take it back
        drive(s, now)
        catchFall(s, now)
        if (autoSpawn && now >= spawnAt) {
            if (live() < maxTreats) spawn()
            spawnAt = now + (750 - 300 * gone / length) * (0.7 + Math.random() * 0.6)
        }
        if (bubbleUntil > 0 && now >= bubbleUntil && !s.tongueOut) { bubbleUntil = 0; s.bubble = "" }
    }

    // ---- moving the pet: straight for the pointer, no dead zone ----
    readonly property int runSpeed: 300     // px a second at k 1 and pace 1 (its idle chase is 170, its own walks 45)
    readonly property var hopArc: [0, -9, -6]   // the lift for the 3 steps of a hop, last step first
    property int hopAir: 0                  // steps of the current hop still to go
    property int hopRest: 0                 // steps it sits between hops
    property real hopDx: 0
    function halt(s) {
        if (s.walking || s.flying) { s.walking = false; s.flying = false; s.frame = s.fSit }
        s.hop = 0
        if (pointerX >= 0) s.faceLeft = pointerX < s.x + s.size / 2
    }
    function drive(s, now) {
        if (s.carried || now < holdUntil) return
        if (hopAir > 0) {                   // in the air
            s.x = s.clampX(s.x + hopDx)
            hopAir--
            s.hop = hopArc[hopAir]
            if (hopAir === 0) { s.frame = s.fSit; hopRest = s.kind.tongue ? 2 : 1 }
            return
        }
        if (hopRest > 0) { hopRest--; return }
        if (pointerX < 0) { halt(s); return }
        const t = s.clampX(pointerX - s.size / 2), d = t - s.x, ad = Math.abs(d)
        const fly = !!s.kind.flies && ad > 60 * s.k
        if (s.kind.hops && !fly) {
            if (ad < (s.kind.tongue ? 24 : 8) * s.k) { halt(s); return }      // the frog lets its tongue do the rest
            s.walking = true
            s.flying = false
            s.faceLeft = d < 0
            s.frame = s.fPounce
            hopDx = Math.sign(d) * Math.min(ad, (s.kind.tongue ? 40 : 30) * s.k) / 3
            hopAir = 3
            drive(s, now)                   // the first step of the hop now
            return
        }
        if (ad <= 1) { halt(s); return }
        s.faceLeft = d < 0
        if (!s.walking || s.flying !== fly) { s.walking = true; s.flying = fly; s.frame = fly ? s.fPounce : s.fWalk }
        const v = runSpeed * s.kind.pace * s.k * (fly ? 1.5 : 1) * tick.interval / 1000
        s.x = ad <= v ? t : s.x + Math.sign(d) * v
    }

    // ---- the treats fall a step; the pet has the ones that reach it ----
    function catchFall(s, now) {
        const floorY = height - s.floorGap
        const headY = floorY - s.size + s.hop * s.k
        const mid = s.x + s.size / 2
        const reach = s.kind.tongue ? 80 * s.k : s.size / 2 + 4 * s.k
        for (let i = 0; i < pool.count; i++) {
            const t = pool.itemAt(i)
            if (!t.on) continue
            t.cy += t.vy
            const dx = t.cx - mid
            if (t.cy >= headY + s.size * (s.kind.tongue ? 0.35 : 0.2) && Math.abs(dx) < reach && !s.carried && !s.tongueOut) {
                t.on = false
                score = Math.max(0, score + t.pts)
                hopAir = 0; hopRest = 0
                if (s.kind.tongue && Math.abs(dx) > s.size / 2) {         // the frog snaps it out of the air
                    s.flick(t.cx, false)
                    holdUntil = now + 450
                } else {                                                   // a gulp
                    s.walking = false; s.flying = false; s.hop = 0
                    s.frame = t.pts > 0 ? s.fEat : s.fSit
                    holdUntil = now + 150
                }
                s.bubble = t.pts > 0 ? "+" + t.pts : "!"
                bubbleUntil = now + 700
            } else if (t.cy >= floorY) t.on = false                       // missed: gone into the ground
        }
    }
}
