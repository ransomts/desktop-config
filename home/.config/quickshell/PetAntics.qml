// What a sprite does about the pet's secrets (PetSecrets.qml knows which exist and which
// have been found; the list, with spoilers, is at the top of that file). Each PetSprite has
// one of these and calls in at a few places, as with PetNature.qml.
// One antic at a time (`act`); the sprite is `busy` for as long as it lasts, and whatever
// ends that (a pat, being picked up, the watchdog) ends the antic too. No timer here runs
// unless an antic is under way, the pointer is resting on it, or paw prints are fading.
import QtQuick
import Quickshell.Services.UPower

Item {
    id: antics
    property Item sprite: null
    property string act: ""                 // dizzy | doze | bell | clock | sulk | star | ufo | td | push | fire

    function hold(name) {                   // stop where it is and be busy with `name`
        const s = sprite
        s.stopMoving(); s.walking = false; s.afterWalk = null; s.grooming = false
        s.hop = 0; s.bubble = ""
        s.busy = true
        act = name
    }
    property var next: null
    Timer {
        id: wait
        onTriggered: {
            const f = antics.next
            antics.next = null
            if (f && antics.act !== "" && antics.sprite.busy && !antics.sprite.carried) f()
        }
    }
    function after(ms, f) { next = f; wait.interval = ms; wait.restart() }
    function finish() { clear(); sprite.endBusy() }
    function clear() {                      // whatever was drawn or held for an antic is let go
        wait.stop(); spin.stop(); cheer.stop(); flicker.stop()
        next = null; act = ""
        dozing = false; fire = false
        if (sprite) { sprite.upside = false; sprite.weigh = false; sprite.atop = false }
    }
    function reset() { clear(); still = 0 }
    Connections { target: antics.sprite; function onBusyChanged() { if (!antics.sprite.busy && antics.act !== "") antics.clear() } }

    // ---- dizzy: ten pats inside four seconds ----
    property var taps: []
    property int turns: 0
    function tapped() {                     // true: that was the tenth, and it is not a pat
        const t = Date.now(), keep = taps.filter(x => t - x < 4000)
        keep.push(t)
        taps = keep
        if (keep.length < 10 || sprite.mood === "asleep" || act === "dizzy") return false
        taps = []
        dizzy()
        return true
    }
    function dizzy() {
        sprite.reset()
        hold("dizzy")
        sprite.bubble = "@_@"
        turns = 10
        spin.restart()
        PetSecrets.found("dizzy")
    }
    Timer {
        id: spin; interval: 90; repeat: true
        onTriggered: {
            const s = antics.sprite
            s.faceLeft = !s.faceLeft
            s.frame = s.fWalk + antics.turns % 2
            if (--antics.turns > 0) return
            stop()
            s.frame = s.fLoaf               // and over it goes, onto its back
            s.upside = true
            antics.after(2600, function() {
                s.upside = false
                s.frame = s.fSit
                s.bubble = ""
                antics.after(500, antics.finish)
            })
        }
    }

    // ---- a warm spot: the pointer rests on it for a minute, and it goes to sleep there ----
    property int dozeMs: 60000
    property int still: 0                   // twelfths of that minute the pointer has not moved
    property bool dozing: false
    Timer {
        interval: antics.dozeMs / 12; repeat: true
        running: antics.sprite !== null && antics.sprite.active && !antics.dozing && (antics.sprite.hovered || antics.still > 0)
        onTriggered: {
            const s = antics.sprite
            if (!s.hovered || s.mood !== "idle" || s.carried) { antics.still = 0; return }
            if (++antics.still >= 12 && !s.busy && !s.walking) antics.doze()
        }
    }
    function stir() { still = 0; if (dozing) wake() }       // the pointer moved, left, or pressed
    function doze() {
        const s = sprite
        hold("doze")
        dozing = true
        still = 0
        s.frame = s.fSleep
        s.bubble = "z"
        if (Sys.tipTarget === s) Sys.tipTarget = null
        PetSecrets.found("doze")
    }
    function wake() {
        dozing = false
        sprite.frame = sprite.fBlink
        sprite.bubble = "!"
        after(600, finish)
    }

    // ---- put down on a pill: the bell rings; the clock is sat on ----
    function dropped(at) {                  // true if it landed on one (the sprite is still busy from the carry)
        const sp = sprite.spans || {}
        if (sp.bell && at >= sp.bell.from && at <= sp.bell.to) { ring(); return true }
        if (sp.clock && at >= sp.clock.from && at <= sp.clock.to) { sitOnClock(); return true }
        return false
    }
    function ring() {
        const s = sprite, sp = s.spans || {}
        hold("bell")
        if (sp.bell) { s.x = Math.round((sp.bell.from + sp.bell.to) / 2 - s.size / 2); s.atop = true }     // up against the bell
        s.frame = s.fPounce
        s.hopOnce()
        s.bubble = "ding!"
        s.rang()
        PetSecrets.found("bell")
        after(1300, finish)
    }
    function sitOnClock() {
        const s = sprite, sp = s.spans || {}
        if (!sp.clock) return
        hold("clock")
        s.x = Math.round((sp.clock.from + sp.clock.to) / 2 - s.size / 2)
        s.frame = s.fSit
        s.atop = true
        s.weigh = true                      // in front of the pill, which sinks under it (Bar.qml)
        PetSecrets.found("clock")
        after(6000, function() {
            s.weigh = false; s.atop = false
            s.frame = s.fPounce
            s.hopOnce()
            antics.finish()                 // settle() walks it out to the nearest open spot
        })
    }

    // ---- named after its own kind: it is not amused ----
    function sulk() {
        const s = sprite
        s.reset()
        hold("sulk")
        s.faceLeft = !s.faceLeft
        s.frame = s.fSit
        s.bubble = "..."
        PetSecrets.found("species")
        after(2400, function() { s.bubble = "hmph"; antics.after(1300, antics.finish) })
    }
    function patGlyph() { return sprite.who === 0 && PetSecrets.offended && Math.random() < 0.25 ? "hmph" : "" }
    Connections {
        target: Pet
        function onNameChanged() {
            Qt.callLater(function() {
                const s = antics.sprite
                if (s && s.who === 0 && s.active && !s.carried && s.mood !== "asleep" && PetSecrets.offended) antics.sulk()
            })
        }
    }

    // ---- a Clemson name: orange paw prints behind it as it walks, fading ----
    property var prints: []                 // [{ x: bar coordinates, t: when }]
    property real lastPrint: -1e9
    property double now: 0
    Connections {
        target: antics.sprite
        function onXChanged() {
            const s = antics.sprite
            if (!PetSecrets.clemson || s.who !== 0 || !s.walking || s.flying || s.carried || !s.active) return
            if (Math.abs(s.x - antics.lastPrint) < 14 * s.k) return
            antics.lastPrint = s.x
            antics.now = Date.now()
            antics.prints = antics.prints.slice(-4).concat([{ x: s.x + (s.faceLeft ? s.size - 8 * s.k : 2 * s.k), t: antics.now }])
            PetSecrets.found("clemson")
        }
    }
    Timer {
        interval: 300; repeat: true; running: antics.prints.length > 0
        onTriggered: {
            antics.now = Date.now()
            const keep = antics.prints.filter(p => antics.now - p.t < 2700)
            if (keep.length !== antics.prints.length) antics.prints = keep
        }
    }
    Repeater {
        model: antics.prints
        Text {
            required property var modelData
            x: (modelData.x - antics.sprite.x) / antics.sprite.k
            y: antics.sprite.box - 9
            text: Icons.paw
            color: Theme.accent
            opacity: Math.max(0, 0.9 - (antics.now - modelData.t) / 3000)
            font { family: Theme.font; pixelSize: 7 }
        }
    }

    // ---- the sky (PetSecrets.sky): a shooting star to watch, something else to hide from ----
    Connections {
        target: PetSecrets
        function onSkyChanged() {
            const s = antics.sprite, what = PetSecrets.sky
            if (what === "" || !s.active || s.busy || s.carried || Pet.calm || ["idle", "dance", "break"].indexOf(s.mood) < 0) return
            antics.hold(what)
            if (what === "star") {
                s.frame = s.fSit
                s.bubble = "★"
                PetSecrets.found("star")
                antics.after(3200, antics.finish)
            } else {
                s.frame = s.kind.shell ? s.fPounce : s.fLoaf       // flat on the floor; the turtle in its shell
                s.bubble = "!"
                PetSecrets.found("ufo")
                antics.after(9300, function() { s.frame = s.fSit; s.bubble = "?"; antics.after(1300, antics.finish) })
            }
        }
        function onTouchdown() {
            const s = antics.sprite
            if (!s.active || s.carried || s.mood === "asleep") return
            s.reset()
            antics.hold("td")
            s.frame = s.fPounce
            s.bubble = Icons.paw + "!"
            cheer.restart()
            PetSecrets.found("touchdown")
            antics.after(2000, function() { antics.clear(); s.patted("♥") })
        }
        function onAct(name) {              // tried from a script
            const s = antics.sprite
            if (s.who !== 0 || !s.active || s.carried) return
            if (name === "dizzy") antics.dizzy()
            else if (name === "sulk") antics.sulk()
            else if (name === "doze") { s.reset(); antics.doze() }
            else if (name === "bell") { s.reset(); antics.ring() }
            else if (name === "clock") { s.reset(); antics.sitOnClock() }
            else if (name === "push") { s.reset(); antics.push() }
            else if (name === "fire") { s.reset(); s.busy = true; antics.trick("breathe fire") }
        }
    }
    SequentialAnimation {
        id: cheer
        loops: 3
        NumberAnimation { target: antics.sprite; property: "hop"; to: -9; duration: 150; easing.type: Easing.OutQuad }
        NumberAnimation { target: antics.sprite; property: "hop"; to: 0; duration: 190; easing.type: Easing.InQuad }
    }

    // ---- the cat, close to you: it knocks the clock off the bar and watches it come back ----
    property real pushChance: 0.004         // each idle moment: about every twenty minutes
    function maybePush() {                  // from the sprite's idle life
        const s = sprite
        if (s.who !== 0 || s.animal !== "cat" || Pet.bond < 60 || Pet.calm || !(s.spans && s.spans.clock)) return false
        if (Math.random() >= pushChance * (UPower.onBattery ? 0.25 : 1)) return false
        push()
        return true
    }
    function push() {
        const s = sprite
        if (!(s.spans && s.spans.clock)) return
        hold("push")
        s.walkTo(s.nearestSpot(s.clockX), 70, function() {
            if (antics.act !== "push") return
            s.faceLeft = false
            s.frame = s.fPounce             // a paw out
            s.hopOnce()
            s.pushed()                      // Bar.qml drops the pill and brings it back
            PetSecrets.found("push")
            antics.after(450, function() {
                s.frame = s.fSit            // and it sits and watches
                antics.after(2700, function() {
                    if (Math.random() < 0.5) { antics.clear(); s.patted("purr") } else antics.finish()
                })
            })
        })
    }

    // ---- the dragon's trick; true if it was one (PetSprite has already made it busy) ----
    property bool fire: false
    property int lick: 0
    readonly property var mouth: [13, 8]    // frame 8, sprite pixels: where the flame starts
    function trick(name) {
        if (name !== "breathe fire") return false
        const s = sprite
        act = "fire"
        s.frame = s.fGroom
        fire = true
        flicker.restart()
        after(1200, function() {
            antics.fire = false
            s.frame = s.fSit
            if (Math.random() < Pet.pleased) { antics.clear(); s.patted("♥") } else antics.finish()
        })
        return true
    }
    Timer { id: flicker; interval: 90; repeat: true; onTriggered: antics.lick++ }
    Item {
        visible: antics.fire
        // the animal is mirrored when it faces left; this is not, so it is placed by hand
        x: antics.sprite && antics.sprite.faceLeft ? antics.sprite.box - antics.mouth[0] * 2 - 2 : antics.mouth[0] * 2 + 2
        y: antics.mouth[1] * 2
        transform: Scale { xScale: antics.sprite && antics.sprite.faceLeft ? -1 : 1 }
        Rectangle { x: 0; y: -2; width: 8 + antics.lick % 3 * 2; height: 5; radius: 2; color: "#f56600" }
        Rectangle { x: 6; y: -3 + antics.lick % 2; width: 7 + antics.lick % 2 * 3; height: 6; radius: 3; color: "#ff9a3c" }
        Rectangle { x: 1; y: -1; width: 6 + antics.lick % 2 * 2; height: 3; radius: 1; color: "#ffe08a" }
    }
}
