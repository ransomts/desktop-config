pragma Singleton
// The GVM video lights (~/.local/bin/gvm), for the bar's light pill and LightsList.qml.
//   Lights.present      lights are named in ~/.config/gvm/lights (the pill hides otherwise)
//   Lights.names        their names, in file order
//   Lights.states       last known {name: {on, bright, mode, cct, hue, sat, at, by}}, from
//                       $XDG_STATE_HOME/gvm/lights.json (written by gvm and gvm-gui; watched)
//   Lights.anyOn / allOn / allOff / known / stateText()   read from those
//   Lights.presets      [{name, note}] from ~/.config/gvm/presets.json (watched)
//   Lights.busy, error  a command is running / why the last one failed ("" when it worked)
//   Lights.on()  off()  quick() (off if any is on, else on)  preset(name)  openWindow()
// Every command is `gvm -l all ...` (or `gvm preset NAME`): gvm hands it to the lights window
// when that is open, since the window holds the lights; otherwise it connects itself, 3-5 s a
// light. Nothing polls: finding out more would mean connecting, which takes the lights from the
// phone app. A click while a command runs is kept and runs next (the latest click wins).
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: lights

    property var island: null               // shell.qml's island: a failed command is said there
    readonly property string home: Quickshell.env("HOME")
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
    readonly property string gvm: Sys.bin + "gvm"

    property var names: []
    property var states: ({})
    property var presets: []
    property bool busy: false
    property string error: ""
    property var pending: null              // [args, what] waiting for the running command
    property string doing: ""
    property var calls: []                  // every command started, newest last (tests)

    readonly property bool present: names.length > 0
    readonly property var known: names.filter(n => !!states[n] && states[n].on !== undefined)
    readonly property bool anyOn: known.some(n => states[n].on === 1)
    readonly property bool allOn: present && known.length === names.length && known.every(n => states[n].on === 1)
    readonly property bool allOff: present && known.length === names.length && known.every(n => states[n].on === 0)
    readonly property int lastAt: known.reduce((m, n) => Math.max(m, states[n].at || 0), 0)

    function stateText() {
        if (known.length === 0) return "not known yet"
        if (allOn) return names.length > 1 ? "all on" : "on"
        if (allOff) return names.length > 1 ? "all off" : "off"
        return names.map(n => n + " " + (!states[n] || states[n].on === undefined ? "?" : states[n].on === 1 ? "on" : "off")).join(", ")
    }
    function tip() {
        const when = lastAt > 0 ? new Date(lastAt * 1000) : null
        return "<b>Lights</b>: " + (busy ? "working…" : stateText())
            + (when && !busy ? "\nas of " + Qt.formatTime(when, "h:mm ap") : "")
            + (error !== "" ? "\nLast try: " + error : "")
            + "\nClick: presets and on / off\nRight-click: " + (anyOn ? "all off" : "all on")
            + "\nMiddle-click: the full controls (also Super+Ctrl+L)"
    }

    function run(args, what) {
        if (busy) { pending = [args, what]; return }
        busy = true
        error = ""
        doing = what
        calls = calls.concat([args.join(" ")])
        proc.command = Sys.clean.concat([gvm].concat(args))
        proc.running = true
    }
    function on() { run(["-l", "all", "on"], "All on") }
    function off() { run(["-l", "all", "off"], "All off") }
    function quick() { if (anyOn) off(); else on() }
    function preset(name) { run(["preset", String(name)], String(name)) }
    function openWindow() { Sys.launch([home + "/.local/bin/gvm-lights"]) }
    function status() { return (present ? names.join(", ") + ": " + stateText() : "no lights named") + (busy ? " (working: " + doing + ")" : "") + (error !== "" ? " (last error: " + error + ")" : "") }

    Process {
        id: proc
        stderr: StdioCollector { id: err }
        onExited: code => {
            lights.busy = false
            if (code !== 0) {
                const lines = err.text.trim().split("\n").filter(l => l.trim() !== "")
                lights.error = (lines.length ? lines[lines.length - 1] : "gvm exited with " + code).replace(/^gvm: /, "")
                if (lights.island) lights.island.say({ kind: "lights", glyph: Icons.lightOff, urgency: "low",
                                                       title: "Lights: " + lights.doing + " didn't work", sub: lights.error, ms: 6000 })
            }
            if (lights.pending) { const p = lights.pending; lights.pending = null; lights.run(p[0], p[1]) }
        }
    }

    // ~/.config/gvm/lights: "name address" lines, # comments
    FileView {
        path: lights.configHome + "/gvm/lights"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: lights.names = text().split("\n").map(l => l.split("#")[0].trim().split(/\s+/)).filter(p => p.length >= 2).map(p => p[0])
        onLoadFailed: lights.names = []
    }
    // ~/.config/gvm/presets.json: {"Name": {"note": ..., "<light>" | "all": {...}}}
    FileView {
        path: lights.configHome + "/gvm/presets.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let o = null
            try { o = JSON.parse(text()) } catch (e) { o = null }
            lights.presets = o && typeof o === "object" && !Array.isArray(o)
                ? Object.keys(o).map(k => ({ name: k, note: o[k] && o[k].note ? String(o[k].note) : "" })) : []
        }
        onLoadFailed: lights.presets = []
    }
    // what gvm / gvm-gui last knew
    FileView {
        path: lights.stateHome + "/gvm/lights.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let o = null
            try { o = JSON.parse(text()) } catch (e) { o = null }
            if (o && o.lights && typeof o.lights === "object") lights.states = o.lights
        }
        onLoadFailed: lights.states = ({})
    }
}
