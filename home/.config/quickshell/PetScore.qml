// Treat catch, the pet's game on an empty desktop (PetGame.qml draws and runs it): who is
// playing, and the best score, kept in ~/.local/state/pet-game.json.
//
// Only offered while the pet is down on a desktop (Wallpaper.qml), not asleep, not during a
// focus period. Started from its menu ("Play a game") or by script:
//   qs ipc call pet game        start; a second call stops it; says why not when it cannot
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: score

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/pet-game.json"
        blockLoading: true
        blockWrites: true           // a change made while an unfinished write was in flight used to be undone when it landed
        printErrors: false
        onAdapterUpdated: saveSoon.restart()
        JsonAdapter {
            id: store
            property int best: 0
            property int games: 0
        }
    }
    Timer { id: saveSoon; interval: 300; onTriggered: file.writeAdapter() }

    // the PetGame of the desktop the pet is down on (each wallpaper has one; the pet is on one
    // screen at a time), else null
    property Item host: null
    readonly property bool here: host !== null
    readonly property bool running: host !== null && host.running
    readonly property int best: store.best
    readonly property int games: store.games

    // why a game cannot start just now ("" when it can)
    function why() {
        if (!host) return "the pet is not down on an empty desktop"
        if (!host.petReady()) return "the pet is not on this desktop just now"
        if (Pet.mood === "asleep") return Pet.name + " is asleep"
        if (Pet.focusing) return "not during a focus period"
        return ""
    }
    function start() {
        if (running) return "already playing"
        const w = why()
        if (w !== "") return w
        host.begin()
        return "treat catch: " + Math.round(host.length / 1000) + " s" + (store.best > 0 ? ", best " + store.best : "")
    }
    function stop() {
        if (!running) return "no game running"
        const n = host.score
        host.finish("stopped")
        return "stopped: " + n + " points"
    }
    function toggle() { return running ? stop() : start() }

    // a game ended with `n` points: true when that is a new best
    function record(n) {
        store.games++
        if (n <= store.best) return false
        store.best = n
        return true
    }
}
