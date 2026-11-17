// Lock screen: `qs -p ~/.config/quickshell/lockscreen.qml`. A separate Quickshell instance
// from the main shell (shell.qml), sharing this folder for the shaders and palettes; started by
// ~/.local/bin/lock-screen, which
// hypridle runs on `loginctl lock-session`), so a reload or crash of the main shell can
// never drop or break the lock. It shows a still frame of the current wallpaper scene,
// the time, and a password field.
//
// The password is checked by ~/.local/bin/pam-check (system PAM, service "hyprlock").
// Safety net: three failed checks in a row, of any kind, and this instance exits without
// unlocking; lock-screen then starts hyprlock, which takes the lock over.
//
// LOCK_TEST=preview  draw the screen as an ordinary window on $LOCK_SCREEN for 4 s (no lock)
//                    (with LOCK_SCENE=sky to try a scene, LOCK_CAPS=1 to see the Caps Lock warning,
//                    LOCK_FORM=DP-9 to put the password field on another screen)
// LOCK_TEST=auto     really lock, then unlock by itself after 4 s
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    settings.watchFiles: false

    readonly property string mode: Quickshell.env("LOCK_TEST") || ""
    readonly property string home: Quickshell.env("HOME")
    readonly property string resultFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/lock-screen.result"

    property bool dark: true
    property string scene: "contours"
    property real lat: 34.6834              // where the sky and ridges scenes are (wallpaper.json, as the wallpaper)
    property real lng: -82.8374
    FileView {
        path: root.home + "/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark"
        printErrors: false
        onLoaded: root.dark = text().trim() !== "false"
    }
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/wallpaper.json"
        printErrors: false
        onLoaded: {
            try {
                const w = JSON.parse(text())
                root.scene = Quickshell.env("LOCK_SCENE") || w.scene || "contours"
                if (typeof w.lat === "number" && typeof w.lng === "number") { root.lat = w.lat; root.lng = w.lng }
            } catch (e) { }
        }
    }

    // ---- the screen with the password field: the laptop's own panel, else the first one.
    // The others show the wallpaper, the clock and the date only (LockView.form). ----
    readonly property string formScreen: {
        const all = Quickshell.screens, lap = all.find(s => /^eDP/.test(s.name))
        if (Quickshell.env("LOCK_FORM")) return Quickshell.env("LOCK_FORM")
        return lap ? lap.name : all.length > 0 ? all[0].name : ""
    }

    // ---- Caps Lock: read when locking and a moment after each press of the key (the keyboard
    // LEDs, and what Hyprland says of each keyboard) ----
    property bool caps: Quickshell.env("LOCK_CAPS") === "1"
    Process {
        id: capsRead
        running: Quickshell.env("LOCK_CAPS") !== "1"
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null; hyprctl -j devices 2>/dev/null | grep -c '\"capsLock\": true'"]
        stdout: StdioCollector { onStreamFinished: root.caps = /^\s*[1-9]/m.test(text) }
    }
    Timer { id: capsSoon; interval: 150; onTriggered: if (!capsRead.running) capsRead.running = true }

    // ---- password ----
    property string typed: ""
    property string pending: ""
    property string phase: "idle"           // idle | checking | wrong | error
    property int fails: 0
    property bool unlocking: false          // the password was right: a moment for the pet's heart (LockPet.qml) and the fade (LockView.qml), then the lock opens

    function key(event) {
        if (event.key === Qt.Key_CapsLock) { capsSoon.restart(); return }
        if (phase === "checking" || unlocking) return
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) submit()
        else if (event.key === Qt.Key_Backspace) typed = typed.slice(0, -1)
        else if (event.key === Qt.Key_Escape || (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier))) typed = ""
        else if (event.text.length > 0 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            if (phase !== "idle") phase = "idle"
            typed += event.text
        }
    }
    function submit() {
        if (typed === "" || phase === "checking") return
        pending = typed
        typed = ""
        phase = "checking"
        auth.running = true
    }
    function verdict(code) {
        if (code === 0) { finish("unlocked"); return }
        fails += 1
        phase = code === 1 ? "wrong" : "error"
        if (fails >= 3) finish("handover")
        else calm.restart()
    }
    function finish(how) {
        Quickshell.execDetached(["sh", "-c", "echo " + how + " > '" + resultFile + "'"])
        if (how === "unlocked") { unlocking = true; open.start(); return }
        leave.start()
    }
    Timer { id: open; interval: 600; onTriggered: { lock.locked = false; leave.start() } }
    Timer { id: calm; interval: 1800; onTriggered: if (root.phase !== "checking") root.phase = "idle" }
    Timer { id: leave; interval: 250; onTriggered: Qt.quit() }
    Process {
        id: auth
        command: ["env", "-u", "LD_LIBRARY_PATH", "-u", "LIBGL_DRIVERS_PATH", "-u", "LIBVA_DRIVERS_PATH",
                  root.home + "/.local/bin/pam-check", "hyprlock"]
        stdinEnabled: true
        onStarted: { write(root.pending + "\n"); root.pending = "" }
        onExited: (exitCode, exitStatus) => root.verdict(exitCode)
    }

    // ---- the lock itself ----
    WlSessionLock {
        id: lock
        locked: root.mode !== "preview"
        WlSessionLockSurface {
            id: surface
            color: "#16161a"
            LockView { anchors.fill: parent; ctl: root; screenObj: surface.screen }
        }
    }

    // ---- test modes ----
    PanelWindow {
        visible: root.mode === "preview"
        screen: Quickshell.screens.find(s => s.name === Quickshell.env("LOCK_SCREEN")) || Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-lock-preview"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "#16161a"
        LockView { anchors.fill: parent; ctl: root; screenObj: parent.screen || Quickshell.screens[0]; demo: true }
    }
    Timer {
        interval: 4000
        running: root.mode !== ""
        onTriggered: { if (root.mode === "auto") root.finish("unlocked"); else Qt.quit() }
    }
}
