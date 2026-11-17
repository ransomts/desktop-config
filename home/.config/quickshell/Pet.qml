// The bar pet: a pixel-art tiger cub that lives in the empty stretches of the bar
// (drawn by PetSprite.qml, one per bar, shown on the focused screen). This is its
// mind, shared by every bar. Its mood is the first of these that holds:
//   asleep    sent to nap from its menu, Do Not Disturb is on, or it is night (bedtime to wake time: 23:00 to 06:00 unless changed in Habits)
//   remind    a reminder you set has come due (PetRemind.qml): it gets up even from sleep, runs to the
//             clock and sits there with a mark until you click it
//   meeting   a calendar event starts within the reminder lead (five minutes unless changed in Habits), or began this minute:
//             it runs to the clock and sits there with a clock over its head
//   focus     a focus timer is running (its menu, or `pet focus 25`): it sits still with the
//             minutes left beside it and pays no mind to notifications or the pointer
//   break     a break in a work and break cycle (PetFocus.qml): it plays, minutes left beside it
//   alert     a notification just arrived: it runs to the bell and waits with a "!",
//             for 25 seconds (a habit) or until the list is read, whichever comes first
//   tired     on battery below 15%: it lies down
//   dance     music is playing: it sits by the music pill and bobs
//   idle      otherwise: stands, blinks, sits, washes, lies down, wanders (mostly on mains power)
// While a notification is waiting the mark beside it says what kind: envelope (mail),
// calendar, speech bubble (chat apps), terminal (builds), "!!" (critical), "!" (anything else).
// It can be picked up and carried along the bar with the mouse. Now and then (mains power,
// idle) a moth flies along the bar and it gives chase. It is shy: while the screen or the
// camera is being captured it leaves the bar (menu: "Hide while sharing").
// On top of the mood it chases the pointer along the bar and pounces when the pointer
// rests near it, plays with a ball (scroll on it, or Play in its menu), eats when fed,
// cheers when the charger goes in, and thinks of a fish now and then if it has not
// been fed for five hours (nothing more than that: it never nags).
//
// In leaf, snow and petal season one drifts down onto the bar now and then and it goes to
// see about it. When you change desktop it sometimes turns to look.
// On a desktop with nothing open it comes down from the bar onto the wallpaper (Settings >
// "Desktop when empty"), twice the size, and follows the pointer across the screen.
// It lives on the focused screen's bar, or on one screen if told to stay ("Stay on this
// screen" in its menu). When the screen is unlocked it greets you.
// Click: pet it. Right-click: its menu (PetMenu.qml). Scroll: play.
//   qs ipc call pet on | off | status | pat | feed | play | nap true|false | chase true|false | name NAME
//   qs ipc call pet focus MINUTES (0 stops) | hat auto|none|santa|witch|party|cap|grad
//   qs ipc call pet calm true|false       no wandering, chasing, moths or thought bubbles
//   qs ipc call pet menu PAGE    open its menu on a page ("" tricks focus looks settings)
//   qs ipc call pet drop         a leaf (or snowflake, or petal, by the season) lands on the bar for it to find
//   qs ipc call pet friend none|cat|dog|frog|bird     a second animal to keep it company
//   qs ipc call pet roam true|false       whether it comes down to an empty desktop
//   qs ipc call pet desk true|false       pretend the desktop is empty (qs ipc call wallpaper grab PATH then shows it)
//   qs ipc call pet greet        what it does when the screen is unlocked
//   qs ipc call pet bug | shy true|false | animal cat|dog|frog|bird | trick "NAME"
//   animals: cat, dog, frog, bird (each behaves in its own way: see `kinds` below)
//   tricks: sit, lie down, spin, jump, beg, play dead, speak; the dog also fetches; the frog croaks and catches
//   qs ipc call pet coat tiger|white|regalia|tabby|panther (cat)  golden|chocolate|husky (dog)  pond|dart|tree (frog)  wren|cardinal|bluebird (bird)      (qs ipc call wallpaper weather rain|snow|auto tries the weather)
//   also: animal turtle (coats slider|box|sea; tricks hide, peek, spin, sit) and fox (red|arctic|silver; pounce, spin, sit, speak)
//   qs ipc call pet point X      pretend the pointer is at bar x (to try the chase); -1 ends it
// Kept in ~/.local/state/pet.json: shown or hidden, chase, its name, when it last ate.
// Sprites: assets/pet.png, drawn by assets/pet-build.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower

