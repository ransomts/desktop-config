// The bar pet on the lock screen, asleep beside the clock. LockView.qml loads this through a
// Loader by its file name, so a mistake in here leaves an empty space, never a broken lock.
//
// It is drawn from the pet's saved state alone: ~/.local/state/pet.json (animal, coat, hat,
// name, on or off, napping) and pet-arc.json (the day it came, for the anniversary). The main shell's singletons
// are not used on purpose: the lock screen is a separate Quickshell instance, and Pet would
// write its state from a second process, Notif would try to be a second notification daemon.
// Nothing here writes anything, takes focus or takes the mouse.
//
// Like the rest of the lock screen nothing animates: the frame changes only when something
// happens (no timers):
//   locked           asleep, "z"
//   first key        sits up, and stays up (not if it was sent to nap from its menu)
//   an event is near sits up with a "!" when the next calendar event is as close as its
//                    "meeting" habit says (pet-habits.json: 5 minutes unless changed, never
//                    if "off"); LockView passes the minutes from LockNext.qml
//   checking         stands, ears up
//   wrong password   the first time it turns to look at you, puzzled ("?"), and shakes its head
//                    with the field; the second time it is on its feet telling the stranger
//                    off ("hiss!", "grr!" ...; the turtle is in its shell); sits again when the
//                    field calms down. (A third miss hands over to the standard lock screen.)
//   unlocking        paws up and a heart, for the half second lockscreen.qml holds the lock
//                    after a right password (`ctl.unlocking`)
// It wears the day's costume, if there is one (the rule is PetSecrets.qml's, repeated here).
// No pet.json, a broken one, or the pet switched off: nothing is shown.
import QtQuick
import Quickshell
import Quickshell.Io
import "assets/pet-anchors.js" as Heads

