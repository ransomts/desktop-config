// The bar pet's sounds (Pet.qml is its mind). Off until switched on: its menu, Settings >
// "Sounds", or `qs ipc call pet sounds true`. The files are made by assets/pet-sounds-build
// into assets/sounds/ (synthesised there, nothing downloaded).
//
// Only things you asked for make a sound, so the bar never chatters by itself:
//   pat        a soft pop                  (a click on it, Pet in its menu, `pet pat`)
//   feed       a munch                     (Feed)
//   speak, croak, sing    its own voice     (the tricks that are a sound, when it does them)
//   greeting on unlock    its own voice
//   focus timer finished  a little fanfare  (in place of the shell's "complete" cue)
//   moth caught           the same fanfare, only for a moth you sent (`pet bug`): a moth that
//                         comes by itself stays as quiet as the rest of its own life
// Never while it is asleep, while Do Not Disturb is on, while it is hidden for a shared
// screen, or while the shell's own sounds are off (control panel). At most one sound every
// 0.4 s and four in any six seconds, so a burst of clicks cannot machine-gun.
//   qs ipc call pet sounds true|false
//   qs ipc call pet soundlevel quiet|soft|normal
//   qs ipc call pet sound NAME     play one now (cat dog frog bird pat munch tada); says why not if it stays quiet
// Kept in ~/.local/state/pet-sound.json.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: snd

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/pet-sound.json"
        blockLoading: true
        blockWrites: true           // a change made while an unfinished write was in flight used to be undone when it landed
        printErrors: false
        onAdapterUpdated: saveSoon.restart()
        JsonAdapter {
            id: store
            property bool enabled: false        // off unless asked for
            property string level: "quiet"
        }
    }
    Timer { id: saveSoon; interval: 300; onTriggered: file.writeAdapter() }

    // volume steps, given to pw-play. The files are made quiet (RMS about -22 dBFS), so "quiet"
    // comes out a little under the shell's "complete" cue (about -30 dB RMS as Sys.sound plays
    // it), "soft" about level with it and "normal" a little over
    readonly property var levels: ({ quiet: 0.3, soft: 0.5, normal: 0.8 })
    readonly property var levelNames: ["quiet", "soft", "normal"]
    readonly property bool enabled: store.enabled
    readonly property string level: levels[store.level] !== undefined ? store.level : "quiet"
    function setEnabled(on) {
        store.enabled = on
        if (on) Qt.callLater(() => snd.play(Pet.animal))       // a sample, so you know what you turned on
    }
    function setLevel(name) {
        if (levels[name] === undefined) return level
        store.level = name
        Qt.callLater(() => snd.play("pat"))                     // how loud that is
        return level
    }
    function nextLevel() { return setLevel(levelNames[(levelNames.indexOf(level) + 1) % levelNames.length]) }

    // why it would stay quiet just now ("" when it would play)
    readonly property var names: ["cat", "dog", "frog", "bird", "pat", "munch", "tada"]
    function why(name) {
        if (names.indexOf(name) < 0) return "no sound called " + name
        if (!store.enabled) return "pet sounds are off"
        if (!Sys.sounds) return "the shell's sounds are off"
        if (!Pet.enabled) return "the pet is hidden"
        if (Notif.dnd) return "Do Not Disturb is on"
        if (Pet.hiding) return "the screen is being shared"
        if (Pet.mood === "asleep") return "it is asleep"
        const t = Date.now()
        if (t - last < 400 || t - Sys.lastSound < 250) return "too soon after the last sound"
        if (recent.filter(r => t - r < 6000).length >= 4) return "too many sounds just now"
        return ""
    }
    property double last: 0
    property var recent: []                     // when the last few played (ms since the epoch)
    function play(name) {
        if (why(name) !== "") return false
        const t = Date.now()
        last = t
        recent = recent.filter(r => t - r < 6000).concat([t])
        Sys.lastSound = t                        // and the shell's own cues keep out of its way
        const path = decodeURIComponent(Qt.resolvedUrl("assets/sounds/" + name + ".oga").toString().replace("file://", ""))
        Sys.run("pw-play --volume " + levels[level] + " '" + path + "'")
        return true
    }
    function test(name) { const w = why(name); return play(name) ? "played " + name + " (" + level + ")" : w }

    // its own voice: only the pet itself (not its friend), and only on the bar it is shown on
    function voice(sprite) { if (sprite.who === 0 && sprite.active) play(sprite.animal) }
    // a moth it caught: a fanfare, if the moth was one you sent in the last half minute
    property double bugAsked: 0
    function caught(sprite) { if (sprite.who === 0 && sprite.active && Date.now() - bugAsked < 30000) play("tada") }

    Connections {
        target: Pet
        function onPat(who) { snd.play("pat") }                 // every bar hears it once here, not once per sprite
        function onFeed() { snd.play("munch") }
        function onBug() { snd.bugAsked = Date.now() }          // the signal is only sent when asked (menu, ipc)
        function onGreet() { if (Pet.mood !== "focus") snd.play(Pet.animal) }      // as PetSprite.greet: no greeting during focus
    }
}