Singleton {
    id: pet

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/pet.json"
        blockLoading: true
        blockWrites: true           // a change made while an unfinished write was in flight used to be undone when it landed
        printErrors: false
        onAdapterUpdated: saveSoon.restart()
        JsonAdapter {
            id: store
            property bool enabled: true
            property bool chase: true
            property string name: "Cub"
            property double fedAt: 0            // ms since the epoch
            property string animal: "cat"       // cat | dog
            property string coat: "tiger"       // which sheet: assets/pet-ANIMAL-COAT.png
            property string friend: ""          // a second animal that keeps it company ("" for none)
            property string friendCoat: ""
            property bool napping: false        // sent to sleep from its menu (until woken); survives a reload
            property string hat: "auto"         // auto (by the date) | none | santa | witch | party | cap | grad
            property double focusUntil: 0       // no longer used: PetFocus.qml keeps the timer (it carries on one left here)
            property double bond: 0             // 0..100: how close it is to you
            property double bondAt: 0           // when that last changed (ms since the epoch)
            property double bondPeak: 0         // the highest it has been: time apart never takes it below 40% of this
            property string bondDay: ""         // the day bondToday is for (yyyy-MM-dd)
            property double bondToday: 0        // how much it has grown that day (at most bondPerDay)
            property bool calm: false           // no wandering, chasing, moths or thought bubbles
            property bool roam: true            // comes down onto the desktop when nothing is open on it
            property string pin: ""             // the screen it stays on ("" follows the focused screen)
            property bool shy: true             // out of sight while the screen or camera is being captured
        }
    }
    Timer { id: saveSoon; interval: 300; onTriggered: file.writeAdapter() }

    readonly property bool enabled: store.enabled
    readonly property bool chase: store.chase
    readonly property string name: store.name
    function setEnabled(on) { store.enabled = on }
    function setChase(on) { store.chase = on }
    // two animals, each with its own coats (sheets drawn by assets/pet-build)
    readonly property var coatsOf: {
        const all = { cat: ["tiger", "white", "regalia", "tabby", "panther"], dog: ["golden", "chocolate", "husky"],
                      frog: ["pond", "dart", "tree"], bird: ["wren", "cardinal", "bluebird"],
                      turtle: ["slider", "box", "sea"], fox: ["red", "arctic", "silver"] }
        if (PetSecrets.dragonOk) all.dragon = ["ember", "jade", "regal"]       // earned (PetSecrets.qml)
        return all
    }
    readonly property string animal: coatsOf[store.animal] ? store.animal : "cat"
    // ---- a friend: a second animal on the bar with it. It has its own nature (see `kinds`),
    // wanders by itself, comes along to the bell, the clock and the music, sleeps beside it,
    // and now and then goes over to say hello. Pats on one are for that one; food is for both;
    // the ball, tricks, the moth and the seasonal finds are the first animal's.
    readonly property string friend: coatsOf[store.friend] ? store.friend : ""
    readonly property string friendCoat: {
        if (friend === "") return ""
        const cs = coatsOf[friend]
        const c = cs.indexOf(store.friendCoat) >= 0 ? store.friendCoat : cs[0]
        return friend === animal && c === coat ? cs[(cs.indexOf(c) + 1) % cs.length] : c      // never its double
    }
    function setFriend(a) { store.friend = coatsOf[a] ? a : ""; return friend === "" ? "none" : friend }
    function nextFriend() { const all = [""].concat(Object.keys(coatsOf)); return setFriend(all[(all.indexOf(friend) + 1) % all.length]) }
    function nextFriendCoat() {
        if (friend === "") return ""
        const cs = coatsOf[friend]
        store.friendCoat = cs[(cs.indexOf(friendCoat) + 1) % cs.length]
        return friendCoat
    }
    property real x0: 0                         // where each of them is on the shown bar (so they can keep apart, or meet)
    property real x1: 0
    signal nuzzle()                             // the friend has come over: both are pleased

    function nextAnimal() { const all = Object.keys(coatsOf); return setAnimal(all[(all.indexOf(animal) + 1) % all.length]) }

    // What makes each animal itself (PetSprite.qml reads these as `kind`):
    //   cat   washes itself, pounces on the pointer, bats the ball about, hates rain (umbrella),
    //         purrs when petted, and only does a trick when it feels like it
    //   dog   sniffs about and wanders a lot, runs faster, fetches the ball and brings it back,
    //         barks when a notification comes in and at the moth, begs when the pointer rests
    //         by it, does not mind rain, always does its tricks and is always pleased
    //   frog  moves in hops, sits still for long stretches and croaks, catches the moth (and
    //         snaps at the pointer) with its tongue, loves rain, stays up at night, and sleeps
    //         through frost and snow
    //   bird  hops short distances and flies longer ones (in front of the pills, not behind),
    //         preens, sings in the morning, catches the moth on the wing, shelters from rain,
    //         and is shy: until the bond reaches 30 it flies off when the pointer comes close
    //   turtle very slow, wanders little and lies about a lot, never flees; when a notification
    //         comes in it pulls into its shell, stays there a while, peeks out and then plods
    //         over to the bell; into the shell too when picked up or startled (`shell`)
    //   fox   quick, pounces nose first at the pointer, stays up at night and is not sleepy in
    //         the evening (`nocturnal`; it does not sleep by day instead), curls up out of the rain,
    //         and steals the ball: it grabs it and runs off with it instead of batting it (`steals`)
    // pace: speed factor.  roam / sits / lazes / fidgets: chances in its idle life.
    // idleA, idleB: the two frames of its fidget (washing, sniffing, croaking).
    readonly property var kinds: ({
        cat:  { speak: "meow!", food: Icons.fish, pace: 1.0, hops: false, roam: 0.2, sits: 0.25, lazes: 0.15, fidgets: 0.12, idleA: 8, idleB: 4,
                pounces: true, tongue: false, fetches: false, barks: false, purrs: true, rain: "umbrella", nocturnal: false, hibernates: false,
                obeys: 0.7, pleased: 0.4, tricks: ["sit", "lie down", "spin", "jump", "beg", "play dead", "speak"] },
        dog:  { speak: "woof!", food: Icons.bone, pace: 1.3, hops: false, roam: 0.35, sits: 0.2, lazes: 0.05, fidgets: 0.25, idleA: 10, idleB: 0,
                pounces: false, tongue: false, fetches: true, barks: true, purrs: false, rain: "fine", nocturnal: false, hibernates: false,
                obeys: 1.0, pleased: 1.0, tricks: ["sit", "lie down", "spin", "jump", "beg", "play dead", "speak", "fetch"] },
        frog: { speak: "ribbit!", food: Icons.bug, pace: 1.0, hops: true, roam: 0.08, sits: 0.55, lazes: 0.05, fidgets: 0.2, idleA: 8, idleB: 4,
                pounces: false, tongue: true, fetches: false, barks: false, purrs: false, rain: "loves", nocturnal: true, hibernates: true,
                obeys: 0.85, pleased: 0.5, tricks: ["sit", "jump", "spin", "croak", "catch", "play dead"] },
        bird: { speak: "tweet!", food: Icons.bug, pace: 1.0, hops: true, flies: true, flees: true, sings: true,
                roam: 0.3, sits: 0.2, lazes: 0.1, fidgets: 0.25, idleA: 8, idleB: 0,
                pounces: false, tongue: false, fetches: false, barks: false, purrs: false, rain: "shelter", nocturnal: false, hibernates: false,
                obeys: 0.8, pleased: 0.6, tricks: ["sing", "fly", "hop", "spin", "peck"] },
        turtle: { speak: "hi!", food: Icons.leaf, pace: 0.4, hops: false, shell: true, roam: 0.06, sits: 0.25, lazes: 0.35, fidgets: 0.1, idleA: 8, idleB: 0,
                pounces: false, tongue: false, fetches: false, barks: false, purrs: false, rain: "fine", nocturnal: false, hibernates: true,
                obeys: 0.75, pleased: 0.5, tricks: ["hide", "peek", "spin", "sit"] },
        // dragon: walks short ways and flies longer ones, hoards the ball like the fox, and
        //         breathes fire when asked; it is not in Looks until it has been earned (PetSecrets.qml)
        dragon: { speak: "rawr!", food: Icons.fish, pace: 1.1, hops: false, flies: true, steals: true, roam: 0.25, sits: 0.25, lazes: 0.15, fidgets: 0.1, idleA: 4, idleB: 1,
                pounces: true, tongue: false, fetches: false, barks: false, purrs: false, rain: "fine", nocturnal: false, hibernates: false,
                obeys: 0.8, pleased: 0.6, tricks: ["breathe fire", "fly", "spin", "sit", "speak", "play dead"] },
        fox:  { speak: "yip!", food: Icons.bone, pace: 1.4, hops: false, steals: true, roam: 0.3, sits: 0.2, lazes: 0.1, fidgets: 0.2, idleA: 8, idleB: 10,
                pounces: true, tongue: false, fetches: false, barks: false, purrs: false, rain: "shelter", nocturnal: true, hibernates: false,
                obeys: 0.7, pleased: 0.5, tricks: ["pounce", "spin", "sit", "speak"] }
    })
    readonly property var kind: kinds[animal]
    readonly property bool hibernating: kind.hibernates && (weather === "snow" || weather === "cold")
    readonly property var coats: coatsOf[animal]
    readonly property string coat: coats.indexOf(store.coat) >= 0 ? store.coat : coats[0]
    function setAnimal(a) {
        if (!coatsOf[a]) return animal
        store.animal = a
        if (coatsOf[a].indexOf(store.coat) < 0) store.coat = coatsOf[a][0]
        return animal
    }
    function setCoat(c) {           // a coat name also picks its animal
        for (const a in coatsOf) if (coatsOf[a].indexOf(c) >= 0) { store.animal = a; store.coat = c }
        return coat
    }
    // ---- hats: by the date, or one chosen from its menu ----
    readonly property var hats: ["auto", "none", "santa", "witch", "party", "cap", "grad"].concat(PetArc.hats)      // and the ones earned over time
    readonly property string hatAuto: {
        const d = WallState.seasonDay, md = (d.getMonth() + 1) * 100 + d.getDate()
        if (WallState.game !== null) return "cap"               // a Clemson game day
        if (md >= 1201 && md <= 1226) return "santa"
        if (md >= 1024 && md <= 1031) return "witch"
        if (md === 101) return "party"
        if (PetArc.anniversary) return "party"                 // the day you met, a year on (PetArc.qml)
        return ""
    }
    readonly property string hat: store.hat === "auto" ? hatAuto : hats.indexOf(store.hat) > 1 ? store.hat : ""
    readonly property string hatChoice: hats.indexOf(store.hat) >= 0 ? store.hat : "auto"
    function setHat(h) { if (hats.indexOf(h) >= 0) store.hat = h; return hatChoice }
    function nextHat() { return setHat(hats[(hats.indexOf(hatChoice) + 1) % hats.length]) }

    // ---- focus timer: it sits with you and counts the minutes down; when they are up
    // it cheers, a sound plays and a notification says so ----
    readonly property bool focusing: PetFocus.focusing             // the timer and cycles live in PetFocus.qml
    readonly property int focusLeft: PetFocus.focusLeft
    property alias focusUntilOld: store.focusUntil
    signal cheer()
    function startFocus(minutes) { PetFocus.single(minutes) }

    // ---- which screen: the focused one, or one it has been told to stay on ----
    // A screen is known by model and serial number: the connector names (DP-7, DP-9) change
    // every time the dock is attached. If the pinned screen is not connected it follows focus.
    // By Hyprland's description of the monitor (maker, model and serial as one string): the
    // laptop panel reports no serial at all, and model|serial then fell back to the connector
    // name, so a pin quietly came undone at the next dock attach.
    function screenKey(s) {
        const m = Hyprland.monitors.values.find(mon => mon.name === s.name)
        const d = m ? (m.description || (m.lastIpcObject || {}).description || "") : ""
        return d !== "" ? d : (s.model || "") + "|" + (s.serialNumber || s.name)
    }
    readonly property string pin: store.pin
    readonly property bool pinOk: store.pin !== "" && Quickshell.screens.some(s => screenKey(s) === store.pin)
    function setPin(key) { store.pin = key }
    // `hold`: a screen it stays on for the moment whatever has the focus. Its menu down on an
    // empty desktop sets this (Wallpaper.qml): closing that menu hands the keyboard back to a
    // window on another screen, and the pet used to follow it there until the mouse next moved.
    property string hold: ""
    function showsOn(key, focused) { return pinOk ? key === store.pin : hold !== "" ? key === hold : focused }

    // ---- bond: grows when you look after it, fades slowly (2 a day) when you do not, down to 40% of its highest and no further ----
    // pat +1, feed +4 (+1 if it was not hungry), ball +3, a trick done +2, a focus timer
    // sat through +3, a greeting +1. The closer it is, the more readily it does tricks
    // and the more often it is pleased. Shown as five hearts in its tooltip and menu.
    // It grows by at most bondPerDay in one day, so closeness comes from days of care and not
    // from one long sitting: a heart takes four days, the dragon (80) two weeks. Care past
    // the day's limit still counts as care (lifetime counts, and it holds off the fading).
    property real bondPerDay: 6
    readonly property real bond: store.bond
    readonly property string hearts: { const n = Math.round(Math.min(100, bond) / 20); return ("♥".repeat(n) + "♡".repeat(5 - n)).split("").join(" ") }      // spaced: the font's heart is wider than its cell
    property var bumped: ({})
    readonly property var bumpGap: ({ pat: 20, play: 30, trick: 20, greet: 600 })      // seconds before the same thing counts again
    function bump(what, n) {
        const t = Date.now()
        if (bumped[what] && t - bumped[what] < (bumpGap[what] || 0) * 1000) return
        bumped[what] = t
        const day = Qt.formatDate(new Date(), "yyyy-MM-dd")
        if (store.bondDay !== day) { store.bondDay = day; store.bondToday = 0 }
        const gain = Math.max(0, Math.min(n, bondPerDay - store.bondToday))
        store.bondToday = store.bondToday + gain
        store.bond = Math.min(100, store.bond + gain)
        store.bondAt = t
        if (store.bond > store.bondPeak) store.bondPeak = store.bond
        PetArc.note(what, store.bond)               // lifetime counts and milestones (PetArc.qml)
    }
    Timer {
        interval: 3600000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            if (store.bondAt <= 0) return
            const days = Math.floor((Date.now() - store.bondAt) / 86400000)
            if (days < 1) return
            // it fades with time apart, but never below 40% of the closest you have been
            const peak = Math.max(store.bondPeak, store.bond)
            if (peak > store.bondPeak) store.bondPeak = peak
            store.bond = Math.max(Math.min(store.bond, 0.4 * peak), store.bond - 2 * days)
            store.bondAt = Date.now()
        }
    }
    // start over from n (qs ipc call pet bond 0): the peak and today's tally go with it; what it has unlocked stays
    function setBond(n) {
        store.bond = Math.max(0, Math.min(100, n)); store.bondPeak = store.bond
        store.bondAt = Date.now(); store.bondToday = 0
        return status()
    }
    readonly property real obeys: Math.min(1, kind.obeys + bond / 250)
    readonly property real pleased: Math.min(1, kind.pleased + bond / 200)
    function petIt(who) { bump("pat", 1); pat(who === undefined ? -1 : who) }      // who: 0 it, 1 its friend, nothing: both
    function playWith() { bump("play", 3); play() }

    // ---- the desktop: with no windows open on a desktop it leaves the bar for the wallpaper,
    // where it is drawn twice the size and has the whole width (Wallpaper.qml draws it there) ----
    readonly property bool roam: store.roam
    function setRoam(on) { store.roam = on }
    property bool deskDemo: false               // behave as if the desktop were empty (to look at it from a script)

    readonly property bool calm: store.calm
    function setCalm(on) { store.calm = on }

    property string menuPage: ""                // the page its menu opens on (set by `pet menu PAGE`, cleared when it closes)
    signal drop()                               // something of the season lands on the bar (a leaf, a snowflake, a petal)
    signal greet()                              // the screen was unlocked (sent by ~/.local/bin/lock-screen)

    // ---- where it was on each screen's bar, kept across a reload of the shell ----
    PersistentProperties { id: keep; reloadableId: "petKeep"; property string spots: "{}" }
    function spot(screen) { try { const v = JSON.parse(keep.spots)[screen]; return v === undefined ? -1 : v } catch (e) { return -1 } }
    function setSpot(screen, x) {
        let s = {}
        try { s = JSON.parse(keep.spots) } catch (e) {}
        s[screen] = Math.round(x)
        keep.spots = JSON.stringify(s)
    }

    // tricks, from its menu or `qs ipc call pet trick NAME`
    readonly property var tricks: kind.tricks
    signal trick(string name)
    function nextCoat() {
        if (PetSecrets.costume !== "") { PetSecrets.plain(); return coat }      // dressed up for the day: the first step takes that off
        return setCoat(coats[(coats.indexOf(coat) + 1) % coats.length])
    }
    function setName(n) { n = n.trim().slice(0, 24); if (n !== "") store.name = n }

    // ---- what it reacts to ----
    function mins(hm) { const p = hm.split(":"); return parseInt(p[0]) * 60 + parseInt(p[1]) }
    readonly property int hour: parseInt(Sys.nowHM.split(":")[0])
    readonly property bool night: PetPrefs.asleepAt(mins(Sys.nowHM))        // bedtime to wake time (PetPrefs.qml)
    readonly property bool musicOn: Sys.player !== null && Sys.player.isPlaying
    readonly property int toNext: Sys.nextEvent ? mins(Sys.nextEvent.start) - mins(Sys.nowHM) : 999
    readonly property bool meetingSoon: (toNext >= 0 && toNext <= PetPrefs.meetingLead)
                                        || (PetPrefs.meetingLead >= 0 && Sys.currentEvent !== null && mins(Sys.nowHM) - mins(Sys.currentEvent.start) < 1)
    readonly property bool lowBattery: UPower.onBattery && UPower.displayDevice.percentage < 0.15
    readonly property bool hungry: { Sys.nowHM; return Date.now() - store.fedAt > PetPrefs.hungryAfterMs }

    // a notification that just came in (not the unread ones found at start-up)
    property bool alerting: false
    property int seenCount: -1
    Timer { id: ready; interval: 4000; running: true; onTriggered: pet.seenCount = Notif.unseen }
    Timer { id: alertOff; interval: PetPrefs.bellWaitMs; onTriggered: pet.alerting = false }
    Connections {
        target: Notif
        function onUnseenChanged() {
            if (pet.seenCount < 0) return
            if (Notif.unseen > pet.seenCount) { pet.alerting = true; alertOff.restart() }
            if (Notif.unseen === 0) pet.alerting = false
            pet.seenCount = Notif.unseen
        }
    }

    // the weather outside (WallState's open-meteo feed, kept running for the pet): in rain
    // it sits under an umbrella and stays put; in snow or frost it curls up and thinks of
    // snowflakes; in heat (32 C and up) it sprawls and thinks of the sun
    readonly property string weather: WallState.wxKind
    Binding { target: WallState; property: "wxWanted"; value: pet.enabled }

    property alias napping: store.napping
    // shy: it leaves the bar while something records video (a shared screen, a camera)
    readonly property bool shy: store.shy
    function setShy(on) { store.shy = on }
    readonly property bool hiding: store.shy && Sys.videoInUse
    readonly property bool sleepy: PetPrefs.sleepyAt(mins(Sys.nowHM))      // evenings: it lies down more
    // what the notification it is waiting on is about, from the newest one's app and title
    readonly property string alertGlyph: {
        const n = Notif.history.length > 0 ? Notif.history[0] : null
        if (!n) return "!"
        const s = ((n.app || "") + " " + (n.summary || "")).toLowerCase()
        if (n.critical) return "!!"
        if (/mail|mu4e|outlook|thunderbird|betterbird|evolution/.test(s)) return Icons.envelope
        if (/calendar|meeting|reminder|event/.test(s)) return Icons.calendar
        if (/discord|slack|element|zoom|teams|signal|whatsapp|matrix/.test(s)) return Icons.chat
        if (/ghostty|terminal|build|finished|done|exit/.test(s)) return Icons.terminal
        return "!"
    }
    signal bug()                                // a moth flies along the bar (also happens by itself now and then)
    readonly property string mood: (napping || PetFocus.userDnd || (night && !kind.nocturnal) || hibernating) && !PetRemind.ringing ? "asleep" : PetRemind.ringing ? "remind" : meetingSoon ? "meeting" : focusing ? "focus" : alerting ? "alert" : PetFocus.onBreak ? "break"
                                   : lowBattery ? "tired" : musicOn ? "dance" : "idle"
    readonly property string doing: mood === "asleep" ? (napping ? "napping" : PetFocus.userDnd ? "asleep while Do Not Disturb is on" : hibernating ? "asleep until it warms up" : "asleep for the night")
        : mood === "remind" ? PetRemind.doing      // a reminder you set (PetRemind.qml)
        : mood === "meeting" ? "reminding you: " + (Sys.nextEvent && toNext <= PetPrefs.meetingLead ? Sys.nextEvent.title + " at " + Sys.nextEvent.start
                                                    : Sys.currentEvent ? Sys.currentEvent.title + " has started" : "an event")
        : mood === "focus" ? "keeping you company: " + focusLeft + " min of focus left"
        : mood === "break" ? "on a break with you: " + PetFocus.breakLeft + " min left"
        : mood === "alert" ? "waiting by the bell: a notification came in"
        : mood === "tired" ? "worn out: the battery is low"
        : (mood === "dance" ? "dancing" : hungry ? "about, and peckish" : "about")
          + (weather === "rain" ? (kind.rain === "umbrella" ? ", under an umbrella: it is raining" : kind.rain === "loves" ? ", delighted: it is raining" : "") : weather === "snow" ? ", keeping warm: it is snowing"
             : weather === "cold" ? ", keeping warm: it is freezing out" : weather === "hot" ? ", sprawled out: it is hot out" : "")

    // ---- things done to it (every bar's sprite hears these; the shown one acts) ----
    signal pat(int who)
    signal feed()
    signal play()
    function giveFood() { bump("feed", hungry ? 4 : 1); store.fedAt = Date.now(); feed() }

    property real pointDemo: -1                 // a pretend pointer position, for trying the chase from a script
    property string where: ""                   // the shown sprite's position, for `pet status`
    function status() { return (enabled ? "on" : "off") + " " + name + " mood=" + mood + (hungry ? " hungry" : "") + (calm ? " calm" : "") + " bond=" + Math.round(bond) + " " + animal + " coat=" + coat + (friend !== "" ? " friend=" + friend + "/" + friendCoat + "@" + Math.round(x1) : "") + " weather=" + weather + " " + where }
}
