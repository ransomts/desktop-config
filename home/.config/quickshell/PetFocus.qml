// The bar pet's focus timer and work and break cycles (Pet.qml is its mind; Pet.focusing,
// Pet.focusLeft and Pet.startFocus hand over to this file).
//
// A single timer (its menu's 15/25/45/60 rows, `qs ipc call pet focus 25`) is as it always was:
// the pet sits with you, and when the time is up it cheers, a sound plays, a notification
// says so, and that is the end of it.
// A cycle (the menu's "Cycle: 25 / 5" row, `qs ipc call pet cycle`) goes on from there:
//   focus   the pet sits still with the minutes left beside it (mood `focus`)
//   break   it plays: a ball game, wandering, chasing the pointer, the minutes left beside it
//           when it stops (mood `break`); every fourth focus period gets the long break
//   then    the next round starts by itself ("carry on by itself" habit) or waits for you
//           (the menu's "Start round N", or `pet skip`)
// Lengths and the rest are habits (PetPrefs.qml): work, shortbreak, longbreak, carryon, focusdnd.
// Do Not Disturb while focusing (focusdnd on): starting a focus period turns Do Not Disturb on
// if it was off, and the end of the period (or Stop) turns it off again. While it is the pet's
// own Do Not Disturb the pet stays awake and keeps you company; Do Not Disturb you turned on
// yourself still puts it to sleep, as always. If you turn it off in the middle, it is yours
// again and the pet leaves it alone.
//   qs ipc call pet focus MINUTES   a single timer (0 stops)
//   qs ipc call pet cycle           a cycle with the habit lengths
//   qs ipc call pet cyclefor W S L  a cycle of W minutes of work, S short break, L long break (fractions allowed, to try it)
//   qs ipc call pet skip            focus: on to the break.  break: on to the next round.  waiting: start it
//   qs ipc call pet stopfocus       stop whatever runs (Do Not Disturb goes back as it was)
//   qs ipc call pet focusstatus     what runs, minutes left, the round, focus periods done today
// Kept in ~/.local/state/pet-focus.json: what runs and until when (a timestamp, so a reload
// carries on with the right time left), the round, whether Do Not Disturb is the pet's, and
// today's count.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: foc

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/pet-focus.json"
        blockLoading: true
        blockWrites: true           // a change made while an unfinished write was in flight used to be undone when it landed
        printErrors: false
        onAdapterUpdated: saveSoon.restart()
        JsonAdapter {
            id: store
            property string phase: ""           // "" | focus | break | wait (a cycle waiting for you after a break)
            property double until: 0            // when the focus or break ends (ms since the epoch)
            property bool cycle: false          // part of a cycle (false: a single timer)
            property int round: 1               // which focus period of four (a cycle only)
            property bool longBreak: false      // the break running is the long one
            property double workMin: 25         // this cycle's lengths, in minutes (fractions allowed)
            property double shortMin: 5
            property double longMin: 15
            property double singleMin: 25       // the single timer's length
            property bool dndMine: false        // the pet turned Do Not Disturb on and will turn it off again
            property string day: ""             // today's count is for this day (YYYY-MM-DD)
            property int done: 0                // focus periods completed that day
        }
    }
    Timer { id: saveSoon; interval: 300; onTriggered: file.writeAdapter() }

    // ---- time: "now" can be replaced (tests run a 2 s focus and a 2 s break) ----
    property var clock: null                    // a function returning ms since the epoch, or null for the real time
    function nowMs() { return clock ? clock() : Date.now() }
    property double now: nowMs()
    property int tickMs: 5000                   // how often a running period is checked (only while one runs)

    // ---- what runs ----
    readonly property string phase: store.phase
    readonly property bool active: store.phase !== ""
    readonly property bool cycle: store.cycle && active
    readonly property bool focusing: store.phase === "focus"
    readonly property bool onBreak: store.phase === "break"
    readonly property bool waiting: store.phase === "wait"
    readonly property bool longBreak: onBreak && store.longBreak
    readonly property int round: store.round
    readonly property real workMin: store.workMin           // this cycle's focus length (minutes)
    readonly property int left: focusing || onBreak ? Math.max(0, Math.ceil((store.until - now) / 60000)) : 0
    readonly property int focusLeft: focusing ? left : 0
    readonly property int breakLeft: onBreak ? left : 0
    // Do Not Disturb as the pet's moods see it: only the user's own puts it to sleep
    readonly property bool userDnd: Notif.dnd && !(store.dndMine && focusing)
    function dayKey(t) { const d = new Date(t); return d.getFullYear() + "-" + (d.getMonth() < 9 ? "0" : "") + (d.getMonth() + 1) + "-" + (d.getDate() < 10 ? "0" : "") + d.getDate() }
    readonly property int doneToday: { Sys.nowHM; return store.day === dayKey(now) ? store.done : 0 }
    signal breakBegan()                         // the sprite starts its ball game

    // ---- for the menu (PetMenu.qml, PetFocusPage.qml) ----
    function mins(m) { return Math.round(m * 10) / 10 }
    readonly property string mainLabel: focusing && !store.cycle ? "Stop the focus timer" : focusing ? "Focus, round " + round
                                        : onBreak ? (store.longBreak ? "Long break" : "Break") : waiting ? "Round " + round + " is next" : "Focus timer"
    readonly property string mainDetail: focusing && !store.cycle ? focusLeft + " min left" : focusing || onBreak ? left + " min left ›" : "›"
    readonly property string caption: (!active ? "Sit with me for..." : waiting ? "Waiting for you" : "Keeping you company")
                                      + (doneToday > 0 || active ? "\nFocus periods done today: " + doneToday : "")
    readonly property string cycleLabel: "Cycle: " + PetPrefs.work + " / " + PetPrefs.shortbreak

    // ---- starting and stopping ----
    function single(minutes) {                  // Pet.startFocus: the plain timer
        if (!(minutes > 0)) { stop(); return }
        quietStop()
        store.cycle = false
        store.singleMin = Math.min(minutes, 240)
        beginFocus()
    }
    function startCycle(work, shortB, longB, fromRound) {      // no arguments: the habit lengths
        quietStop()
        store.cycle = true
        store.workMin = work > 0 ? work : parseInt(PetPrefs.work)
        store.shortMin = shortB > 0 ? shortB : parseInt(PetPrefs.shortbreak)
        store.longMin = longB > 0 ? longB : parseInt(PetPrefs.longbreak)
        store.round = fromRound >= 1 && fromRound <= 4 ? fromRound : 1
        beginFocus()
        return status()
    }
    function stop() { quietStop(); return status() }
    function quietStop() {
        giveDnd()
        store.phase = ""
        store.until = 0
        store.cycle = false
        store.longBreak = false
    }
    function skip() {
        if (focusing && store.cycle) focusDone(false)
        else if (onBreak) breakDone(true)
        else if (waiting) beginFocus()
        else return "nothing to skip: " + status()
        return status()
    }
    function resume() { if (waiting) beginFocus() }

    function beginFocus() {
        now = nowMs()
        takeDnd()
        store.until = now + (store.cycle ? store.workMin : store.singleMin) * 60000
        store.longBreak = false
        store.phase = "focus"
    }
    function takeDnd() {
        if (!PetPrefs.focusDnd || Notif.dnd) return
        store.dndMine = true                    // first, so the pet never reads it as yours and dozes off
        Notif.setDnd(true)
    }
    function giveDnd() {
        if (!store.dndMine) return
        if (Notif.dnd) Notif.setDnd(false)
        store.dndMine = false
    }
    // turned off by hand in the middle: from then on it is the user's, to turn on or off
    Connections { target: Notif; function onDndChanged() { if (!Notif.dnd) store.dndMine = false } }

    function notify(title, body) {
        Sys.run("notify-send -a '" + Pet.name.replace(/[^\w .-]/g, "") + "' '" + title + "' '" + body + "'")
    }
    function fanfare() { if (!PetSound.play("tada")) Sys.sound("complete") }      // the pet's own fanfare when its sounds are on

    // completed: the time ran out (counted); otherwise skipped to the break (not counted)
    function focusDone(completed) {
        now = nowMs()
        giveDnd()                               // first: the notification and the sound must get through
        if (completed) {
            const today = dayKey(now)
            if (store.day !== today) { store.day = today; store.done = 0 }
            store.done = store.done + 1
            Pet.bump("focus", 3)                // lifetime count and bond (PetArc.qml)
        }
        if (!store.cycle) {
            store.phase = ""
            store.until = 0
            fanfare()
            notify("Focus time is up", "Stand up, stretch, look out of the window.")
            Pet.cheer()
            return
        }
        const long = store.round >= 4
        const m = long ? store.longMin : store.shortMin
        store.longBreak = long
        store.until = now + m * 60000
        store.phase = "break"
        if (completed) {
            fanfare()
            notify("Focus time is up", (long ? "A long break: " : "A break: ") + mins(m) + " min. Stand up, stretch, look out of the window.")
            Pet.cheer()
        }
        foc.breakBegan()
    }
    // skipped: you cut the break short, so the next round starts now and nothing is announced
    function breakDone(skipped) {
        now = nowMs()
        store.round = store.round >= 4 ? 1 : store.round + 1
        store.longBreak = false
        if (skipped || PetPrefs.carryOn) {
            beginFocus()
            if (!skipped) { fanfare(); notify("Break is over", "Round " + store.round + ": " + mins(store.workMin) + " min of focus.") }
            return
        }
        store.phase = "wait"
        store.until = 0
        fanfare()
        notify("Break is over", "Start round " + store.round + " from my menu when you are ready.")
    }

    // ---- the clock: runs only while a period does (and once more to hand Do Not Disturb back).
    // Not on start: the shell reads Do Not Disturb from its file a moment after a reload, and
    // turning it off before then would be undone when the file arrives.
    Timer {
        interval: foc.tickMs; repeat: true
        running: store.phase === "focus" || store.phase === "break" || (store.dndMine && store.phase !== "focus")
        onTriggered: {
            foc.now = foc.nowMs()
            if (store.dndMine && store.phase !== "focus") foc.giveDnd()
            if (store.phase === "focus" && foc.now >= store.until) foc.focusDone(true)
            else if (store.phase === "break" && foc.now >= store.until) foc.breakDone(false)
        }
    }
    // a single timer started before this file existed (Pet.qml kept it in pet.json): carry it on.
    // Once, a few seconds after start, when both files have surely been read.
    Timer {
        interval: 4000; running: true
        onTriggered: {
            if (Pet.focusUntilOld <= 0) return
            if (store.phase === "" && Pet.focusUntilOld > Date.now()) {
                store.cycle = false
                store.singleMin = (Pet.focusUntilOld - Date.now()) / 60000
                store.until = Pet.focusUntilOld
                store.phase = "focus"
                foc.now = foc.nowMs()
            }
            Pet.focusUntilOld = 0
        }
    }

    function status() {
        const s = !active ? "idle" : (focusing ? "focus" : onBreak ? (store.longBreak ? "longbreak" : "break") : "wait")
                  + (focusing || onBreak ? " " + left + " min left" : "")
                  + (store.cycle ? " round " + round + "/4" : " single")
        return s + ", done today " + doneToday + (store.dndMine ? ", dnd by the pet" : "")
               + ", habits " + PetPrefs.work + "/" + PetPrefs.shortbreak + "/" + PetPrefs.longbreak + (PetPrefs.carryOn ? " carry on" : " wait") + (PetPrefs.focusDnd ? " dnd" : "")
    }
}
