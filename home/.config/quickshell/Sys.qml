// State shared by every bar (one per screen) and the control panel, so each
// script runs once however many screens there are.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris

Singleton {
    id: sys
    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/"

    // ---- the bar can be hidden (qs ipc call bar off) ----
    property bool barVisible: true
    readonly property bool barAtBottom: false

    // Quickshell runs through nixGL, which points library and Qt plugin paths at
    // the Nix store. Programs started from the bar are system ones: give them a
    // clean environment or system Qt/GL apps would load the wrong libraries.
    readonly property var clean: ["env", "-u", "LD_LIBRARY_PATH", "-u", "LIBGL_DRIVERS_PATH", "-u", "LIBVA_DRIVERS_PATH",
                                  "-u", "GBM_BACKENDS_PATH", "-u", "__EGL_VENDOR_LIBRARY_FILENAMES",
                                  "-u", "QT_PLUGIN_PATH", "-u", "NIXPKGS_QT6_QML_IMPORT_PATH"]
    // Both go through run-logged: a command that fails leaves its exit status and last stderr
    // lines in the user journal (journalctl --user -t run-logged); one that succeeds leaves nothing.
    readonly property string logged: Quickshell.env("HOME") + "/.local/bin/run-logged"
    function run(cmd) { Quickshell.execDetached(clean.concat([logged, "sh", "-c", cmd])) }
    function launch(argv) { Quickshell.execDetached(clean.concat([logged], argv)) }   // no shell: argv as given
    signal panelToggle()

    // ---- script-backed pills ----
    property alias dnd: dnd
    property alias drives: drives
    property alias rec: rec
    ScriptSource { id: dnd;     exec: sys.bin + "dnd-toggle status";    interval: 3000;  active: sys.barVisible }
    ScriptSource { id: drives;  exec: sys.bin + "drives";               interval: 5000;  active: sys.barVisible }
    ScriptSource { id: rec;     exec: sys.bin + "screen-record status"; interval: 1000;  active: sys.barVisible }
    function refreshSoon() { refreshTimer.restart() }
    function refreshNow() { dnd.refresh(); drives.refresh(); rec.refresh(); tail.refresh() }
    Timer { id: refreshTimer; interval: 400; onTriggered: sys.refreshNow() }

    // ---- Emacs: the running Org clock and unread mail (shell-status; no emacsclient involved) ----
    property alias orgClock: orgClock
    property alias mail: mail
    ScriptSource { id: orgClock; exec: sys.bin + "shell-status clock"; interval: 30000;  active: sys.barVisible }
    ScriptSource { id: mail;     exec: sys.bin + "shell-status mail";  interval: 120000; active: sys.barVisible }
    // ---- Teams: unread chats, from the local Matrix bridge (teams-unread; the list feeds TeamsList.qml) ----
    property alias teams: teams
    ScriptSource { id: teams; exec: sys.bin + "teams-unread"; interval: 30000; active: sys.barVisible }
    function teamsOpen(roomId) { run(bin + "teams-unread open " + (roomId || "")); teamsSoon.restart() }
    function teamsList() { run(bin + "teams-unread list") }
    Timer { id: teamsSoon; interval: 3000; onTriggered: teams.refresh() }
    function focusEmacs() { run("hyprctl dispatch 'hl.dsp.focus({ window = \"class:^(emacs|Emacs)$\" })'") }

    // ---- Tailscale: looked at often while the control panel is open, rarely otherwise
    // (the bar only shows it while an exit node carries the traffic) ----
    property bool panelOpen: false
    property alias tail: tail
    ScriptSource { id: tail; exec: sys.bin + "shell-status tailscale"; interval: sys.panelOpen ? 4000 : 90000; active: sys.barVisible || sys.panelOpen }
    function setTailscale(on) { run("tailscale " + (on ? "up" : "down") + " >/dev/null 2>&1; " + bin + "bar-refresh"); tail.cls = on ? "on" : "off" }

    // ---- night light (hyprsunset). 6000 K is its "no change"; a hand-set value lasts
    // until the next profile time in hyprsunset.conf. Read only when the panel opens. ----
    property int nightK: 6000
    readonly property bool night: nightK < 5900
    property int nightWanted: 4500          // what the toggle switches on to
    function readNight() { if (!nightGet.running) nightGet.running = true }
    function setNight(k) {
        nightK = Math.max(2500, Math.min(6000, Math.round(k / 100) * 100))
        if (night) nightWanted = nightK
        nightSet.restart()
    }
    Process {
        id: nightGet
        command: sys.clean.concat(["hyprctl", "hyprsunset", "temperature"])
        stdout: StdioCollector { onStreamFinished: { const k = parseInt(text); if (k > 0) sys.nightK = k } }
    }
    Timer { id: nightSet; interval: 80; onTriggered: sys.run("hyprctl hyprsunset " + (sys.night ? "temperature " + sys.nightK : "identity") + " >/dev/null") }

    // ---- Bluetooth headphones: the connected audio device and its battery (BlueZ, pushed, no polling) ----
    readonly property var btDevice: {
        const a = Bluetooth.defaultAdapter
        return a && a.enabled ? (a.devices.values.find(d => d.connected && /^audio-/.test(d.icon || "")) || null) : null
    }
    readonly property QtObject bt: QtObject {
        readonly property var dev: sys.btDevice
        readonly property int pct: dev && dev.batteryAvailable ? Math.round(dev.battery * 100) : -1
        readonly property string shortName: dev ? (dev.name || dev.address).replace(/^.*'s /, "") : ""      // "Tim's Pixel Buds Pro 2" -> "Pixel Buds Pro 2"
        readonly property string text: !dev ? "" : "󰂱" + (pct >= 0 ? "  󰁹 " + pct + "%" : "")
        readonly property string cls: pct >= 0 && pct <= 20 ? "low" : "ok"
        readonly property string tooltip: "<b>Bluetooth</b>: " + shortName.replace(/&/g, "&amp;").replace(/</g, "&lt;") + (pct >= 0 ? ", battery " + pct + "%" : "")
            + "\nClick: Bluetooth devices\nRight-click: reconnect (fixes silent audio)\nMiddle-click: Pixel Buds call / music mode"
    }

    // ---- power profile (system76-power) ----
    // Read once over the standard power-profiles D-Bus interface; after that system76-power only
    // announces changes with its own PowerProfileSwitch signal (no PropertiesChanged), so a
    // dbus-monitor on that signal keeps the pill current. Pushed, no polling.
    property string profileCls: "balanced"      // battery | balanced | performance
    function profileFromNative() {
        profileCls = PowerProfiles.profile === PowerProfile.PowerSaver ? "battery"
                   : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced"
    }
    Connections { target: PowerProfiles; function onProfileChanged() { sys.profileFromNative() } }
    Component.onCompleted: profileFromNative()
    Process {
        running: true
        command: sys.clean.concat(["dbus-monitor", "--system", "type='signal',interface='com.system76.PowerDaemon',member='PowerProfileSwitch'"])
        stdout: SplitParser {
            onRead: line => {
                const m = /^\s*string "(Battery|Balanced|Performance)"/.exec(line)
                if (m) sys.profileCls = m[1].toLowerCase()
            }
        }
    }
    function setProfile(name) {             // then a popup naming the profile actually in force
        run("system76-power profile " + name + " >/dev/null 2>&1; notify-send -a osd -h string:x-canonical-private-synchronous:osd-power -i battery"
            + " \"Power profile: $(system76-power profile 2>/dev/null | sed -n 's/^Power Profile: //p')\"")
    }
    function nextProfile() { setProfile(profileCls === "battery" ? "balanced" : profileCls === "balanced" ? "performance" : "battery") }
    readonly property QtObject profile: QtObject {
        readonly property string cls: sys.profileCls
        readonly property string text: cls === "battery" ? "󰌪" : cls === "performance" ? "󰓅" : "󰾅"
        readonly property string tooltip: "<b>Power profile</b>: " + cls.charAt(0).toUpperCase() + cls.slice(1) + "\nClick: choose\nRight-click: next profile"
    }

    // ---- network (NetworkManager, pushed, no polling) ----
    readonly property var netDev: {
        const ds = Networking.devices.values.filter(d => d.connected)
        return ds.find(d => d.type === DeviceType.Wired) || ds.find(d => d.type === DeviceType.Wifi) || null
    }
    readonly property string netKind: !netDev ? "offline" : netDev.type === DeviceType.Wired ? "wired" : "wifi"      // wifi | wired | offline
    readonly property string netName: {
        if (!netDev) return ""
        if (netDev.type === DeviceType.Wired) return netDev.name
        const n = netDev.networks.values.find(n => n.connected)
        return n ? n.name : ""
    }
    // The Wi-Fi pill is an icon only (its name ran the pills over the clock, 2026-11-12); on any
    // network not listed here the icon turns the warning colour, so a hotspot or guest network shows.
    readonly property var usualNets: ["Torus Shaped Earth", "eduroam"]
    readonly property bool netUnusual: netKind === "wifi" && netName !== "" && usualNets.indexOf(netName) < 0

    // ---- keyboard layout ----
    property string layout: ""
    readonly property string layoutShort: /dvorak/i.test(layout) ? "DV" : layout === "" ? "" : "US"
    Process {
        id: kb
        running: true
        command: ["sh", "-c", "hyprctl devices -j | jq -r '.keyboards[] | select(.main) | .active_keymap' | head -1"]
        stdout: StdioCollector { onStreamFinished: sys.layout = text.trim() }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") sys.layout = event.data.split(",").slice(1).join(",")
        }
    }

    // ---- desktops: workspace N*10+i is desktop N on monitor i (Desk in hyprland.lua) ----
    readonly property var monitorOrder: {
        const ms = Hyprland.monitors.values.slice()
        ms.sort((a, b) => a.x - b.x || a.y - b.y)
        return ms.map(m => m.name)
    }
    function slotOf(monitorName) { return monitorOrder.indexOf(monitorName) + 1 }
    readonly property int desktop: {
        const ws = Hyprland.focusedWorkspace
        return ws && ws.id >= 11 ? Math.floor(ws.id / 10) : 1
    }
    function goDesktop(n) {
        n = Math.max(1, Math.min(10, n))
        run("hyprctl eval 'Desk.go(" + n + ")'")
    }

    // ---- audio ----
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [sys.sink, sys.source] }
    // something is recording from a microphone / capturing video (screen share, camera)
    readonly property bool micInUse: Pipewire.nodes.values.some(n => n.isStream && (n.type & PwNodeType.AudioInStream) === PwNodeType.AudioInStream)
    readonly property bool videoInUse: Pipewire.nodes.values.some(n => n.isStream && (n.type & PwNodeType.Video) === PwNodeType.Video)

    // ---- screen brightness (laptop panel) ----
    property real brightness: 0             // 0..1
    function readBrightness() { if (!brGet.running) brGet.running = true }
    function setBrightness(v) { brightness = Math.max(0.05, Math.min(1, v)); brSet.restart() }
    Process {
        id: brGet
        command: ["brightnessctl", "-m"]     // device,class,current,63%,max
        stdout: StdioCollector {
            onStreamFinished: { const f = text.trim().split(","); if (f.length > 3) sys.brightness = parseInt(f[3]) / 100 }
        }
    }
    // writing needs the video group (see the brightness keys in hyprland.lua); one write per drag step at most
    Timer { id: brSet; interval: 60; onTriggered: sys.run("sg video -c 'brightnessctl -q set " + Math.round(sys.brightness * 100) + "%'") }

    // ---- popups under pills ("calendar", "mixer"), opened on the focused screen's bar ----
    signal popupRequest(string name)

    // ---- media: which player to show. A music player beats a browser tab (a video
    // or stream in Firefox shouldn't take over from Rhythmbox); playing beats paused.
    // playerPin: follow that player (by name) while it exists; "" picks automatically.
    property string playerPin: ""
    readonly property var realPlayers: Mpris.players.values.filter(p => !/playerctld/i.test(p.dbusName || p.identity || ""))
    Timer {                                 // MPRIS does not push the position: ask once a second while playing
        interval: 1000; repeat: true
        running: sys.player !== null && sys.player.isPlaying
        onTriggered: sys.player.positionChanged()
    }
    readonly property var player: {
        const ps = realPlayers
        const pinned = playerPin !== "" ? ps.find(p => p.identity === playerPin) : null
        if (pinned) return pinned
        const browser = p => /firefox|chrom|brave|vivaldi|zen/i.test((p.identity || "") + (p.desktopEntry || ""))
        return ps.find(p => p.isPlaying && !browser(p)) || ps.find(p => p.isPlaying)
            || ps.find(p => !browser(p) && (p.trackTitle || "") !== "") || ps[0] || null
    }

    // ---- agenda: today's events from the Org calendars (~/.local/bin/agenda-day) ----
    property bool todayLoaded: false        // the agenda has been read at least once since the shell (re)loaded (Quiet.qml waits for it)
    property var today: []                  // [{ start, end, title, allday, location, url, date, id }] (see agenda-day)
    property string nowHM: Qt.formatTime(new Date(), "HH:mm")
    readonly property var nextEvent: today.find(e => !e.allday && e.start > nowHM) || null
    readonly property var currentEvent: today.find(e => !e.allday && e.start <= nowHM && e.end > nowHM) || null
    Process {
        id: agenda
        command: sys.clean.concat([sys.bin + "agenda-day"])
        stdout: StdioCollector { onStreamFinished: { try { sys.today = JSON.parse(text) } catch (e) { sys.today = [] } sys.todayLoaded = true } }
    }
    // ---- the bar's clock: `now` (the date pill) and `nowHM`, ticking on the minute ----
    // A Timer (SystemClock too) counts on the monotonic clock, which stops while the laptop sleeps,
    // so after a wake the bar kept the pre-sleep time for up to a minute (16:24 at 19:13, 2026-11-16).
    // logind's PrepareForSleep(false) re-reads the time, and the agenda, the moment the system resumes.
    property date now: new Date()
    function tick() {
        now = new Date()
        nowHM = Qt.formatTime(now, "HH:mm")
        minuteTimer.interval = 60000 - (Date.now() % 60000) + 50     // next fire just after the minute turns
    }
    Timer {
        id: minuteTimer
        interval: 60000; running: true; repeat: true; triggeredOnStart: true
        property int ticks: 0
        onTriggered: {
            sys.tick()
            if (ticks++ % 5 === 0 && !agenda.running) agenda.running = true     // re-read every five minutes
        }
    }
    Process {
        running: true
        command: sys.clean.concat(["dbus-monitor", "--system", "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"])
        stdout: SplitParser {
            onRead: line => {
                if (!/^\s*boolean false/.test(line)) return      // true is going to sleep, false is waking
                sys.tick()
                if (!agenda.running) agenda.running = true
            }
        }
    }

    // ---- sounds: short cues from the freedesktop sound theme ----
    // (new notification, volume step, screenshot). Off switch in the control panel.
    property bool sounds: true
    readonly property string soundsFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/shell-sounds"
    function setSounds(on) { sounds = on; run("echo " + (on ? "on" : "off") + " > '" + soundsFile + "'") }
    FileView { path: sys.soundsFile; printErrors: false; onLoaded: sys.sounds = text().trim() !== "off" }
    property double lastSound: 0
    function sound(name) {
        if (!sounds) return
        const now = Date.now()
        if (now - lastSound < 250) return               // key repeat and bursts: not a machine gun
        lastSound = now
        run("pw-play --volume 0.45 '/usr/share/sounds/freedesktop/stereo/" + name.replace(/[^a-z0-9-]/g, "") + ".oga'")
    }

    // ---- keep awake (idle inhibitor), held by the bar windows ----
    property bool keepAwake: false

    // ---- tooltips: one at a time, shown by the bar the pointer is on ----
    property Item tipTarget: null
    property string tipText: ""
    property var tipWindow: null
}
