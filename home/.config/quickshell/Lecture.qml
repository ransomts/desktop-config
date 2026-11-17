// Lecture tools: state shared by the overlays (LectureDraw, LectureSpot, LectureKeys,
// LectureTimer), the control panel block (LecturePanel) and `qs ipc call lecture ...`.
// Everything is in memory; nothing is written. Every tool is off until asked for, and
// all of them go off together (allOff) when presenting ends: the coordinator's
// display-menu removes $XDG_RUNTIME_DIR/presenting, watched here only while a tool is on.
// Key display also goes off when the session locks (logind's Lock signal, watched only
// while it is on), so a password is never shown.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: lec

    // ---- draw (LectureDraw.qml) ----
    property bool drawOn: false
    property bool hold: false               // ink stays, clicks and keys pass through
    property string tool: "pen"
    readonly property var tools: ["pen", "marker", "arrow", "box", "ellipse", "line"]   // keys 1-6
    property int colorIndex: 0
    readonly property var colorNames: ["orange", "purple", "red", "green", board === 2 ? (Theme.dark ? "black" : "white") : (Theme.dark ? "white" : "black")]
    readonly property color contrastInk: board === 2 ? Theme.solidBg : Theme.fg      // white on dark, black on light
    readonly property var colors: [Theme.accentBg, Theme.alt, Theme.red, Theme.ok, contrastInk]
    readonly property color ink: colors[colorIndex]
    readonly property var weights: [2, 3, 4, 6, 8, 12, 16, 24]
    property int weightIndex: 2
    readonly property real weight: weights[weightIndex]
    property int board: 0                   // 0 none, 1 this theme's solid background, 2 the other theme's
    readonly property color boardColor: board === 1 ? Theme.solidBg : board === 2 ? Theme.fg : "transparent"
    signal inkCommand(string what)          // "undo" | "redo" | "clear", from the panel or the menu

    function toggleDraw() {                 // Super+Z then D: start; while held: draw again; else leave
        if (!drawOn) { hold = false; drawOn = true }
        else if (hold) hold = false
        else leaveDraw()
    }
    function toggleHold() { if (drawOn) hold = !hold }
    function leaveDraw() { drawOn = false; hold = false; board = 0 }
    function setTool(name) { if (tools.indexOf(name) >= 0) tool = name }
    function cycleColor() { colorIndex = (colorIndex + 1) % colors.length }
    function stepWeight(d) { weightIndex = Math.max(0, Math.min(weights.length - 1, weightIndex + d)) }
    function cycleBoard() { board = (board + 1) % 3 }

    // ---- spotlight (LectureSpot.qml) ----
    property bool spotOn: false
    property int spotRadius: 150
    function toggleSpot() { spotOn = !spotOn }
    function setSpotSize(px) { spotRadius = Math.max(40, Math.min(800, Math.round(px))) }

    // ---- zoom: Hyprland's cursor zoom, around the pointer ----
    readonly property var zoomSteps: [1.0, 1.5, 2, 3, 4]
    property int zoomIndex: 0
    readonly property real zoomFactor: zoomSteps[zoomIndex]
    function zoomCmd(f) { return "hyprctl eval 'hl.config({ cursor = { zoom_factor = " + f + " } })' >/dev/null" }
    function zoom(step) {
        const i = Math.max(0, Math.min(zoomSteps.length - 1, zoomIndex + step))
        if (i === zoomIndex) return
        zoomIndex = i
        Sys.run(zoomCmd(zoomFactor))
    }
    function zoomReset() { zoomIndex = 0; Sys.run(zoomCmd(1.0)) }

    // ---- key display (LectureKeys.qml runs ~/.local/bin/lecture-keys while this is on) ----
    property bool keysOn: false
    property string keysProblem: ""          // set by LectureKeys when the reader finds no keyboard
    function toggleKeys() { keysOn = !keysOn }
    function keysOff() { keysOn = false }
    // one line from lecture-keys, "mods<TAB>key" -> { mods: ["Ctrl", ...], key }
    function parseKeyLine(line) {
        const tab = line.indexOf("\t")
        if (tab < 0) return null
        const mods = line.slice(0, tab).split("+").filter(m => m !== "")
        const key = line.slice(tab + 1)
        return key === "" ? null : { mods: mods, key: key }
    }
    Process {                               // logind says lock: key display off before any password is typed
        running: lec.keysOn
        command: Sys.clean.concat(["dbus-monitor", "--system", "type='signal',interface='org.freedesktop.login1.Session',member='Lock'"])
        stdout: SplitParser { onRead: line => { if (/member=Lock\b/.test(line)) lec.keysOff() } }
    }

    // ---- timer (LectureTimer.qml) ----
    property double timerEnd: 0             // ms since the epoch; 0 = no timer
    property double timerTotal: 0           // ms it was set for
    property string timerLabel: ""
    property var nowFn: null                // tests put a fast clock here
    function now() { return nowFn ? nowFn() : Date.now() }
    function startTimer(minutes, label) {
        if (!(minutes > 0)) { stopTimer(); return }
        timerTotal = Math.round(Math.min(minutes, 600) * 60000)
        timerLabel = label || ""
        timerPausedLeft = -1
        timerEnd = now() + timerTotal
    }
    function stopTimer() { timerEnd = 0; timerTotal = 0; timerLabel = ""; timerPausedLeft = -1 }
    // paused: the time left is held here (ms) and timerEnd no longer counts; -1 = running
    property double timerPausedLeft: -1
    readonly property bool timerPaused: timerEnd > 0 && timerPausedLeft >= 0
    function pauseTimer() {                 // pause, or carry on
        if (timerEnd <= 0) return
        if (timerPaused) { const left = timerPausedLeft; timerPausedLeft = -1; timerEnd = now() + left }
        else if (timerEnd - now() > 0) timerPausedLeft = timerEnd - now()
    }
    function resetTimer() {                 // back to the full length; a paused one stays paused
        if (timerEnd <= 0 || timerTotal <= 0) return
        if (timerPaused) { timerPausedLeft = timerTotal; timerEnd = now() + timerTotal }
        else timerEnd = now() + timerTotal
    }
    function clock(sec) {                   // 754 -> "12:34", 3725 -> "1:02:05"
        sec = Math.max(0, Math.ceil(sec))
        const h = Math.floor(sec / 3600), m = Math.floor(sec / 60) % 60, s = sec % 60
        const two = n => (n < 10 ? "0" : "") + n
        return (h > 0 ? h + ":" + two(m) : two(m)) + ":" + two(s)
    }

    // ---- all of it ----
    readonly property bool anyOn: drawOn || spotOn || keysOn || timerEnd > 0 || zoomIndex !== 0
    function allOff() {
        leaveDraw()
        spotOn = false
        keysOn = false
        stopTimer()
        if (zoomIndex !== 0) zoomReset()
    }
    function status() {
        const t = timerEnd > 0 ? Math.max(0, (timerPaused ? timerPausedLeft : timerEnd - now()) / 1000) : -1
        return "draw=" + (drawOn ? (hold ? "hold" : "on") : "off")
             + " tool=" + tool + " colour=" + colorNames[colorIndex] + " weight=" + weight
             + " spot=" + (spotOn ? "on" : "off") + " spotsize=" + spotRadius
             + " zoom=" + zoomFactor
             + " keys=" + (keysOn ? "on" : "off")
             + " timer=" + (t < 0 ? "off" : clock(t) + (timerPaused ? "(paused)" : "")) + (t >= 0 && timerLabel !== "" ? " label=" + timerLabel.replace(/\s+/g, "_") : "")
             + " presenting=" + (presenting ? "yes" : "no")
    }

    // ---- presenting: when $XDG_RUNTIME_DIR/presenting goes away, everything goes off ----
    property bool presenting: false
    FileView {
        id: presentFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/presenting"
        printErrors: false
        watchChanges: lec.anyOn
        onFileChanged: reload()
        onLoaded: lec.presenting = true
        onLoadFailed: {
            if (lec.presenting) { lec.presenting = false; lec.allOff() }
        }
    }
    onAnyOnChanged: if (anyOn) presentFile.reload()
    Timer {                                 // a deleted file is not always reported: look every 3 s, only while a tool is on
        interval: 3000; repeat: true
        running: lec.anyOn
        onTriggered: presentFile.reload()
    }
}
