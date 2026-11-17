// Webcam bubble (CamBubble.qml draws it, CamView.qml is its content): on/off, size, place, and the camera feed.
// IPC: qs ipc call cam toggle | on | off | size PX | use DEVICE | next | status. screen-record --cam
// turns it on while recording. Choosing a camera: Super+Ctrl+Shift+W (`cams pick`), middle-click on
// the bubble (the next camera), or Settings > Recording. The cameras come from `cams`.
//
// The camera: this Nix-built Quickshell has no QtMultimedia (`import QtMultimedia` fails with
// "module is not installed"), so ffmpeg reads the camera (v4l2, 640x480), crops it square, and
// writes a 480 px JPEG to $XDG_RUNTIME_DIR/qs-cam/frame.jpg 15 times a second (atomic rename:
// never half a picture); CamView reloads it on a 15 Hz timer and draws it round and mirrored.
// ffmpeg runs ONLY while the bubble is shown, so the camera (and its LED) is off otherwise; it is
// stopped (SIGTERM) when the bubble hides and dies with the shell (setpriv --pdeathsig).
//
// Remembered in $XDG_STATE_HOME/cam-bubble.json:
//   size    bubble diameter in px (120-480, default 220; scroll on the bubble to change)
//   device  the camera (default /dev/video0; a chosen one is kept by its /dev/v4l/by-id name,
//           which does not change with plug order)
//   pos     per screen name, the bubble's centre as fractions of that screen ([fx, fy]);
//           a screen with none gets the bottom-right corner
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: cs
    property bool shown: false
    property string screenName: ""          // where it shows: the focused screen when turned on
    property string error: ""               // why there is no picture (camera missing or busy)
    property var cameras: []                // [{path, name, dev}] from `cams` (dev: its /dev/videoN)
    property string notice: ""              // the camera's name, shown on the bubble for a moment after a switch
    property bool switching: false          // feed stopped to restart it on another camera
    readonly property int camIndex: cameras.findIndex(c => c.path === store.device || c.dev === store.device)
    readonly property string deviceName: {
        const c = cameras[camIndex]
        return c ? c.name : store.device
    }
    readonly property alias cfg: store
    readonly property int minSize: 120
    readonly property int maxSize: 480
    readonly property int fps: 15
    readonly property bool feeding: feed.running
    readonly property int feedPid: feed.running ? feed.processId : 0
    readonly property string frameDir: Quickshell.env("CAM_FRAME_DIR")
        || (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-cam"
    readonly property string frameFile: frameDir + "/frame.jpg"
    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/cam-bubble.json"

    // ffmpeg's input; the test harness swaps in a generated picture (lavfi) so no camera is opened
    property var input: ["-f", "v4l2", "-video_size", "640x480", "-i", store.device]
    readonly property string feedScript: 'd=$1; shift; mkdir -p "$d" && rm -f "$d/frame.jpg" && '
        + 'exec setpriv --pdeathsig TERM ffmpeg -hide_banner -loglevel error -nostdin "$@" '
        + '-vf "crop=min(iw\\,ih):min(iw\\,ih),scale=480:480" -r ' + fps + ' -q:v 5 '
        + '-f image2 -update 1 -atomic_writing 1 -y "$d/frame.jpg"'
    readonly property var command: Sys.clean.concat(["sh", "-c", feedScript, "cam-feed", frameDir]).concat(input)

    function on() {
        const m = Hyprland.focusedMonitor
        const s = Quickshell.screens.find(x => m && x.name === m.name) || Quickshell.screens[0]
        screenName = s ? s.name : ""
        error = ""
        shown = true
        scan()                                  // a camera plugged in since shows up in the lists
    }
    function off() { shown = false }
    function scan() { if (!lister.running) lister.running = true }
    // show DEVICE in the bubble (turning it on when off)
    function use(device) {
        if (!device) return store.device
        const changed = device !== store.device
        store.device = device
        error = ""
        notice = deviceName
        noticeTimer.restart()
        if (!shown) on()
        else if (changed && feed.running) switching = true     // feed restarts once it has stopped
        else if (!feed.running) { switching = true; switching = false }   // retry after an error
        return device
    }
    // the next camera in the list (wraps); with the list not read yet, read it first
    function next() {
        if (!cameras.length) { pendingNext = true; scan(); return }
        use(cameras[(camIndex + 1) % cameras.length].path)
    }
    property bool pendingNext: false
    function toggle() { if (shown) off(); else on() }
    function setSize(px) { store.size = Math.max(minSize, Math.min(maxSize, Math.round(px))); return store.size }
    function posFor(name) { const p = store.pos || {}; return p[name] || null }
    function savePos(name, fx, fy) {
        const p = Object.assign({}, store.pos || {})
        p[name] = [Math.round(fx * 1000) / 1000, Math.round(fy * 1000) / 1000]
        store.pos = p
    }
    function status() {
        return JSON.stringify({ shown: shown, screen: screenName, size: store.size, device: store.device, name: deviceName,
                                camera: feed.running, pid: feedPid, error: error })
    }

    Process {
        id: feed
        running: cs.shown && !cs.switching
        command: cs.command
        stderr: StdioCollector { id: feedErr }
        onExited: (code, status) => {
            if (cs.switching) { cs.switching = false; return }   // restarts on the new camera
            if (!cs.shown) return                   // we stopped it: the camera is released
            const why = (feedErr.text || "").trim().split("\n").pop()
            cs.error = "No camera" + (why ? ": " + why.slice(0, 120) : "")
            console.warn("CamState: camera feed ended (" + code + ")", why)
        }
    }

    Process {
        id: lister
        command: Sys.clean.concat([Quickshell.env("HOME") + "/.local/bin/cams"])
        stdout: StdioCollector {
            onStreamFinished: {
                cs.cameras = text.split("\n").filter(l => l.includes("\t")).map(l => {
                    const [path, name, dev] = l.split("\t"); return { path: path, name: name, dev: dev || path } })
                if (cs.pendingNext) { cs.pendingNext = false; if (cs.cameras.length) cs.next() }
            }
        }
    }
    Timer { id: noticeTimer; interval: 2000; onTriggered: cs.notice = "" }
    Component.onCompleted: scan()

    FileView {
        id: file
        path: cs.stateFile
        blockLoading: true
        blockWrites: true
        printErrors: false
        onAdapterUpdated: saveSoon.restart()
        JsonAdapter {
            id: store
            property int size: 220
            property string device: "/dev/video0"
            property var pos: ({})
        }
    }
    Timer { id: saveSoon; interval: 300; onTriggered: file.writeAdapter() }
}
