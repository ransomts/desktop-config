// The pet as drawn in one place (its mind is Pet.qml): on a bar, and, twice the size, on
// the wallpaper of a desktop with nothing open on it (Wallpaper.qml; `k`, `floorGap`).
// The bar pet as drawn on one bar: It walks only in the
// bar's empty stretches: `gaps` is a list of { from, to } x ranges the bar hands
// over (left of the clock, right of the music pill); `bellX`, `musicX` and
// `clockX` are where it goes when a notification comes in, music plays, or an
// event is about to start.
//
// What differs between the animals (gait, fidgets, what it does about the pointer, the
// ball, the moth, rain, tricks) comes from `kind`, the table in Pet.qml.
//
// How it is put together:
//   mood (Pet.mood)  where it should be and how it rests there: settle() walks it, rest() poses it
//   busy             a one-off in progress (pat, eat, pounce, ball game); the mood waits until it ends
//   lured            the pointer is on the bar and it is free to chase it
// Cheap on purpose: one small image; the frame timer runs only while something
// moves (2-6 ticks a second); it wanders mostly on mains power.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.UPower
import "assets/pet-anchors.js" as Heads

Item {
    id: sprite
    property var gaps: []                   // [{ from, to }], bar coordinates
    property real bellX: 0
    property real musicX: 0
    property real clockX: 0
    property bool shown: true               // this bar is on the focused screen
    property string screenName: ""
    property int who: 0                     // 0: the pet; 1: its friend (Pet.friend), a second animal on the same bar
    // what it is drawn as: itself, but for a costume or the first of April (PetSecrets.qml)
    readonly property var look: PetSecrets.look(who, Pet.animal, Pet.coat, Pet.friend, Pet.friendCoat)
    readonly property string animal: look.animal
    readonly property string coat: look.coat
    readonly property real otherX: who === 0 ? Pet.x1 : Pet.x0
    readonly property bool paired: Pet.friend !== ""
    readonly property string spotKey: screenName + spotTag + (who ? "#friend" : "")
    onXChanged: if (shown) { if (who) Pet.x1 = x; else Pet.x0 = x }
    // a newly shown sprite (another screen, the desktop) may not move for a while: say where it is
    // now, or the other one goes by the place it had on the last screen
    onShownChanged: if (shown) { if (who) Pet.x1 = x; else Pet.x0 = x }
    property real pointerX: -1              // the pointer's x while it is over this bar, else -1
    signal menuRequested()

    readonly property int px: 2             // screen pixels per sprite pixel (16 x 2 = 32, the bar is 34 tall)
    readonly property int box: 16 * px      // the animal's own square, before any enlarging
    property real k: 1                      // drawn k times larger (on the desktop: 2); distances and speeds follow
    property real floorGap: 0               // how far above the bottom of its parent it stands
    property real baseZ: -1
    property string spotTag: ""             // tells the desktop's remembered place from the bar's
    readonly property real size: box * k    // its width on screen: what the arithmetic about places uses
    scale: k
    transformOrigin: Item.BottomLeft
    readonly property var home: {           // the widest gap
        let best = null
        for (const g of gaps) if (g.to - g.from >= size + 8 && (!best || g.to - g.from > best.to - best.from)) best = g
        return best
    }
    readonly property bool active: Pet.enabled && !Pet.hiding && shown && home !== null && (who === 0 || Pet.friend !== "")
    // It fades rather than snaps when it moves to another screen's bar or between the bar
    // and the desktop: the old sprite fades out while the new one fades in. Still drawn while
    // fading out, so the mouse area is shut off as soon as it is no longer `active`.
    opacity: active ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.InOutQuad } }
    visible: active || opacity > 0
    width: box; height: box
    y: parent ? parent.height - box - floorGap + hop * k - lift : 0
    z: flying || atop ? Math.max(3, baseZ) : baseZ             // behind the pills when it walks past one; over them when it flies
    property bool flying: false
    property bool inGame: false             // treat catch (PetGame.qml) is moving it: busy until the game ends

    // frames in assets/pet.png
    readonly property int fStand: 0
    readonly property int fBlink: 1
    readonly property int fWalk: 2          // and 3
    readonly property int fSit: 4
    readonly property int fSleep: 5         // and 6
    readonly property int fLoaf: 7
    readonly property int fGroom: 8
    readonly property int fPounce: 9
    readonly property int fEat: 10
    readonly property int fTail: 11         // standing, tail the other way

    readonly property string mood: Pet.mood
    readonly property var kind: Pet.kinds[animal] || Pet.kind      // what this animal is like
    PetNature { id: nature; sprite: sprite }      // the turtle's shell, the fox's thieving (PetNature.qml)
    PetAntics { id: antics; sprite: sprite; z: -1 }     // its secrets (PetSecrets.qml)
    property var spans: ({})                // { bell: { from, to }, clock: { from, to } }: pills it can be put down on
    property real carryAt: -1               // where the pointer was when it was last carried (bar coordinates)
    property bool upside: false             // on its back
    property bool atop: false               // in front of a pill it was put down on, not behind it
    property bool weigh: false              // sitting on the clock pill, which sinks under it
    readonly property bool hovered: area.containsMouse
    signal rang()                           // it has rung the bell: the bar swings the pill
    signal pushed()                         // it has knocked the clock off: the bar drops it and brings it back
    function hopOnce() { patHop.restart() }
    property bool walking: false
    property bool busy: false
    property bool grooming: false
    property bool faceLeft: false
    property int frame: 0
    property int tick: 0
    property real hop: 0                    // lifted off the floor
    property real lift: 0                   // screen pixels up: riding on the other one's back (PetPlay.qml)
    property string bubble: ""              // glyph beside its head
    property var afterWalk: null            // what to do on arriving

    // ---- places ----
    function clampX(v) { return home ? Math.max(home.from, Math.min(home.to - size, v)) : v }
    function inGaps(v) {
        for (const g of gaps) if (v >= g.from - 1 && v <= g.to - size + 1) return true
        return false
    }
    function nearestSpot(left) {            // the allowed position closest to `left`
        let best = null, off = 1e9
        for (const g of gaps) {
            if (g.to - g.from < size + 8) continue
            const v = Math.max(g.from, Math.min(g.to - size, left))
            if (Math.abs(v - left) < off) { off = Math.abs(v - left); best = v }
        }
        return best === null ? clampX(left) : best
    }
    // It keeps its place: changing desktop or screen focus (the bar goes inactive for an
    // instant) must not send it back to where it started.
    property bool placed: false
    function place() {
        if (placed || !home) return
        const kept = Pet.spot(spotKey)             // where it was before the shell reloaded
        x = kept >= 0 ? nearestSpot(kept) : clampX(home.from + (home.to - home.from) * (who ? 0.4 : 0.6))
        placed = true
    }

    // ---- walking ----
    function stopMoving() { stroll.stop(); hopSeq.stop(); flying = false }
    property real walkTarget: 0
    function walkTo(target, speed, then) {
        if (!active || carried) return
        target = Math.round(target)
        afterWalk = then || null
        if (Math.abs(target - x) < 4) { stopMoving(); arrive(); return }     // stop: an earlier walk may still be running
        faceLeft = target < x
        grooming = false
        walking = true
        walkTarget = target
        speed = (speed || 45) * kind.pace * k
        if (kind.flies && Math.abs(target - x) > 60) {      // the bird: further than a few hops, it flies (over the pills)
            hopSeq.stop()
            flying = true
            frame = fPounce
            stroll.to = target
            stroll.duration = Math.abs(target - x) / (Math.max(speed, 140) * 1.5) * 1000
            stroll.go()
            return
        }
        if (kind.hops) {                    // the frog: a string of hops, longer and quicker when it hurries
            stroll.stop()
            flying = false
            hopLen = speed > 100 ? 30 : 22
            hopPause.duration = speed > 100 ? 190 : 420         // it sits between hops: without the pause it seems to fly
            if (!hopSeq.running) hopStep()
            return
        }
        hopSeq.stop()
        frame = fWalk                       // at once: a short walk can be over before the frame timer ticks
        stroll.to = target
        stroll.duration = Math.abs(target - x) / speed * 1000
        stroll.go()
    }
    property int hopLen: 24
    function hopStep() {
        if (!walking) return
        const d = walkTarget - x
        if (Math.abs(d) < 4) { arrive(); return }
        faceLeft = d < 0
        frame = fPounce
        hopMove.to = x + Math.sign(d) * Math.min(Math.abs(d), hopLen * k)
        hopSeq.restart()
    }
    SequentialAnimation {
        id: hopSeq
        ParallelAnimation {
            NumberAnimation { id: hopMove; target: sprite; property: "x"; duration: 260; easing.type: Easing.OutQuad }
            SequentialAnimation {
                NumberAnimation { target: sprite; property: "hop"; to: -9; duration: 110; easing.type: Easing.OutQuad }
                NumberAnimation { target: sprite; property: "hop"; to: 0; duration: 150; easing.type: Easing.InQuad }
            }
        }
        ScriptAction { script: sprite.frame = sprite.fSit }     // landed: squat again
        PauseAnimation { id: hopPause; duration: 420 }
        ScriptAction { script: Qt.callLater(sprite.hopStep) }
    }
    function arrive() {
        walking = false
        flying = false
        Pet.setSpot(spotKey, x)
        const then = afterWalk
        afterWalk = null
        if (then) then(); else rest()
    }
    // Walking is stepped 20 times a second, not animated every frame: each new position makes
    // the compositor redraw (and re-blur) the bar or the wallpaper, and sixty a second of that
    // took 20-30% of the GPU while it moved (measured 2026-11-11).
    Timer {
        id: stroll
        property real to: 0
        property real duration: 0           // ms for the whole walk, as walkTo() sets it
        property real perStep: 0
        interval: 50; repeat: true
        function go() { perStep = Math.abs(to - sprite.x) / Math.max(1, duration / interval); start() }
        onTriggered: {
            const d = to - sprite.x
            if (Math.abs(d) <= perStep + 0.01) { sprite.x = to; stop(); sprite.arrive() }
            else sprite.x += Math.sign(d) * perStep
        }
    }

    // ---- the mood: where to be, how to rest there ----
    function rest() {
        if (walking || busy) return
        grooming = false
        if (lured) {            // sits and watches the pointer (it turns its head only once the pointer is clearly past it)
            frame = fSit; bubble = ""; hop = 0
            if (Math.abs(ptr - (x + size / 2)) > 8 * k) faceLeft = ptr < x + size / 2
            return
        }
        if (mood === "asleep") { frame = fSleep; bubble = "z" }
        else if (mood === "meeting") { frame = fSit; bubble = Icons.clock; faceLeft = false }
        else if (mood === "remind") { frame = fSit; bubble = Icons.clock + "!"; faceLeft = false }     // PetRemind.qml
        else if (mood === "focus") { frame = fSit; bubble = Pet.focusLeft + "m" }
        else if (mood === "break") { frame = fStand; bubble = PetFocus.breakLeft + "m" }      // a break in a cycle (PetFocus.qml)
        else if (mood === "alert") { frame = fSit; bubble = Pet.alertGlyph; faceLeft = false }
        else if (mood === "tired") { frame = fLoaf; bubble = "" }
        else if (mood === "dance") { frame = fSit; bubble = "♪" }
        else { frame = fStand; bubble = "" }
        if (mood !== "dance") hop = 0
    }
    function settle() {
        if (!active || busy) return
        // asleep, the friend settles down beside the other one
        if (mood === "asleep" && who === 1 && Math.abs(x - (otherX - 30 * k)) > 12 * k) { walkTo(nearestSpot(otherX - 30 * k), 45); return }
        const to = mood === "alert" ? bellX : mood === "meeting" || mood === "remind" ? clockX : mood === "dance" ? musicX : -1
        if (to >= 0) walkTo(nearestSpot(to - who * 38 * k), mood === "dance" ? 45 : 110)       // it runs to the bell and the clock
        else if (!inGaps(x)) walkTo(nearestSpot(x), 110)       // stopped behind a pill: step out to the nearest open spot
        else { stopMoving(); walking = false; afterWalk = null; rest() }
    }
    function endBusy() { if (carried || inGame) return; busy = false; settle() }      // a timer left over from before it was picked up must not free it
    onMoodChanged: { settle(); if (mood === "alert" && kind.barks) bark() }
    function bark() { if (busy) return; bubble = kind.speak; barked.restart() }
    Timer { id: barked; interval: 1000; onTriggered: if (!sprite.busy) { if (sprite.walking) sprite.bubble = ""; else sprite.rest() } }
    // the bar lays its pills out a moment after it appears, and they change width as
    // they update: go again once the places it stands have stopped moving
    Timer { id: settleSoon; interval: 400; onTriggered: sprite.settle() }
    onGapsChanged: if (active && !busy && !walking && !inGaps(x)) settleSoon.restart()      // a pill grew over where it stands
    onBellXChanged: if (mood === "alert") settleSoon.restart()
    onMusicXChanged: if (mood === "dance") settleSoon.restart()
    onClockXChanged: if (mood === "meeting" || mood === "remind") settleSoon.restart()
    onActiveChanged: { if (active) { place(); settleSoon.restart() } else reset() }
    // Back to a clean slate: whatever it was in the middle of is dropped. Used when it leaves
    // this bar (another screen takes the focus, it is hidden) and by the watchdog below; without
    // it a ball game cut short left it "busy" for good, standing still and deaf to everything.
    function reset() {
        stopMoving(); leap.stop(); patHop.stop(); jumps.stop(); swipe.stop(); roll.stop(); bugFly.stop()
        for (const t of [wagStep, oneShotDone, trickDone, spinStep, eating, bat, tongueBack, barked, thought, lostIt]) t.stop()
        walking = false; afterWalk = null; busy = false; grooming = false
        carried = false; carrying = false; ballOut = false; bugOut = false; tongueOut = false; dropOut = false
        dropFall.stop(); dropGone.stop()
        nature.reset()
        antics.reset()
        hop = 0; bubble = ""
        lift = 0; PetPlay.left(sprite)          // a scene with the other one ends too, and frees it
        if (Sys.tipTarget === sprite) Sys.tipTarget = null
    }
    Timer {     // watchdog: nothing it does takes half a minute
        interval: 30000
        running: sprite.busy && !area.pressed && !sprite.inGame && !antics.dozing
        onTriggered: { if (sprite.carried) sprite.putDown(); else { sprite.reset(); sprite.settle() } }
    }
    onWalkingChanged: if (walking) { tipDelay.stop(); if (Sys.tipTarget === sprite) Sys.tipTarget = null }
    Component.onCompleted: { if (active) place(); settleSoon.restart() }
    QtObject { Component.onCompleted: PetPlay.join(sprite); Component.onDestruction: PetPlay.forget(sprite) }      // scenes for two (PetPlay.qml)

    // ---- frames: legs while walking, the dance bob, breathing asleep, washing ----
    Timer {
        interval: sprite.flying ? 110 : sprite.walking ? 160 : 500
        repeat: true
        running: sprite.active && (sprite.walking || sprite.grooming || (!sprite.busy && (sprite.mood === "dance" || sprite.mood === "asleep")))
        onTriggered: {
            sprite.tick++
            if (sprite.flying) sprite.frame = sprite.tick % 2 ? sprite.fPounce : sprite.fTail        // wings up, wings down
            else if (sprite.walking) { if (!sprite.kind.hops) sprite.frame = sprite.fWalk + sprite.tick % 2 }
            else if (sprite.grooming) sprite.frame = sprite.tick % 2 ? sprite.kind.idleA : sprite.kind.idleB      // washing, sniffing, croaking
            else if (sprite.mood === "dance" && !sprite.lured) sprite.hop = sprite.tick % 2 ? -3 : 0
            else if (sprite.mood === "asleep") {
                sprite.frame = sprite.fSleep + (sprite.tick >> 2) % 2          // a breath every two seconds
                sprite.bubble = sprite.tick % 28 >= 24 ? sprite.kind.food : "z"   // and now and then a dream of dinner
            }
        }
    }

    // ---- idle life: every few seconds it does one small thing ----
    Timer {
        interval: PetPrefs.idleMs
        repeat: true
        running: sprite.active && (sprite.mood === "idle" || sprite.mood === "break") && !sprite.walking && !sprite.lured && !sprite.busy
        onTriggered: {
            const r = Math.random(), k = sprite.kind, wx = Pet.weather
            sprite.grooming = false
            if (sprite.paired && Math.abs(sprite.x - sprite.otherX) < 30 * sprite.k) {             // on top of each other: they step apart
                const right = sprite.x > sprite.otherX || (sprite.x === sprite.otherX && sprite.who === 1)
                sprite.walkTo(sprite.nearestSpot(sprite.x + (right ? 44 : -44) * sprite.k))
                return
            }
            if (PetPlay.maybe(sprite)) return                                        // now and then the two of them play (PetPlay.qml)
            if (antics.maybePush()) return                                           // or the cat has an idea (PetAntics.qml)
            if (sprite.who === 1 && !Pet.calm && Math.random() < 0.07) {                // the friend goes over to say hello
                sprite.walkTo(sprite.nearestSpot(sprite.otherX + (sprite.x < sprite.otherX ? -34 : 34) * sprite.k), 60, function() { Pet.nuzzle() })
                return
            }
            const lovesRain = wx === "rain" && k.rain === "loves"
            if (k.sings && Pet.hour >= 5 && Pet.hour < 10 && Math.random() < 0.3) sprite.think("♪")      // morning song
            const huddle = (wx === "rain" && k.rain === "shelter") || wx === "snow" || wx === "cold" || wx === "hot" || (Pet.sleepy && !k.nocturnal && Math.random() < 0.5)
            if (lovesRain && Math.random() < 0.25) sprite.think(k.speak)
            else if (wx !== "" && wx !== "clear" && wx !== "fog" && Math.random() < 0.1)
                sprite.think(wx === "hot" ? Icons.sun : wx === "rain" ? Icons.drop : Icons.flake)
            if (huddle && r < 0.6) { sprite.frame = sprite.fLoaf; return }               // curled up against the cold, sprawled in the heat
            // wander: by its nature; rarely on battery; the cat not at all in the rain, the frog all the more
            const roam = Pet.calm ? 0 : lovesRain ? 0.45 : wx === "rain" && k.rain === "umbrella" ? 0 : k.roam * PetPrefs.roamScale * (UPower.onBattery ? 0.25 : 1)
            if (r < roam && sprite.home) {
                sprite.walkTo(sprite.home.from + Math.random() * (sprite.home.to - sprite.home.from - sprite.size))
                return
            }
            const q = Math.random()
            if (q < k.sits) sprite.frame = sprite.fSit
            else if (q < k.sits + k.lazes) sprite.frame = sprite.fLoaf
            else if (q < k.sits + k.lazes + k.fidgets) { sprite.frame = k.idleA; sprite.grooming = true }
            else if (q < 0.8) {
                sprite.frame = sprite.fStand
                if (!k.hops && !k.flies && Math.random() < 0.6) sprite.wag(k.barks ? 6 : 4, k.barks ? 130 : 230)     // a wag, or a slow flick of the tail
            }
            else if (sprite.frame === sprite.fStand || k.hops) { sprite.frame = sprite.fBlink; unblink.restart() }
            if (Pet.hungry && Math.random() < 0.08) sprite.think(k.food)
            else if (PetSecrets.costume === "shiny" && Math.random() < 0.15) sprite.think("★")
        }
    }
    Timer { id: unblink; interval: 180; onTriggered: if (sprite.frame === sprite.fBlink) sprite.frame = sprite.fStand }
    function think(glyph) { if (busy || bubble !== "" || Pet.calm) return; bubble = glyph; thought.restart() }
    Timer { id: thought; interval: 2200; onTriggered: if (!sprite.busy && sprite.mood === "idle") sprite.bubble = "" }

    // ---- chasing the pointer: runs to the spot nearest it, sits and watches, pounces when it rests ----
    readonly property real ptr: Pet.pointDemo >= 0 ? Pet.pointDemo : pointerX
    readonly property bool lured: active && !busy && !carried && Pet.chase && !Pet.calm && ptr >= 0
                                  && (mood === "idle" || mood === "dance" || mood === "break" || Pet.pointDemo >= 0)
    property real lastPtr: -1
    property int stillTicks: 0              // how long the pointer has rested within reach
    property double pouncedAt: 0
    property int awayTicks: 0               // how long the pointer has been out of reach while it sat
    property double turnedAt: 0             // when it last set off the other way
    function chaseStep() {
        if (kind.shell && nature.startled(ptr, lastPtr)) { lastPtr = ptr; return }      // the pointer darted at the turtle
        if (kind.flees && Pet.bond < 30) {          // the bird, not yet tame: it keeps its distance
            if (!walking && Math.abs(ptr - (x + size / 2)) < 70 && Date.now() - pouncedAt > 9000) {
                pouncedAt = Date.now()
                let far = x, off = -1               // the open spot furthest from the pointer
                for (const g of gaps) {
                    if (g.to - g.from < size + 8) continue
                    for (const v of [g.from, g.to - size]) if (Math.abs(v - ptr) > off) { off = Math.abs(v - ptr); far = v }
                }
                walkTo(far, 220)
            } else if (!walking) rest()
            lastPtr = ptr
            return
        }
        const t = nearestSpot(ptr - size / 2 - who * 44 * k)      // the friend keeps a place beside the other
        // It gets up only when the pointer has gone some way off (the frog lets it go further:
        // its tongue is long); nearer than that it stays sitting and just turns to watch.
        // It is slow to take the bait, too: it waits a moment before getting up, and once under
        // way it does not turn about within most of a second unless the pointer has gone far.
        // (It used to follow so closely that wiggling the pointer over it jerked it left and right.)
        const reach = (kind.tongue ? 100 : 48) * k
        const off = Math.abs(t - x), far = off > 160 * k
        if (off > (walking ? 10 : reach)) {
            stillTicks = 0
            const left = t < x
            if (!walking && !far && ++awayTicks < 3) { lastPtr = ptr; return }
            if (walking && left !== faceLeft && !far && Date.now() - turnedAt < 800) { lastPtr = ptr; return }
            awayTicks = 0
            if (!walking || Math.abs(walkTarget - t) > 24 * k) {
                if (left !== faceLeft) turnedAt = Date.now()
                walkTo(t, 170)
            }
        } else if (!walking) {
            awayTicks = 0
            rest()
            stillTicks = Sys.tipTarget === sprite ? 0 : Math.abs(ptr - lastPtr) < 3 ? stillTicks + 1 : 0
            if (stillTicks >= 5 && Math.abs(ptr - (x + size / 2)) < reach + 30 && Date.now() - pouncedAt > 4000) {
                if (kind.tongue) flick(ptr)                 // the frog snaps at it
                else if (kind.pounces) pounce()             // the cat leaps
                else begAt()                                // the dog asks nicely
            }
        }
        lastPtr = ptr
    }
    Timer { interval: 150; repeat: true; triggeredOnStart: true; running: sprite.lured; onTriggered: sprite.chaseStep() }
    Timer { id: lostIt; interval: 1500; onTriggered: sprite.settle() }      // the pointer left: back to what it was doing
    onLuredChanged: { stillTicks = 0; if (lured) lostIt.stop(); else if (!busy) lostIt.restart() }

    function pounce() {
        busy = true
        pouncedAt = Date.now()
        faceLeft = ptr < x + size / 2
        frame = fPounce
        bubble = ""
        leap.restart()
    }
    SequentialAnimation {
        id: leap
        NumberAnimation { target: sprite; property: "hop"; to: -9; duration: 130; easing.type: Easing.OutQuad }
        NumberAnimation { target: sprite; property: "hop"; to: 0; duration: 170; easing.type: Easing.InQuad }
        onFinished: {
            sprite.frame = sprite.fSit
            if (Math.random() < 0.35) { sprite.bubble = "♥"; oneShotDone.interval = 900 } else oneShotDone.interval = 250
            oneShotDone.restart()
        }
    }
    Timer { id: oneShotDone; onTriggered: sprite.endBusy() }
    function begAt() {
        busy = true
        pouncedAt = Date.now()
        faceLeft = ptr < x + size / 2
        frame = fGroom
        bubble = "♥"
        oneShotDone.interval = 1200
        oneShotDone.restart()
    }
    // the frog's tongue: out to bar position `to` and back; `caught`: it got the moth
    property real tongueTo: 0
    property bool tongueOut: false
    property bool caughtIt: false
    function flick(to, caught) {
        busy = true
        pouncedAt = Date.now()
        stopMoving(); walking = false; afterWalk = null
        faceLeft = to < x + size / 2
        frame = fEat
        bubble = ""
        hop = 0
        caughtIt = caught === true
        tongueTo = to
        tongueOut = true
        tongueBack.restart()
    }
    Timer {
        id: tongueBack; interval: 190
        onTriggered: {
            sprite.tongueOut = false
            sprite.frame = sprite.fSit
            if (sprite.caughtIt) sprite.bubble = "♥"
            if (sprite.caughtIt) PetSound.caught(sprite)
            oneShotDone.interval = sprite.caughtIt ? 1000 : 300
            oneShotDone.restart()
        }
    }
    Rectangle {
        visible: sprite.tongueOut
        readonly property real mouth: sprite.faceLeft ? 2 : sprite.box - 2         // sprite coordinates
        readonly property real tip: (sprite.tongueTo - sprite.x) / sprite.k
        x: Math.min(mouth, tip); width: Math.abs(tip - mouth)
        y: 17; height: 2; radius: 1
        color: "#e58a8a"
    }

    // ---- a pat: heart and a little hop.  cheer: the same with another glyph ----
    function patted(glyph) {
        if (!active) return
        busy = true
        stopMoving(); walking = false; afterWalk = null
        if (mood !== "asleep") { if (kind.barks) { frame = fStand; wag(10, 120) } else frame = fSit }      // the dog wags
        bubble = glyph || antics.patGlyph() || (kind.purrs && Math.random() < 0.4 ? "purr" : "♥")
        patHop.restart()
        oneShotDone.interval = 1400
        oneShotDone.restart()
    }
    // tail: a few swings between the two standing frames (the dog's wag, the cat's flick)
    property int wags: 0
    function wag(n, ms) { wags = n; wagStep.interval = ms; wagStep.restart() }
    Timer {
        id: wagStep; repeat: true
        onTriggered: {
            const standing = sprite.frame === sprite.fStand || sprite.frame === sprite.fTail
            if (!standing || sprite.walking || sprite.wags <= 0) {
                wagStep.stop()
                if (sprite.frame === sprite.fTail) sprite.frame = sprite.fStand
                return
            }
            sprite.frame = sprite.wags-- % 2 ? sprite.fStand : sprite.fTail
        }
    }
    SequentialAnimation {
        id: patHop
        NumberAnimation { target: sprite; property: "hop"; to: -6; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: sprite; property: "hop"; to: 0; duration: 160; easing.type: Easing.InQuad }
    }
    Connections {
        target: Pet
        function onPat(who) { if (who < 0 || who === sprite.who) sprite.patted() }
        function onFeed() { if (!PetPlay.feeding(sprite)) sprite.fed() }       // with a friend there, they eat side by side
        function onPlay() { if (sprite.who === 0 && !PetPlay.ballFor(sprite)) sprite.playBall() }     // with a friend there, the ball game for two
        function onBug() { if (sprite.who === 0) sprite.bugVisit(true) }
        function onTrick(name) { if (sprite.who === 0) sprite.doTrick(name) }
        function onNuzzle() {
            if (!sprite.active || sprite.busy || sprite.mood !== "idle") { sprite.rest(); return }
            sprite.faceLeft = sprite.otherX < sprite.x
            sprite.patted("♥")
        }
        function onAlertGlyphChanged() { if (sprite.mood === "alert") sprite.rest() }
        function onFocusLeftChanged() { if (sprite.mood === "focus") sprite.rest() }
        function onCheer() { sprite.patted("♥") }
        function onGreet() { sprite.greet() }
        function onDrop() { if (sprite.who === 0) sprite.dropVisit(true) }
    }
    Connections {     // a remark of its own (PetSay.qml): a hop and a few characters beside its head, held five seconds
        target: PetSay
        function onRemark(glyph) { if (sprite.who !== 0 || !sprite.active || sprite.busy) return; sprite.patted(glyph); oneShotDone.interval = 5000; oneShotDone.restart() }
    }
    // a break in a work and break cycle (PetFocus.qml): a ball game once the cheer is over, and now and then another
    Connections {
        target: PetFocus
        function onBreakBegan() { if (sprite.who === 0) breakPlay.restart() }
        function onBreakLeftChanged() { if (sprite.mood !== "break") return; sprite.rest(); if (sprite.who === 0 && Math.random() < 0.3) breakPlay.restart() }
    }
    Timer { id: breakPlay; interval: 1700; onTriggered: if (sprite.mood === "break" && !Pet.calm) sprite.playBall() }
    Connections { target: UPower; function onOnBatteryChanged() { if (!UPower.onBattery && sprite.mood !== "asleep") sprite.patted(Icons.batCharging) } }
    Connections { target: PetArc; function onCelebrate(glyph) { if (sprite.active && !sprite.busy) { sprite.patted(glyph); PetArc.taken = true } } }     // a milestone reached (PetArc.qml)

    // ---- you are back (the screen was just unlocked): it is glad to see you ----
    function greet() {
        if (!active || busy || mood === "asleep" || mood === "focus") return
        busy = true
        stopMoving(); walking = false; afterWalk = null; grooming = false
        frame = fSit
        bubble = kind.speak
        Pet.bump("greet", 1)
        jumps.restart()
        trickDone.interval = 1300
        trickDone.restart()
    }

    // ---- tricks: a pose or a move held for a moment, then (often) a heart ----
    property int spins: 0
    function doTrick(name) {
        if (!active || busy || mood === "asleep") return
        if (name === "fetch") { playBall(); return }
        busy = true
        stopMoving(); walking = false; afterWalk = null; grooming = false
        bubble = ""
        hop = 0
        if (Math.random() > Pet.obeys) {           // not in the mood: it looks the other way
            faceLeft = !faceLeft
            frame = fSit
            bubble = "..."
            oneShotDone.interval = 1600
            oneShotDone.restart()
            return
        }
        Pet.bump("trick", 2)
        spinStep.interval = Math.max(130, 130 / kind.pace)        // the turtle turns slowly
        if (nature.trick(name) || antics.trick(name)) return        // hide, peek, pounce (PetNature.qml); breathe fire (PetAntics.qml)
        if (name === "speak" || name === "croak" || name === "sing") PetSound.voice(sprite)       // the tricks that are a sound
        if (name === "catch") { flick(x + (faceLeft ? -70 : size + 70)); return }
        let hold = 2200
        if (name === "sit") frame = fSit
        else if (name === "lie down") frame = fLoaf
        else if (name === "beg") { frame = fGroom; bubble = "♥" }
        else if (name === "play dead") { frame = fSleep; bubble = "..."; hold = 3000 }
        else if (name === "speak" || name === "croak") { frame = name === "croak" ? fGroom : fSit; bubble = kind.speak; patHop.restart(); hold = 1500 }
        else if (name === "jump" || name === "hop") { frame = fPounce; jumps.restart(); hold = 900 }
        else if (name === "sing") { frame = fSit; bubble = "♪ ♪"; patHop.restart(); hold = 1800 }
        else if (name === "peck") { frame = fEat; hold = 1400 }
        else if (name === "fly" && home) {           // to the far end of its stretch of bar and back
            const from = x, far = Math.abs(home.from - x) > Math.abs(home.to - size - x) ? home.from : home.to - size
            walkTo(far, 220, function() {
                sprite.walkTo(from, 220, function() { sprite.frame = sprite.fSit; trickDone.interval = 300; trickDone.restart() })
            })
            return
        }
        else if (name === "spin") { spins = 8; spinStep.restart(); return }       // ends itself
        else { busy = false; return }
        trickDone.interval = hold
        trickDone.restart()
    }
    Timer { id: trickDone; onTriggered: { if (Math.random() < Pet.pleased) sprite.patted("♥"); else sprite.endBusy() } }
    Timer {
        id: spinStep; interval: 130; repeat: true
        onTriggered: {
            sprite.faceLeft = !sprite.faceLeft
            sprite.frame = sprite.fWalk + sprite.spins % 2
            if (--sprite.spins <= 0) { spinStep.stop(); sprite.frame = sprite.fSit; trickDone.interval = 300; trickDone.restart() }
        }
    }
    SequentialAnimation {
        id: jumps
        loops: 2
        NumberAnimation { target: sprite; property: "hop"; to: -8; duration: 150; easing.type: Easing.OutQuad }
        NumberAnimation { target: sprite; property: "hop"; to: 0; duration: 190; easing.type: Easing.InQuad }
    }

    // ---- fed: head down over a fish, then it is pleased ----
    function fed() {
        if (!active) return
        busy = true
        stopMoving(); walking = false; afterWalk = null
        frame = fEat
        hop = 0
        bubble = kind.food
        eating.restart()
    }
    Timer { id: eating; interval: 1500; onTriggered: sprite.patted() }

    // ---- the ball: it rolls off; the cat (and the frog) run after it and bat it away again, three
    // times; the dog fetches: runs it down, carries it back to where it started, twice ----
    property bool carrying: false
    property real fetchHome: 0
    function fetchThrow() {
        carrying = false
        ballX = x + size / 2
        let to = ballX
        for (let i = 0; i < 8 && Math.abs(to - ballX) < 120; i++) to = home.from + 6 + Math.random() * (home.to - home.from - 12)
        roll.to = to
        roll.restart()
        walkTo(clampX(to - size / 2), 200, function() {
            sprite.carrying = true
            sprite.walkTo(sprite.fetchHome, 150, function() {
                sprite.carrying = false
                sprite.ballX = sprite.x + sprite.size / 2
                sprite.faceLeft = false
                sprite.throwsLeft--
                if (sprite.throwsLeft > 0) { sprite.frame = sprite.fSit; bat.restart() }
                else { sprite.ballOut = false; sprite.patted("♥") }
            })
        })
    }
    property real ballX: 0                  // bar coordinates
    property bool ballOut: false
    property int throwsLeft: 0
    function playBall() {
        if (!active || busy || mood === "asleep" || !home) return
        busy = true
        bubble = ""
        hop = 0
        ballX = x + size / 2
        ballOut = true
        if (kind.steals) { nature.stealBall(); return }         // the fox runs off with it
        if (kind.fetches) { throwsLeft = 2; fetchHome = clampX(x); fetchThrow() }
        else { throwsLeft = 3; throwBall() }
    }
    function throwBall() {
        let to = ballX
        for (let i = 0; i < 8 && Math.abs(to - ballX) < 90; i++) to = home.from + 6 + Math.random() * (home.to - home.from - 12)
        roll.to = to
        roll.restart()
        const stand = clampX(to - size / 2 + (to > x ? -12 : 12))
        walkTo(stand, 190, function() {
            sprite.faceLeft = sprite.ballX < sprite.x + sprite.size / 2
            sprite.throwsLeft--
            if (sprite.throwsLeft > 0) { sprite.frame = sprite.fPounce; bat.restart() }
            else { sprite.ballOut = false; sprite.patted() }
        })
    }
    NumberAnimation { id: roll; target: sprite; property: "ballX"; duration: 520; easing.type: Easing.OutCubic }
    Timer { id: bat; interval: 320; onTriggered: { if (sprite.kind.fetches) sprite.fetchThrow(); else sprite.throwBall() } }
    Rectangle {
        visible: sprite.ballOut
        x: sprite.carrying ? (sprite.faceLeft ? 0 : sprite.box - 8) : (sprite.ballX - sprite.x) / sprite.k - 4     // carried in its mouth
        y: sprite.carrying ? 14 : sprite.box - 9 - sprite.hop
        width: 8; height: 8; radius: 4
        color: Theme.alt
        border.width: 1
        border.color: Theme.altInk          // light in both themes: what is behind it is the wallpaper, purple in light mode
    }

    // ---- a moth flies along the bar and the cub goes after it (it never catches it) ----
    property real bugX: 0                   // bar coordinates
    property bool bugOut: false
    function bugVisit(asked) {              // asked: sent from its menu or a script, so it comes whatever the mood (bar asleep)
        if (!active || busy || !home || mood === "asleep") return
        if (!asked && (lured || mood !== "idle" || Pet.weather === "rain")) return
        busy = true
        bubble = ""
        grooming = false
        const ltr = Math.random() < 0.5
        bugFly.from = ltr ? home.from : home.to
        bugFly.to = ltr ? home.to : home.from
        bugFly.duration = (home.to - home.from) / 60 * 1000
        bugX = bugFly.from
        bugOut = true
        bugFly.restart()
    }
    NumberAnimation {
        id: bugFly; target: sprite; property: "bugX"
        onFinished: {
            sprite.bugOut = false
            stopMoving(); sprite.walking = false; sprite.afterWalk = null
            sprite.frame = sprite.fSit
            sprite.faceLeft = bugFly.to < sprite.x
            if (sprite.kind.barks) sprite.bubble = sprite.kind.speak        // the dog tells it off as it goes
            oneShotDone.interval = 1300
            oneShotDone.restart()
        }
    }
    Timer {
        interval: 200; repeat: true; running: sprite.bugOut
        onTriggered: {
            if (sprite.kind.flies) {            // the bird goes after it on the wing, and gets it
                if (Math.abs(sprite.bugX - (sprite.x + sprite.size / 2)) < 26) { bugFly.stop(); sprite.bugOut = false; PetSound.caught(sprite); sprite.patted("♥"); return }
                const to = sprite.clampX(sprite.bugX - sprite.size / 2)
                if (!sprite.walking || Math.abs(sprite.walkTarget - to) > 40) sprite.walkTo(to, 200)
                return
            }
            if (sprite.kind.tongue) {           // the frog does not run: it watches, and when the moth is in reach it has it
                sprite.faceLeft = sprite.bugX < sprite.x + sprite.size / 2
                if (Math.abs(sprite.bugX - (sprite.x + sprite.size / 2)) < 85) { bugFly.stop(); sprite.bugOut = false; sprite.flick(sprite.bugX, true) }
                return
            }
            const t = sprite.clampX(sprite.bugX - sprite.size / 2 + (bugFly.to > bugFly.from ? -26 : 26))
            if (Math.abs(t - sprite.x) > 12 && (!sprite.walking || Math.abs(sprite.walkTarget - t) > 30))
                sprite.walkTo(t, 150, function() { sprite.frame = sprite.fPounce; swipe.restart() })
        }
    }
    SequentialAnimation {
        id: swipe
        NumberAnimation { target: sprite; property: "hop"; to: -7; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: sprite; property: "hop"; to: 0; duration: 150; easing.type: Easing.InQuad }
    }
    Timer {     // by itself: about every seven minutes there is a fair chance of one
        interval: PetPrefs.ambientMs; repeat: true
        running: sprite.who === 0 && sprite.active && sprite.mood === "idle" && !UPower.onBattery && !Pet.calm
        onTriggered: {
            if (Math.random() >= PetPrefs.ambientChance) return
            if (sprite.dropKind !== "" && Math.random() < 0.5) sprite.dropVisit(); else sprite.bugVisit()
        }
    }
    Item {
        visible: sprite.bugOut
        x: (sprite.bugX - sprite.x) / sprite.k
        y: 5 + 4 * Math.sin(sprite.bugX / 9) - sprite.hop
        Rectangle { width: 4; height: 4; radius: 2; color: "#f0c674" }
        Rectangle { x: Math.floor(sprite.bugX / 5) % 2 ? -3 : 3; y: -2; width: 3; height: 3; radius: 1.5; color: "#f0c674"; opacity: 0.7 }
    }

    // ---- something of the season lands on the bar (a leaf, a snowflake, a petal): it goes over,
    // has a look in its own way (the cat bats it, the dog and the bird nose at it, the frog
    // just stares), and it is gone ----
    readonly property string dropKind: WallState.seasonKind === "leaves" ? "leaf" : WallState.seasonKind === "snow" ? "flake"
                                       : WallState.seasonKind === "petals" ? "petal" : ""
    property real dropX: 0                  // bar coordinates
    property real dropY: 0                  // sprite coordinates
    property bool dropOut: false
    property string dropShown: "leaf"
    function dropVisit(asked) {
        if (!active || busy || !home || mood === "asleep") return
        if (!asked && (lured || mood !== "idle" || dropKind === "")) return
        busy = true
        bubble = ""
        grooming = false
        dropShown = dropKind !== "" ? dropKind : "leaf"
        dropX = x
        for (let i = 0; i < 8 && Math.abs(dropX - (x + size / 2)) < 70; i++) dropX = home.from + 8 + Math.random() * (home.to - home.from - 16)
        dropY = -8
        dropOut = true
        faceLeft = dropX < x + size / 2
        dropFall.restart()
    }
    NumberAnimation {
        id: dropFall; target: sprite; property: "dropY"; to: sprite.box - 11; duration: 1600; easing.type: Easing.InOutSine
        onFinished: sprite.walkTo(sprite.clampX(sprite.dropX - sprite.size / 2 + (sprite.dropX > sprite.x ? -14 : 14)), 80, function() {
            sprite.faceLeft = sprite.dropX < sprite.x + sprite.size / 2
            sprite.frame = sprite.kind.pounces ? sprite.fPounce : sprite.kind.tongue ? sprite.fBlink : sprite.fEat
            if (sprite.kind.pounces) swipe.restart()
            dropGone.restart()
        })
    }
    Timer {
        id: dropGone; interval: 1000
        onTriggered: {
            sprite.dropOut = false
            sprite.frame = sprite.fSit
            if (Math.random() < Pet.pleased) { sprite.bubble = "♥"; oneShotDone.interval = 900 } else oneShotDone.interval = 300
            oneShotDone.restart()
        }
    }
    Item {
        visible: sprite.dropOut
        x: (sprite.dropX - sprite.x) / sprite.k + 3 * Math.sin(sprite.dropY / 5)     // it sways as it comes down
        y: sprite.dropY - sprite.hop
        Text {
            visible: sprite.dropShown !== "petal"
            anchors.centerIn: parent
            text: sprite.dropShown === "flake" ? Icons.flake : Icons.leaf
            color: sprite.dropShown === "flake" ? Theme.fg : "#e0a030"
            rotation: sprite.dropY * 6
            style: Text.Outline; styleColor: Theme.solidBg
            font { family: Theme.font; pixelSize: 11 }
        }
        Rectangle { visible: sprite.dropShown === "petal"; anchors.centerIn: parent; width: 7; height: 4; radius: 2; color: "#e8b7c4"; rotation: sprite.dropY * 6 }
    }

    // ---- a change of desktop: now and then it turns to look ----
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "workspacev2" || !sprite.active || sprite.busy || sprite.walking || sprite.lured || sprite.mood !== "idle") return
            if (Math.random() < 0.35) { sprite.faceLeft = !sprite.faceLeft; sprite.frame = sprite.fBlink; unblink.restart() }
        }
    }

    // ---- carried: press and drag it along the bar; it dangles until it is put down ----
    property bool carried: false
    function carryTo(barX) {
        if (!carried) { reset(); carried = true; busy = true; frame = fPounce; hop = -5 }     // reset: whatever it was in the middle of is dropped
        faceLeft = barX < x + size / 2
        carryAt = barX
        x = nearestSpot(barX - size / 2)
    }
    function putDown() {
        carried = false
        hop = 0
        frame = fSit
        Pet.setSpot(spotKey, x)
        if (antics.dropped(carryAt)) return                     // onto the bell or the clock (PetAntics.qml)
        if (kind.shell) { nature.shellIn(2500); return }        // set down, the turtle stays in its shell a while
        oneShotDone.interval = 500
        oneShotDone.restart()
    }

    readonly property string where: "x=" + Math.round(x) + (walking ? " walking" : "") + (walking ? " to " + Math.round(walkTarget) : "")
        + (busy ? " busy" : "") + (carried ? " carried" : "") + (bugOut ? " bug=" + Math.round(bugX) : "") + (dropOut ? " drop=" + Math.round(dropX) : "") + (active ? "" : " inactive") + (lured ? " lured by " + Math.round(ptr) : "") + " frame=" + frame
        + (ballOut ? " ball=" + Math.round(ballX) : "")
        + " bell=" + Math.round(bellX) + " music=" + Math.round(musicX) + " clock=" + Math.round(clockX)
        + " gaps=" + gaps.map(g => Math.round(g.from) + "-" + Math.round(g.to)).join(",")
    onWhereChanged: if (shown && who === 0) Pet.where = where

    Item {      // the animal and its hat, mirrored together when it faces left
        anchors.fill: parent
        transform: Scale {
            origin.x: sprite.box / 2; xScale: sprite.faceLeft ? -1 : 1
            // on its back: turned over about the middle of what is drawn, so it stays on the floor
            origin.y: ((Heads.heads[sprite.animal] || [])[sprite.frame] || [12, 9])[1] + 15; yScale: sprite.upside ? -1 : 1
        }
        Item {      // one 16x16 frame out of the sheet, enlarged with hard pixels
            anchors.fill: parent
            clip: true
            Image {
                readonly property bool fitOk: true     // a sprite sheet: cut to one frame on purpose (Fit.qml)
                x: -sprite.frame * sprite.box
                width: sourceSize.width * sprite.px
                height: sprite.box
                // from `look` in one go: animal and coat taken one after the other gave, for an instant, a sheet that does not exist
                source: sprite.look.animal !== "" ? Qt.resolvedUrl("assets/pet-" + sprite.look.animal + "-" + sprite.look.coat + ".png") : ""
                smooth: false
                cache: false
            }
        }
        Image {     // hat: its bottom row sits on the top of the head (assets/pet-anchors.js says where that is)
            visible: Pet.hat !== "" && !sprite.upside
            readonly property var head: (Heads.heads[sprite.animal] || [])[sprite.frame] || [12, 2]
            readonly property var dim: Heads.hats[Pet.hat] || [0, 0]
            x: Math.round((head[0] - dim[0] / 2) * sprite.px)
            y: (head[1] - dim[1] + 1) * sprite.px
            width: dim[0] * sprite.px; height: dim[1] * sprite.px
            source: Pet.hat !== "" ? Qt.resolvedUrl("assets/hat-" + Pet.hat + ".png") : ""
            smooth: false
        }
    }
    Text {
        visible: sprite.bubble !== ""
        anchors { top: parent.top; left: parent.right; leftMargin: -3 }      // beside its head: the bar has no room above
        text: sprite.bubble
        color: sprite.mood === "alert" && !sprite.busy && !sprite.lured ? Theme.accent : sprite.bubble === "♥" ? Theme.red : sprite.bubble === "z" ? Theme.faint : sprite.bubble === "!" || sprite.bubble === "♪" ? Theme.accent : Theme.fg
        // a halo: behind it is the wallpaper, not a pill, and in light mode that is deep purple
        style: Text.Outline; styleColor: Theme.solidBg
        font { family: Theme.font; pixelSize: 12; bold: true }
    }
    Text {      // its sign (PetSign.qml): low on the tail side, below the bubble's height; outside the mirrored item so it always reads forwards
        visible: sprite.who === 0 && sprite.mood !== "asleep" && !Pet.hiding && PetSign.text !== ""
        x: sprite.faceLeft ? sprite.box : -width
        anchors { bottom: parent.bottom; bottomMargin: 3 }
        text: PetSign.text
        color: PetSign.color
        style: Text.Outline; styleColor: Theme.solidBg
        font { family: Theme.font; pixelSize: 9 }
    }
    Text {      // in the rain it keeps an umbrella up (not while it sleeps or runs about)
        visible: Pet.weather === "rain" && sprite.kind.rain === "umbrella" && sprite.mood !== "asleep" && !sprite.busy
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: -3 }
        text: Icons.umbrella
        color: Theme.dark ? "#b294bb" : Theme.alt
        style: Text.Outline; styleColor: Theme.solidBg
        font { family: Theme.font; pixelSize: 15 }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        enabled: sprite.active && (sprite.carried || sprite.atop || (!sprite.walking && sprite.inGaps(sprite.x)))      // never in the way of a pill it is passing
        property real pressAt: 0
        property bool moved: false
        function barX(mouse) { return area.mapToItem(sprite.parent, mouse.x, mouse.y).x }
        onPressed: mouse => { antics.stir(); pressAt = barX(mouse); moved = false; tipDelay.stop(); Sys.tipTarget = null }
        onPositionChanged: mouse => {
            antics.stir()
            if (!(mouse.buttons & Qt.LeftButton)) { if (sprite.carried) sprite.putDown(); return }
            const at = barX(mouse)
            if (!moved && Math.abs(at - pressAt) < 8) return
            moved = true
            sprite.carryTo(at)
        }
        onReleased: if (sprite.carried) sprite.putDown()
        onClicked: mouse => {
            Sys.tipTarget = null
            if (moved) return                                    // that was a carry, not a click
            if (mouse.button === Qt.MiddleButton) { Pet.menuPage = "say"; sprite.menuRequested(); return }     // what's up? (PetSay.qml)
            if (mouse.button === Qt.LeftButton && PetRemind.ringing) PetRemind.done()      // seen: the reminder is acknowledged
            if (mouse.button === Qt.RightButton) { sprite.menuRequested(); return }
            PetSecrets.unfool()                                  // the first of April: seen through
            if (!antics.tapped()) Pet.petIt(sprite.who)          // the tenth quick pat is one too many
        }
        onWheel: wheel => { if (wheel.angleDelta.y !== 0) Pet.playWith() }
        onEntered: if (!pressed && !sprite.carried) tipDelay.restart()
        onCanceled: if (sprite.carried) sprite.putDown()        // the press was taken away: do not leave it dangling
        onExited: { antics.stir(); tipDelay.stop(); if (Sys.tipTarget === sprite) Sys.tipTarget = null }
    }
    Timer {
        id: tipDelay
        interval: 900
        onTriggered: {
            if (area.pressed || sprite.carried || sprite.walking) return
            Sys.tipText = sprite.who === 1 ? "<b>" + Pet.name + "'s friend</b>, the " + sprite.animal + "\nClick: pet    Right-click: menu"
                        : "<b>" + Pet.name + "</b> is " + Pet.doing + "\nBond " + Pet.hearts + "\nClick: pet    Scroll: play    Right-click: menu"
            Sys.tipWindow = sprite.QsWindow.window
            if (sprite.who === 0) Sys.tipText += PetSay.tipLine        // how to ask it what's up, and its last remark
            Sys.tipTarget = sprite
        }
    }
}
