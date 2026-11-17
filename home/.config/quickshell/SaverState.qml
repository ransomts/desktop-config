// The idle screensaver's logic (the windows are Saver.qml, one screen's picture SaverView.qml).
// After `minutes` without input the wallpaper scene comes up full-screen on every screen,
// over all windows, with a slow-drifting clock and the pet asleep beside it. Any input takes
// it away. It never locks and never holds the session awake: hypridle still blanks the
// screens at 15 minutes and locks at 30, and the saver steps aside before the blanking.
//
// It does not start while: on battery (unless `battery`), a full-screen window is focused,
// the screen is shared or the camera is on (Sys.videoInUse, Hyprland's screencast event),
// presenting ($XDG_RUNTIME_DIR/presenting), keep awake or another idle inhibitor is on
// (the IdleMonitor respects inhibitors), or the session is locked. When the wallpaper would
// rest (fan busy, on battery, set still) it shows a held frame: nothing animates.
//
//   qs ipc call saver status | preview | stop | minutes 5 | scene same|cycle|NAME | clock true|false | battery true|false
//
// Settings in $XDG_STATE_HOME/saver.json. Every input below is a plain property bound to the
// real thing, so the test harness (tests/saver, SAVER_HARNESS=1) can drive them, idle included.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower

Singleton {
    id: ss
    readonly property bool harness: Quickshell.env("SAVER_HARNESS") === "1"
    readonly property alias cfg: store

    // ---- settings ----
    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/saver.json"
    FileView {
        id: file
        path: ss.stateFile
        blockLoading: true
        blockWrites: true
        printErrors: false
        onAdapterUpdated: saveSoon.restart()
        JsonAdapter {
            id: store
            property int minutes: 5           // idle minutes before it starts; 0: never
            property string scene: "same"     // "same" as the wallpaper, a scene name, or "cycle" (a new one every two minutes)
            property bool clock: true         // the drifting clock and date
            property bool battery: false      // start on battery too (it then shows a held frame)
        }
    }
    Timer { id: saveSoon; interval: 300; onTriggered: file.writeAdapter() }

    function setMinutes(n) { store.minutes = Math.max(0, Math.min(240, n)); return store.minutes }
    function setScene(name) {
        if (name === "same" || name === "cycle" || WallState.scenes.indexOf(name) >= 0) store.scene = name
        return store.scene
    }

    // ---- inputs (bindings to the real thing; the harness assigns them) ----
    property bool idle: false                 // no input for `minutes` (IdleMonitor below)
    property bool blank: false                // no input for `blankAfter`: hypridle is turning the screens off
    readonly property int blankAfter: 900     // hypridle.conf's dpms listener (seconds)
    property bool onBattery: UPower.onBattery
    property bool fullscreen: !!Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen
    property bool screencast: false           // Hyprland's screencast event
    property bool videoInUse: Sys.videoInUse   // a screen share or the camera (PipeWire video streams)
    property bool keepAwake: Sys.keepAwake
    property bool locked: false               // from the probe: `hyprctl locked`
    property bool presenting: false           // from the probe: $XDG_RUNTIME_DIR/presenting exists
    property string probeCmd: "hyprctl locked 2>/dev/null; [ -e \"${XDG_RUNTIME_DIR:-/tmp}/presenting\" ] && echo presenting; true"
    property string focusedScreen: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

    Connections {
        target: Hyprland
        enabled: !ss.harness
        function onRawEvent(event) { if (event.name === "screencast") ss.screencast = event.data.split(",")[0] === "1" }
    }

    // Two idle monitors, both respecting inhibitors (keep awake, a playing video): one for the
    // saver itself, one at hypridle's blanking time so the saver stops before DPMS goes off.
    // Created only while the saver is on; a monitor is a Wayland object, nothing polls.
    LazyLoader {
        active: !ss.harness && store.minutes > 0
        onActiveChanged: if (!active) { ss.idle = false; ss.blank = false }
        IdleMonitor {
            timeout: store.minutes * 60
            respectInhibitors: true
            onIsIdleChanged: ss.idle = isIdle
        }
    }
    LazyLoader {
        active: !ss.harness && store.minutes > 0
        onActiveChanged: if (!active) ss.blank = false
        IdleMonitor {
            timeout: ss.blankAfter - 5
            respectInhibitors: true
            onIsIdleChanged: ss.blank = isIdle
        }
    }

    // ---- what is in the way (empty: nothing) ----
    readonly property string blocker: onBattery && !store.battery ? "on battery"
        : fullscreen ? "a full-screen window"
        : videoInUse || screencast ? "screen shared or camera on"
        : keepAwake ? "keep awake is on"
        : presenting ? "presenting"
        : locked ? "the session is locked" : ""

    // ---- showing ----
    property bool dismissed: false            // input came while it was up: wait for the next idle spell
    property bool probed: false
    readonly property bool wanted: store.minutes > 0 && idle && !blank && !dismissed
    onWantedChanged: { probed = false; if (wanted) runProbe() }
    onIdleChanged: if (!idle) dismissed = false
    property bool previewing: false
    readonly property bool shown: !blank && (previewing || (wanted && probed && blocker === ""))
    // animating: the wallpaper's own rule (mains, fan not busy, set moving), and only while up
    readonly property bool moving: shown && WallState.moving
    property string petScreen: ""             // the screen that was focused when it came up: the pet and the keyboard
    onShownChanged: {
        if (shown) { petScreen = focusedScreen; cycleAt = Math.max(0, WallState.scenes.indexOf(WallState.cfg.scene)) }
        shownAt = shown ? Date.now() : 0
    }
    property double shownAt: 0

    Process {
        id: probe
        command: Sys.clean.concat(["sh", "-c", ss.probeCmd])
        stdout: StdioCollector {
            onStreamFinished: {
                ss.locked = /^\s*true/.test(text)
                ss.presenting = /presenting/.test(text)
                ss.probed = true
            }
        }
    }
    function runProbe() { if (!probe.running) probe.running = true }
    // while up: the lock (a suspend locks without input) and presenting, twice a minute
    Timer { interval: 30000; repeat: true; running: ss.shown && !ss.previewing; onTriggered: ss.runProbe() }

    function dismiss() {
        if (previewing) { previewing = false; previewEnd.stop() }
        if (idle) dismissed = true
    }
    function preview(ms) { petScreen = focusedScreen; previewing = true; previewEnd.interval = ms || 8000; previewEnd.restart() }
    function stop() { previewing = false; previewEnd.stop(); if (idle) dismissed = true }
    Timer { id: previewEnd; interval: 8000; onTriggered: ss.previewing = false }

    // ---- which scene ----
    property int cycleAt: 0
    Timer { interval: 120000; repeat: true; running: ss.shown && store.scene === "cycle"; onTriggered: ss.cycleAt++ }
    readonly property string scene: store.scene === "cycle" ? WallState.scenes[(cycleAt + 1) % WallState.scenes.length]
        : WallState.scenes.indexOf(store.scene) >= 0 ? store.scene : WallState.cfg.scene

    function status() {
        const state = store.minutes <= 0 ? "off"
            : shown ? (previewing ? "preview" : "shown") + (moving ? " (moving)" : " (held frame)")
            : wanted && blocker !== "" ? "idle, not starting: " + blocker
            : blank ? "screens blanking" : "waiting"
        return state + " minutes=" + store.minutes + " scene=" + store.scene + (store.scene !== scene ? " (" + scene + ")" : "")
            + " clock=" + (store.clock ? "on" : "off") + " battery=" + (store.battery ? "on" : "off")
            + (blocker !== "" ? " blocked=\"" + blocker + "\"" : "")
    }
}
