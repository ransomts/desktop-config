// What only some animals do (their traits are in Pet.qml's `kinds`), kept out of
// PetSprite.qml: each sprite has one of these, and PetSprite calls in at a few places.
//   shell (the turtle)  it pulls into its shell when a notification comes in, stays there a
//                       while, peeks out and then plods over to the bell; also when it is put
//                       down after being carried (while it dangles it already shows the shell
//                       frame) and when the pointer darts at it. Tricks: "hide" and "peek".
//   steals (the fox)    the ball game: it runs the ball down, grabs it and makes off with it to
//                       the far end of its stretch of bar, looks back, and the game is over.
//                       Trick: "pounce", a high leap nose first (frame 9 is its mousing pounce).
// No timer here runs unless one of those is under way.
import QtQuick

Item {
    id: nature
    property Item sprite: null
    visible: false

    // ---- the shell ----
    property var then: null                 // what to do once it has peeked out (else it carries on)
    property string peekGlyph: ""
    property bool peeking: false
    property double ducked: 0               // when the pointer last startled it
    function shellIn(ms, done, glyph) {
        const s = sprite
        s.busy = true
        s.stopMoving(); s.walking = false; s.afterWalk = null; s.grooming = false
        s.hop = 0
        s.bubble = s.mood === "alert" ? Pet.alertGlyph : ""        // the mark still says what came in
        s.frame = s.fPounce                 // the turtle's frame 9: head and legs pulled in
        then = done || null
        peekGlyph = glyph || ""
        peeking = false
        shellOut.interval = ms
        shellOut.restart()
    }
    Timer {
        id: shellOut
        onTriggered: {
            const s = nature.sprite
            if (s.carried || !s.busy) return            // picked up, or reset, in the meantime
            if (!nature.peeking) {                       // first a look out
                nature.peeking = true
                s.frame = s.fStand
                s.bubble = nature.peekGlyph !== "" ? nature.peekGlyph : s.mood === "alert" ? Pet.alertGlyph : "?"
                interval = 900
                restart()
                return
            }
            nature.peeking = false
            const t = nature.then
            nature.then = null
            if (t) t(); else s.endBusy()                 // endBusy: settle(), so to the bell if it is still waiting
        }
    }
    // the pointer darts in close: back into the shell (called from PetSprite's chaseStep)
    function startled(ptr, lastPtr) {
        const s = sprite
        if (lastPtr < 0 || Math.abs(ptr - lastPtr) < 40 * s.k || Math.abs(ptr - (s.x + s.size / 2)) > 40 * s.k) return false
        if (Date.now() - ducked < 6000) return false
        ducked = Date.now()
        shellIn(2500)
        return true
    }
    // a notification: into the shell instead of off to the bell (PetSprite's settle() takes it there afterwards)
    Connections {
        target: nature.sprite
        function onMoodChanged() {
            const s = nature.sprite
            if (s.mood === "alert" && s.kind.shell && s.active && !s.busy && !s.carried) nature.shellIn(3500)
        }
    }

    // ---- tricks of its own; true if it was one (PetSprite has already made it busy) ----
    function trick(name) {
        if (name === "hide") { shellIn(3000, finish); return true }
        if (name === "peek") { shellIn(900, finish, "boo!"); return true }
        if (name === "pounce") { sprite.frame = sprite.fPounce; leap.restart(); return true }
        return false
    }
    function finish() { if (Math.random() < Pet.pleased) sprite.patted("♥"); else sprite.endBusy() }     // as PetSprite's trickDone
    SequentialAnimation {
        id: leap
        NumberAnimation { target: nature.sprite; property: "hop"; to: -11; duration: 170; easing.type: Easing.OutQuad }
        NumberAnimation { target: nature.sprite; property: "hop"; to: 0; duration: 200; easing.type: Easing.InQuad }
        ScriptAction { script: { nature.sprite.frame = nature.sprite.fSit; nature.finish() } }
    }

    // ---- the fox and the ball: it does not bat it, it takes it ----
    function stealBall() {
        const s = sprite, home = s.home
        let to = s.ballX
        for (let i = 0; i < 8 && Math.abs(to - s.ballX) < 100; i++) to = home.from + 6 + Math.random() * (home.to - home.from - 12)
        ballRoll.to = to
        ballRoll.restart()
        s.walkTo(s.clampX(to - s.size / 2), 200, function() {
            s.carrying = true                   // got it
            const far = Math.abs(home.from - s.x) > Math.abs(home.to - s.size - s.x) ? home.from : home.to - s.size
            s.walkTo(far, 240, function() {     // and away with it
                s.frame = s.fSit
                s.faceLeft = !s.faceLeft        // a look back over its shoulder
                s.bubble = s.kind.speak
                kept.restart()
            })
        })
    }
    NumberAnimation { id: ballRoll; target: nature.sprite; property: "ballX"; duration: 520; easing.type: Easing.OutCubic }
    Timer {
        id: kept; interval: 1600
        onTriggered: {
            const s = nature.sprite
            if (!s.carrying) return             // reset in the meantime
            s.carrying = false
            s.ballOut = false                   // it keeps it
            s.endBusy()
        }
    }

    function reset() { shellOut.stop(); leap.stop(); ballRoll.stop(); kept.stop(); then = null; peeking = false }
}