Item {
    id: pet
    property var ctl: null                  // the lock's ShellRoot: typed, phase, dark
    property Item around: null              // LockView's column (clock, date, field), a sibling of the Loader

    readonly property int k: 5              // screen pixels per sprite pixel (16 x 5 = 80)
    readonly property int box: 16 * k
    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")

    // ---- what it is, from its files ----
    property var store: null                // pet.json, parsed; null until read (or if missing or broken)
    FileView {
        path: pet.stateDir + "/pet.json"
        printErrors: false
        onLoaded: { try { const s = JSON.parse(text()); pet.store = s && typeof s === "object" ? s : null } catch (e) { pet.store = null } }
        onLoadFailed: pet.store = null
    }
    FileView {
        path: pet.stateDir + "/pet-arc.json"
        printErrors: false
        onLoaded: {
            try {
                const arc = JSON.parse(text()), a = String(arc.adopted || ""), t = Qt.formatDate(new Date(), "yyyy-MM-dd")
                pet.anniversary = a.length === 10 && a !== t && a.slice(5) === t.slice(5)     // as PetArc.anniversary
            } catch (e) { pet.anniversary = false }
        }
    }
    // ---- a costume for the day: as PetSecrets.costume (ghost on 31 October, a black coat on a
    // Friday the 13th, gold about one day in 180), unless it was taken off today ----
    property string plainDay: ""
    FileView {
        path: pet.stateDir + "/pet-secrets.json"
        printErrors: false
        onLoaded: { try { pet.plainDay = String(JSON.parse(text()).plainDay || "") } catch (e) { pet.plainDay = "" } }
    }
    readonly property string costume: {
        const d = new Date(), day = Qt.formatDate(d, "yyyy-MM-dd")
        if (plainDay === day) return ""
        if (d.getMonth() === 9 && d.getDate() === 31) return "ghost"
        if (d.getDate() === 13 && d.getDay() === 5) return "shadow"
        let h = 7
        for (let i = 0; i < day.length; i++) h = (h * 31 + day.charCodeAt(i)) % 1000003
        return h % 180 === 7 ? "shiny" : ""
    }
    function word(v, fallback) { return typeof v === "string" && /^[a-z]+$/.test(v) ? v : fallback }   // only plain names go into a file path
    readonly property string animal: store ? word(store.animal, "cat") : ""
    readonly property string coat: store ? word(store.coat, "tiger") : ""
    // one binding for the whole path, so it is never built from a new animal and an old coat
    readonly property url sheetUrl: store && store.enabled !== false ? Qt.resolvedUrl("assets/pet-" + word(store.animal, "cat") + "-"
        + (costume === "" ? word(store.coat, "tiger") : costume === "shadow" && word(store.animal, "cat") === "cat" ? "panther" : costume) + ".png") : ""
    readonly property string name: store && typeof store.name === "string" ? store.name.slice(0, 24) : ""
    readonly property bool shown: store !== null && store.enabled !== false && animal !== ""
    readonly property bool napping: store !== null && store.napping === true

    // The hat: one chosen in its menu, or on "auto" the hats that go by the date (as in Pet.qml,
    // without the game-day cap, which needs the main shell's game schedule).
    readonly property string hat: {
        const h = store ? word(store.hat, "auto") : ""
        if (h === "auto") {
            const d = new Date(), md = (d.getMonth() + 1) * 100 + d.getDate()
            if (md >= 1201 && md <= 1226) return "santa"
            if (md >= 1024 && md <= 1031) return "witch"
            if (md === 101) return "party"
            return anniversary ? "party" : ""
        }
        return Heads.hats[h] ? h : ""
    }
    property bool anniversary: false        // the day you met, a year on

    // ---- what it is doing: frames in the sheet (the list at the top of PetSprite.qml) ----
    readonly property string phase: ctl && typeof ctl.phase === "string" ? ctl.phase : "idle"
    readonly property bool unlocking: ctl ? ctl.unlocking === true : false
    property bool awake: false              // set by the first key, and kept
    property int toNext: 0                  // minutes to the next calendar event (0: none); set by LockView
    property int lead: 5                    // its "meeting" habit, in minutes (-1: off), as PetPrefs.meetingLead
    FileView {
        path: pet.stateDir + "/pet-habits.json"
        printErrors: false
        onLoaded: {
            try {
                const m = String(JSON.parse(text()).meeting || "5"), n = parseInt(m)
                pet.lead = m === "off" || m === "0" || m === "none" ? -1 : n >= 1 && n <= 60 ? n : 5
            } catch (e) { }
        }
    }
    readonly property bool soon: lead > 0 && toNext > 0 && toNext <= lead && !napping
    Connections {
        target: pet.ctl
        ignoreUnknownSignals: true
        function onTypedChanged() { if (pet.ctl.typed && pet.ctl.typed.length > 0) pet.awake = true }
    }
    readonly property bool upset: phase === "wrong" || phase === "error"
    readonly property int fails: ctl && typeof ctl.fails === "number" ? ctl.fails : 0
    readonly property bool cross: phase === "wrong" && fails >= 2       // the second miss: that is no friend of its
    readonly property var growl: ({ cat: "hiss!", dog: "grr!", frog: "ribbit?!", bird: "squawk!", turtle: "!", fox: "grr!", dragon: "rawr!" })
    readonly property int frame: unlocking ? (animal === "dragon" ? 4 : 8)     // paws raised (its "beg"); the dragon's 8 is for fire
        : napping ? 5
        : cross ? (animal === "turtle" ? 9 : 0)     // on its feet; the turtle in its shell
        : upset ? 4                         // sitting, turned to look at you
        : phase === "checking" ? 0          // standing, ears up
        : awake || soon ? 4 : 5             // sitting, or asleep
    readonly property string bubble: unlocking ? "♥" : napping || frame === 5 ? "z" : cross ? (growl[animal] || "!") : phase === "wrong" ? "?" : upset ? "..." : soon && phase === "idle" ? "!" : ""
    readonly property bool turned: upset && !cross && !unlocking && !napping       // looking the other way: at you

    // ---- where: beside the clock when there is room on its right, else under the field ----
    readonly property Item clock: around && around.children.length > 0 ? around.children[0] : null
    readonly property real groupW: Math.max(box + 18, label.width)
    readonly property bool beside: around !== null && width - (around.x + around.width) >= 40 + groupW + 24
    visible: shown && sheet.status === Image.Ready && around !== null

    Column {
        id: group
        x: !pet.around ? 0 : pet.beside ? pet.around.x + pet.around.width + 40 : Math.round((pet.width - width) / 2)
        y: !pet.around ? 0
            : pet.beside ? Math.round(pet.around.y + (pet.clock ? pet.clock.y + pet.clock.baselineOffset : 100) - pet.box)
            : pet.around.y + pet.around.height + 28
        spacing: 6

        Item {          // the animal and its hat; facing the clock when it lies beside it
            id: body
            anchors.horizontalCenter: parent.horizontalCenter
            width: pet.box; height: pet.box
            Item {
                anchors.fill: parent
                transform: [
                    Scale { origin.x: pet.box / 2; xScale: (pet.beside ? -1 : 1) * (pet.turned ? -1 : 1) },
                    Translate { id: headShake }
                ]
                Item {      // one 16x16 frame out of the sheet, enlarged with hard pixels
                    anchors.fill: parent
                    clip: true
                    Image {
                        id: sheet
                        x: -pet.frame * pet.box
                        width: sourceSize.width * pet.k
                        height: pet.box
                        source: pet.sheetUrl
                        smooth: false
                        mipmap: false
                    }
                }
                Image {     // its bottom row on the top of the head (assets/pet-anchors.js)
                    visible: pet.hat !== "" && status === Image.Ready
                    readonly property var head: (Heads.heads[pet.animal] || [])[pet.frame] || [12, 2]
                    readonly property var dim: Heads.hats[pet.hat] || [0, 0]
                    x: Math.round((head[0] - dim[0] / 2) * pet.k)
                    y: (head[1] - dim[1] + 1) * pet.k
                    width: dim[0] * pet.k; height: dim[1] * pet.k
                    source: pet.hat !== "" ? Qt.resolvedUrl("assets/hat-" + pet.hat + ".png") : ""
                    smooth: false
                }
            }
            Text {          // z, !, or a heart, by its head (which side depends on which way it faces)
                visible: pet.bubble !== ""
                x: pet.beside !== pet.turned ? -width - 2 : parent.width + 2
                y: pet.frame === 5 || pet.frame === 7 ? pet.box * 0.3 : -4
                text: pet.bubble
                color: pet.bubble === "♥" || pet.cross ? "#e5484d" : "#b8b2ab"
                style: Text.Outline; styleColor: "#16161a"
                font { family: "FiraCode Nerd Font"; pixelSize: 22; bold: true }
            }
        }
        // a wrong password: it shakes its head as the field shakes (the one thing that moves here)
        SequentialAnimation {
            id: no
            NumberAnimation { target: headShake; property: "x"; to: -5; duration: 60 }
            NumberAnimation { target: headShake; property: "x"; to: 5; duration: 90 }
            NumberAnimation { target: headShake; property: "x"; to: -4; duration: 80 }
            NumberAnimation { target: headShake; property: "x"; to: 0; duration: 70 }
        }
        Connections {
            target: pet.ctl
            ignoreUnknownSignals: true
            function onPhaseChanged() { if (pet.ctl.phase === "wrong" && !pet.napping) no.restart() }
        }
        Column {
            id: label
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: pet.name !== ""
                text: pet.name
                color: "#e6e1dc"
                style: Text.Outline; styleColor: "#16161a"
                font { family: "FiraCode Nerd Font"; pixelSize: 15; bold: true }
            }
        }
    }
}
