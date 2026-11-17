// The pet's secrets: things it does that no menu mentions. This file knows which exist,
// which have been found (the Journal shows "Secrets 3 of 17", never what the rest are), the
// calendar ones, and the rare ones that come from outside (the sky, a Clemson touchdown).
// What a sprite does about them is in PetAntics.qml. SPOILERS below.
//
//   By the date
//     anniversary  the day you met, a year on: party hat (PetArc.qml, Pet.hatAuto)
//     ghost        31 October: a ghost of itself for the day
//     santa        1 to 26 December: the red hat (Pet.hatAuto)
//     shadow       any Friday the 13th: a black coat for the day (the cat: its panther coat)
//     fool         1 April: it has swapped bodies with its friend, or become another animal,
//                  until you pet it
//     A costume can be taken off for the day by stepping "Coat" in Looks.
//   Things you do
//     dizzy        ten pats inside four seconds: it spins, and ends up on its back
//     bell         carry it onto the bell pill and let go: it rings the bell
//     clock        carry it onto the clock and let go: it sits on the clock, which sinks a little
//     doze         leave the pointer resting on it for a minute: it goes to sleep there
//     clemson      name it Tiger, Clemson, Dabo, Howard, Tillman, Death Valley ...: it leaves
//                  orange paw prints behind it as it walks
//     species      name it after its own kind ("Cat" for a cat): it turns its back, and now
//                  and then answers a pat with "hmph"
//   Rare
//     shiny        about one day in 180: a golden coat for the day
//     star         some evenings (dark theme, 19:00 to 06:00, mains power) a shooting star
//                  crosses the wallpaper and it sits to watch
//     ufo          very rarely something else crosses the wallpaper, and it ducks until it is gone
//     touchdown    on a Clemson game day, when Clemson's score goes up by six or more
//                  (~/.local/bin/pet-score, asked once a minute during the game only)
//   Earned
//     push         the cat, once the bond is 60 or more: now and then it knocks the clock
//                  off the bar and watches it come back
//     dragon       the bond reaches 80: a small dragon appears under Looks > Animal, for good
//
//   qs ipc call pet secrets            how many are found, and their names
//   qs ipc call pet secret NAME        try one without it counting: star ufo touchdown dizzy doze
//                                      bell clock push sulk ghost shadow shiny fool dragon none
//   qs ipc call pet secretday 2027-04-01     pretend it is that day ("" ends it)
// Kept in ~/.local/state/pet-secrets.json.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Singleton {
    id: sec

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/pet-secrets.json"
        blockLoading: true
        blockWrites: true
        printErrors: false
        onAdapterUpdated: saveSoon.restart()
        JsonAdapter {
            id: store
            property string found: ""           // ids, space separated
            property string foolYear: ""        // the year whose 1 April joke has been seen through
            property string plainDay: ""        // the day its costume was taken off (yyyy-MM-dd)
        }
    }
    Timer { id: saveSoon; interval: 300; onTriggered: file.writeAdapter() }

    // Pet.qml reads `dragonOk` in a binding, so nothing here reaches back into Pet until a
    // few seconds after start (as PetArc.qml does).
    property bool ready: false
    Timer { interval: 5000; running: true; onTriggered: { sec.ready = true; sec.daily() } }

    readonly property var all: [
        { id: "anniversary", title: "Many happy returns" },
        { id: "ghost",       title: "A ghost on the bar" },
        { id: "santa",       title: "The red hat" },
        { id: "shadow",      title: "Friday the 13th" },
        { id: "fool",        title: "Not quite itself" },
        { id: "dizzy",       title: "A dizzy spell" },
        { id: "bell",        title: "Ding" },
        { id: "clock",       title: "A heavy sitter" },
        { id: "doze",        title: "A warm spot" },
        { id: "clemson",     title: "Paw prints" },
        { id: "species",     title: "What's in a name" },
        { id: "shiny",       title: "A rare shine" },
        { id: "star",        title: "A wish" },
        { id: "ufo",         title: "Not from around here" },
        { id: "touchdown",   title: "Touchdown" },
        { id: "push",        title: "Gravity, tested" },
        { id: "dragon",      title: "Something hatched", say: "An egg hatched: there is a small dragon in Looks" }
    ]
    function has(id) { return (" " + store.found + " ").indexOf(" " + id + " ") >= 0 }
    readonly property int count: store.found.trim() === "" ? 0 : store.found.trim().split(" ").length
    readonly property string summary: count + " of " + all.length
    property double quietUntil: 0           // a secret tried from a script does not count as found
    function found(id) {
        if (!ready || has(id) || Date.now() < quietUntil || pretending) return
        const s = all.find(x => x.id === id)
        if (!s || !Pet.enabled) return
        store.found = (store.found + " " + id).trim()
        PetArc.write(s.say || "Found a secret: " + s.title)
        PetArc.cheer("★")
    }
    function report() {
        return summary + " secrets found" + all.filter(s => has(s.id)).map(s => "\n  " + s.title).join("")
    }

    // ---- the day (once a minute with the bar clock; no timer of its own) ----
    property string dayDemo: ""             // yyyy-MM-dd to pretend
    property bool pretending: false         // ... from a script: nothing found on a pretended day counts
    function pretend(day) { pretending = day !== ""; dayDemo = day; return dayStr + (costume !== "" ? " " + costume : "") + (fool ? " fool" : "") }
    readonly property string dayStr: { Sys.nowHM; return dayDemo !== "" ? dayDemo : Qt.formatDate(new Date(), "yyyy-MM-dd") }
    readonly property int md: parseInt(dayStr.slice(5, 7)) * 100 + parseInt(dayStr.slice(8, 10))
    readonly property int weekday: new Date(dayStr + "T12:00:00").getDay()
    onDayStrChanged: Qt.callLater(daily)     // once the costume for the new day has been worked out
    function hash(s) { let h = 7; for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 1000003; return h }

    // ---- costumes: another sheet for the day (assets/pet-costumes-build draws one per animal) ----
    property string costumeDemo: ""         // ghost | shadow | shiny | none
    readonly property string costume: {
        if (costumeDemo !== "") return costumeDemo === "none" ? "" : costumeDemo
        if (store.plainDay === dayStr) return ""
        if (md === 1031) return "ghost"
        if (md % 100 === 13 && weekday === 5) return "shadow"
        if (hash(dayStr) % 180 === 7) return "shiny"
        return ""
    }
    function plain() { if (costumeDemo !== "") costumeDemo = ""; else store.plainDay = dayStr }

    // ---- 1 April ----
    property bool foolDemo: false
    readonly property bool fool: foolDemo || (md === 401 && store.foolYear !== dayStr.slice(0, 4))
    function unfool() {
        if (!fool) return
        if (foolDemo) foolDemo = false
        else { store.foolYear = dayStr.slice(0, 4); found("fool") }
    }

    // what sprite `who` (0 the pet, 1 its friend) is drawn as, given what they really are
    function look(who, animal, coat, friend, friendCoat) {
        let a = who === 0 ? animal : friend, c = who === 0 ? coat : friendCoat
        if (fool) {
            if (friend !== "") { a = who === 0 ? friend : animal; c = who === 0 ? friendCoat : coat }
            else if (who === 0) {
                const names = Object.keys(Pet.coatsOf)
                a = names[(names.indexOf(animal) + 1) % names.length]
                c = Pet.coatsOf[a][0]
            }
        }
        // (asked while the animal has changed and its coat has not yet: never a sheet that does not exist)
        if (a !== "" && Pet.coatsOf[a] && Pet.coatsOf[a].indexOf(c) < 0) c = Pet.coatsOf[a][0]
        if (a !== "" && costume !== "") c = costume === "shadow" && a === "cat" ? "panther" : costume
        return { animal: a, coat: c }
    }

    // ---- names ----
    readonly property string lowName: ready ? Pet.name.trim().toLowerCase() : ""
    readonly property bool clemson: /^(the )?(tiger|tigers|tiger cub|clemson|dabo|howard|tillman|death valley)$/.test(lowName)
    readonly property bool offended: ready && lowName !== "" && lowName === Pet.animal

    // ---- earned ----
    property bool dragonDemo: false
    readonly property bool dragonOk: dragonDemo || has("dragon")
    Connections {
        target: sec.ready ? Pet : null
        function onBondChanged() { if (Pet.bond >= 80) sec.found("dragon") }
        function onEnabledChanged() { sec.daily() }
    }
    function daily() {
        if (!ready || !Pet.enabled) return
        if (costume !== "" && costumeDemo === "") found(costume)
        if (dayDemo === "" && Pet.hatChoice === "auto" && Pet.hat === "santa") found("santa")
        if (dayDemo === "" && PetArc.anniversary) found("anniversary")
        if (Pet.bond >= 80) found("dragon")
    }

    // ---- the sky: something crosses the wallpaper (PetSky.qml draws it from `skyT`) ----
    property string sky: ""                 // "" | star | ufo
    property real skyT: 0                   // 0..1 across
    property real skyY: 0.2                 // how far down the screen, 0..1
    property bool skyLtr: true
    function startSky(kind) {
        if (sky !== "" || (kind !== "star" && kind !== "ufo")) return
        skyLtr = Math.random() < 0.5
        skyY = 0.08 + Math.random() * 0.22
        skyT = 0
        sky = kind
        skyStep.start()
    }
    Timer {     // twenty steps a second, as the pet walks
        id: skyStep; interval: 50; repeat: true
        onTriggered: {
            sec.skyT = Math.min(1, sec.skyT + interval / (sec.sky === "ufo" ? 9000 : 1300))
            if (sec.skyT >= 1) { stop(); sec.sky = "" }
        }
    }
    Timer {     // every ten minutes a small chance, on mains power, with the pet up and about
        interval: 600000; repeat: true
        running: sec.ready && Pet.enabled && !Pet.calm && !UPower.onBattery
        onTriggered: {
            if (Pet.mood === "asleep" || Pet.hiding) return
            const r = Math.random()
            if (r < 0.1 && Theme.dark && (Pet.hour >= 19 || Pet.hour < 6)) sec.startSky("star")
            else if (r > 0.992) sec.startSky("ufo")
        }
    }

    // ---- touchdown: Clemson's score, asked once a minute while a game is on ----
    signal touchdown()
    property int us: -1                     // Clemson's score when last seen (-1: no game under way)
    property string gameOver: ""            // the day whose game has ended
    readonly property bool gameWindow: {
        if (!ready || WallState.game === null || gameOver === dayStr || dayDemo !== "") return false
        const t = WallState.game.time || ""
        if (t === "") return Pet.hour >= 11
        const now = Pet.mins(Sys.nowHM), kick = Pet.mins(t)
        return now >= kick - 2 && now <= kick + 330
    }
    Timer { interval: 60000; repeat: true; triggeredOnStart: true; running: sec.gameWindow && Pet.enabled; onTriggered: scoreGet.running = true }
    Process {
        id: scoreGet
        command: Sys.clean.concat([Sys.bin + "pet-score"])
        stdout: StdioCollector { onStreamFinished: sec.score(text) }
    }
    function score(text) {
        let g = null
        try { g = JSON.parse(text) } catch (e) { return }
        if (!g || g.state === "pre") { us = -1; return }
        if (g.state === "post") { us = -1; gameOver = dayStr; return }
        if (us >= 0 && g.us - us >= 6) touchdown()
        us = g.us
    }

    // ---- trying one from a script (`pet secret NAME`): nothing is recorded ----
    signal act(string name)                 // the ones a sprite does by itself (PetAntics.qml)
    function demo(name) {
        quietUntil = Date.now() + 20000
        if (name === "star" || name === "ufo") { startSky(name); return sky === name ? name : "the sky is busy" }
        if (name === "touchdown") { touchdown(); return name }
        if (name === "ghost" || name === "shadow" || name === "shiny") { costumeDemo = name; return name }
        if (name === "none") { costumeDemo = ""; foolDemo = false; dragonDemo = false; return "back to normal" }
        if (name === "fool") { foolDemo = !foolDemo; return foolDemo ? "fooled" : "itself again" }
        if (name === "dragon") { dragonDemo = !dragonDemo; return dragonDemo ? "the dragon is in Looks" : (dragonOk ? "it has been earned: it stays" : "gone again") }
        if (["dizzy", "doze", "bell", "clock", "push", "sulk", "fire"].indexOf(name) >= 0) { act(name); return name }
        return "no such secret"
    }
}
