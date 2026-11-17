// Shared state for the animated wallpaper (Wallpaper.qml): which scene, which effects,
// and the live feeds the scenes react to (animation clock, sun, weather, music).
// Settings persist in ~/.local/state/wallpaper.json.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower
import "sky.js" as Sky
import "palettes.js" as Pal

Singleton {
    id: ws
    readonly property var scenes: ["silk", "aurora", "contours", "ink", "ridges", "sky", "terrain", "flow", "ripples", "field", "pulsar", "depths"]
    readonly property var effects: ["daylight", "music", "weather", "pointer", "agenda", "desks", "rest", "sharp", "heat", "season"]
    readonly property bool live: Quickshell.env("WALL_HARNESS") !== "1"     // off while rendering test frames
    readonly property alias cfg: store

    // ---- settings ----
    readonly property string stateFile: Quickshell.env("WALL_STATE")
        || (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/wallpaper.json"
    FileView {
        id: file
        path: ws.stateFile
        blockLoading: true
        blockWrites: true           // a change made while an unfinished write was in flight used to be undone when it landed
        printErrors: false
        onAdapterUpdated: saveSoon.restart()
        JsonAdapter {
            id: store
            property string scene: "silk"
            property bool running: true       // false: hold the current frame (no animation)
            property int fps: 20              // frames a second while moving
            property bool hidden: false       // true: no scene at all, hyprpaper is started and its plain image shows
            property real speed: 0.012        // flow units per second
            property bool daylight: true      // colours shift with the time of day
            property bool music: true         // scenes pulse with what is playing
            property bool weather: true       // rain, fog and snow drawn over the scene
            property bool pointer: true       // the scene leans toward the pointer
            property bool agenda: true        // today's events as a band along the bottom
            property bool desks: true         // each desktop is a different part of the scene
            property bool rest: true          // a screen with windows on it holds its frame (saves GPU)
            property bool pillbars: true      // live bars in the bar's music pill (needs the analyser while music plays)
            property bool heat: true          // hold the frame while the fan is busy, so the wallpaper never adds to fan noise
            property int fanMax: 3700         // rpm, averaged over two minutes: stop at this, start again at 80% of it
            property int heatCap: 88          // degrees C: stop at this whatever the fan does, start again 10 below
            property bool season: true        // seasonal touches: leaves, snow, petals, fireflies, the game-day paw (WallSeason.qml)
            property bool sharp: true         // Hyprland's blur is off while the wallpaper moves (saves GPU)
            property real lat: 34.6834        // Clemson, SC (as on the new-tab page)
            property real lng: -82.8374
        }
    }
    Timer { id: saveSoon; interval: 300; onTriggered: file.writeAdapter() }

    function setScene(name) { if (scenes.indexOf(name) >= 0) store.scene = name; return store.scene }
    function nextScene() { store.scene = scenes[(scenes.indexOf(store.scene) + 1) % scenes.length]; return store.scene }
    function setEffect(name, on) { if (effects.indexOf(name) >= 0 || name === "pillbars") store[name] = on }
    function status() {
        return (store.hidden ? "hidden" : store.running ? "on" : "still") + (moving || !store.running || store.hidden ? "" : hot ? " (still: fan busy, " + Math.round(fanAvg) + " rpm avg, " + Math.round(cpuTemp) + " C)" : " (still: on battery)")
            + " scene=" + store.scene + " speed=" + store.speed + " fps=" + store.fps
            + " " + effects.map(e => e + "=" + (store[e] ? "on" : "off")).join(" ")
            + " weather:" + (wxDemo || "auto") + " rain=" + wxRain.toFixed(2) + " fog=" + wxFog.toFixed(2) + " snow=" + wxSnow.toFixed(2)
            + " sun=" + sunAlt.toFixed(1) + "deg"
    }

    // ---- animation clock: counts only time spent moving, so it resumes where it froze ----
    // Moves on mains power only; on battery every scene holds its frame.
    // ---- heat guard: fan speed and CPU package temperature, read every 5 s while it matters ----
    // The temperature says little on this laptop: the fan switches on at about 72 C and off
    // at 69 C, so the CPU sits at 70 C whatever it is doing (measured 2026-11-12, docked: 70.4 C
    // with the wallpaper held, 70.9 C with it moving). What changes is how much the fan runs:
    // on about 60% of the time held, 80% moving, all the time under real load. So the guard
    // goes by the fan's average speed over two minutes (about 2700 rpm held, 3250 moving,
    // 3850 and up when it never gets to stop). It rests at fanMax and starts again at 80% of
    // it, a gap wider than what the wallpaper itself adds, so it cannot flip back and forth.
    // The temperature stays as a ceiling (heatCap) and is all there is on a machine without
    // a fan sensor.
    property real cpuTemp: 0
    property real fanAvg: 0                   // rpm over the last two minutes; 0 until there are 30 s of readings
    property bool fanKnown: false
    property var fanLog: []
    property bool hot: false
    readonly property int fanResume: Math.round(store.fanMax * 0.8)
    readonly property bool guarding: live && store.heat && store.running && !store.hidden && !UPower.onBattery
    onGuardingChanged: if (!guarding) { hot = false; fanLog = []; fanAvg = 0 }
    Process {
        id: tempGet
        command: ["sh", "-c", "for z in /sys/class/thermal/thermal_zone*; do [ \"$(cat $z/type)\" = x86_pkg_temp ] && echo t $(cat $z/temp) && break; done; echo f $(cat /sys/class/hwmon/hwmon*/fan1_input 2>/dev/null | head -1)"]
        stdout: StdioCollector {
            onStreamFinished: {
                const got = {}
                for (const line of text.split("\n")) { const w = line.trim().split(" "); if (w.length > 1) got[w[0]] = w[1] }
                const t = Number(got.t || 0) / 1000
                const rpm = got.f || ""
                if (t > 0) ws.cpuTemp = t
                ws.fanKnown = rpm !== ""
                if (ws.fanKnown) {
                    const log = ws.fanLog.concat([Number(rpm)]).slice(-24)
                    ws.fanLog = log
                    ws.fanAvg = log.length >= 6 ? log.reduce((a, b) => a + b, 0) / log.length : 0
                }
                const tooWarm = t >= store.heatCap
                const cooled = !(t > store.heatCap - 10)
                if (tooWarm || (ws.fanAvg > 0 && ws.fanAvg >= store.fanMax)) ws.hot = true
                else if (cooled && (!ws.fanKnown || (ws.fanAvg > 0 && ws.fanAvg <= ws.fanResume))) ws.hot = false
            }
        }
    }
    Timer {
        interval: 5000; repeat: true; triggeredOnStart: true
        running: ws.guarding
        onTriggered: if (!tempGet.running) tempGet.running = true
    }
    readonly property bool moving: live && store.running && !store.hidden && !UPower.onBattery && !(store.heat && hot)
    // Blur behind the bar, panels and translucent windows has to be redone on every screen
    // each time the wallpaper changes: about three quarters of Hyprland's GPU work while a
    // scene moves (38% -> 9% measured). So blur is switched off while moving, back on when still.
    readonly property bool blurOff: live && store.sharp && moving
    function applyBlur() {
        Sys.run("hyprctl eval 'hl.config({ decoration = { blur = { enabled = " + (blurOff ? "false" : "true") + " } } })'")
    }
    onBlurOffChanged: applyBlur()
    Connections {                             // a config reload turns blur back on: put it right
        target: Hyprland
        function onRawEvent(event) { if (event.name === "configreloaded" && ws.blurOff) ws.applyBlur() }
    }
    property real clock: (Date.now() / 1000) % 10800
    property real last: 0
    onMovingChanged: last = 0
    Timer {
        interval: Math.round(1000 / Math.max(2, Math.min(60, store.fps))); repeat: true; running: ws.moving
        onTriggered: {
            const now = Date.now() / 1000
            if (ws.last > 0) ws.clock = (ws.clock + Math.min(now - ws.last, 0.2)) % 10800
            ws.last = now
        }
    }

    // ---- the whole monitor layout, so scenes can be continuous across screens ----
    readonly property rect layoutBox: {
        let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
        for (const s of Quickshell.screens) {
            x0 = Math.min(x0, s.x); y0 = Math.min(y0, s.y)
            x1 = Math.max(x1, s.x + s.width); y1 = Math.max(y1, s.y + s.height)
        }
        return x1 > x0 ? Qt.rect(x0, y0, x1 - x0, y1 - y0) : Qt.rect(0, 0, 1920, 1080)
    }

    // ---- sun: altitude now, for the sky scenes and the time-of-day colours ----
    property var nowOverride: null            // a Date, for test frames
    function now() { return nowOverride || new Date() }
    property real sunAlt: -30                 // degrees
    property bool sunRising: false
    property real dayPhase: 0                 // 0 midnight .. 1
    readonly property real sunSin: Math.sin(sunAlt * Math.PI / 180)
    function refreshSun() {
        const d = now(), s = Sky.sunAltitude(d, store.lat, store.lng)
        sunAlt = s.alt; sunRising = s.rising
        dayPhase = (d.getHours() * 60 + d.getMinutes()) / 1440
    }
    onNowOverrideChanged: refreshSun()
    Timer { interval: 60000; repeat: true; running: ws.live; triggeredOnStart: true; onTriggered: ws.refreshSun() }
    Component.onCompleted: { refreshSun(); if (live) { applyBlur(); applyPaper() } }

    // ---- hyprpaper, the plain fallback image: runs only while the scene is hidden ----
    // Under a scene it is never seen, and it held a full-size image for every screen
    // (about 250 MiB of GPU memory on four screens, measured 2026-11-11).
    function applyPaper() {
        Sys.run(store.hidden ? "pgrep -x hyprpaper >/dev/null || exec uwsm app -- hyprpaper" : "pkill -x hyprpaper; true")       // no hyprpaper to stop is not a failure (run-logged)
    }
    Connections { target: store; function onHiddenChanged() { if (ws.live) ws.applyPaper() } }

    // time-of-day colour shift: warm near sunset (and a little at sunrise), cool in the
    // morning, a touch deeper at night
    function sstep(a, b, x) { const t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t) }
    readonly property real warmth: {
        if (!store.daylight) return 0
        const low = Math.max(0, 1 - Math.abs(sunAlt - 2) / 22), high = Math.max(0, Math.min(1, (sunAlt - 10) / 35))
        const night = sstep(-4, -14, sunAlt)
        return low * (sunRising ? 0.45 : 1.0) + high * (sunRising ? -0.45 : 0.25) - night * 0.35
    }
    readonly property real depth: store.daylight ? sstep(-4, -14, sunAlt) * 0.22 : 0

    // ---- palettes: in palettes.js, shared with the lock screen ----
    readonly property var palettes: Pal.palettes
    function mixc(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }
    // colour i of the scene, shifted for the time of day
    function tone(scene, dark, i) {
        let c = Qt.color((palettes[scene] || palettes.silk)[dark ? "dark" : "light"].c[i])
        const k = i === 4 ? 1 : i === 3 ? 0.5 : 0
        if (k > 0 && warmth > 0) c = mixc(c, Qt.color("#ffb347"), warmth * 0.45 * k)
        if (k > 0 && warmth < 0) c = mixc(c, Qt.color("#b8408c"), -warmth * 0.60 * k)
        return depth > 0 ? mixc(c, Qt.color("#000000"), depth) : c
    }
    function stops(scene, dark) {
        const s = (palettes[scene] || palettes.silk)[dark ? "dark" : "light"].s, d = -0.06 * warmth
        return Qt.vector4d(s[0] + d, s[1] + d, s[2] + d, 1.0)
    }

    // ---- weather: open-meteo, the same service and place as the new-tab page ----
    property string wxDemo: ""                // "", or rain | fog | snow | clear to force one
    property real rainNow: 0
    property real fogNow: 0
    property real snowNow: 0
    property real cloudNow: 0
    property real tempC: 15                   // outside temperature
    property bool stormNow: false
    property bool wxWanted: false             // someone else wants the feed kept fresh (the bar pet), wallpaper moving or not
    // one word for the weather outside, for things that react to it: rain | snow | fog | hot | cold | clear
    readonly property string wxKind: wxDemo !== "" ? wxDemo : rainNow > 0 ? "rain" : snowNow > 0 ? "snow" : fogNow > 0 ? "fog"
                                     : tempC >= 32 ? "hot" : tempC <= 0 ? "cold" : "clear"
    function pick(kind, real) { return !store.weather ? 0 : wxDemo === "" ? real : wxDemo === kind ? 0.8 : 0 }
    property real wxRain: pick("rain", rainNow)
    property real wxFog: pick("fog", fogNow)
    property real wxSnow: pick("snow", snowNow)
    property real wxCloud: store.weather ? cloudNow : 0
    property int wxFade: live ? 3000 : 0
    Behavior on wxRain { NumberAnimation { duration: ws.wxFade } }
    Behavior on wxFog { NumberAnimation { duration: ws.wxFade } }
    Behavior on wxSnow { NumberAnimation { duration: ws.wxFade } }
    function applyWeather(text) {
        try {
            const cur = JSON.parse(text).current, w = cur.weather_code
            tempC = cur.temperature_2m === undefined ? 15 : cur.temperature_2m
            stormNow = w >= 95
            cloudNow = (cur.cloud_cover || 0) / 100
            fogNow = (w === 45 || w === 48) ? 0.8 : 0
            snowNow = ((w >= 71 && w <= 77) || w === 85 || w === 86) ? 0.7 : 0
            rainNow = (w >= 51 && w <= 57) ? 0.35 : (w === 61 || w === 80) ? 0.5 : (w === 63 || w === 81 || w === 66) ? 0.7
                    : (w === 65 || w === 67 || w === 82 || w >= 95) ? 1.0 : 0
        } catch (e) { }                       // offline or a bad answer: keep what we had
    }
    Process {
        id: wxGet
        command: Sys.clean.concat(["curl", "-fsS", "--max-time", "10",
            "https://api.open-meteo.com/v1/forecast?latitude=" + store.lat.toFixed(2) + "&longitude=" + store.lng.toFixed(2)
            + "&current=weather_code,cloud_cover,temperature_2m"])
        stdout: StdioCollector { onStreamFinished: ws.applyWeather(text) }
    }
    Timer {
        interval: 20 * 60000; repeat: true; triggeredOnStart: true
        running: ws.live && ((store.running && store.weather) || ws.wxWanted)
        onTriggered: if (!wxGet.running) wxGet.running = true
    }

    // a picture of the focused screen's wallpaper, windows or not (qs ipc call wallpaper grab PATH)
    signal grabRequest(string path)

    // ---- season: what drifts over the scene at this time of year, and game days ----
    property string seasonDemo: ""            // "", or leaves | snow | petals | fireflies | none to force one
    property date seasonDay: new Date()
    Timer { interval: 3600000; repeat: true; running: ws.live && store.season; onTriggered: ws.seasonDay = new Date() }
    readonly property string seasonKind: {
        if (!store.season) return ""
        if (seasonDemo !== "") return seasonDemo === "none" ? "" : seasonDemo
        const md = (seasonDay.getMonth() + 1) * 100 + seasonDay.getDate()
        if (md >= 1015 && md <= 1130) return "leaves"
        if (md >= 1201 || md <= 228) return "snow"
        if (md >= 315 && md <= 430) return "petals"
        if (md >= 515 && md <= 831) return sunAlt < -4 ? "fireflies" : ""      // after dusk only
        return ""
    }
    property var game: null                   // today's Clemson football game, or null (~/.local/bin/gameday)
    property var gameNext: null
    property bool gameDemo: false             // show the paw as if the next game were today
    readonly property var gameShown: !store.season ? null : gameDemo ? (game || gameNext) : game
    Process {
        id: gameGet
        command: Sys.clean.concat([Sys.bin + "gameday"])
        stdout: StdioCollector {
            onStreamFinished: { try { const g = JSON.parse(text); ws.game = g.today || null; ws.gameNext = g.next || null } catch (e) {} }
        }
    }
    Timer {
        interval: 3 * 3600000; repeat: true; triggeredOnStart: true
        running: ws.live && store.season
        onTriggered: if (!gameGet.running) gameGet.running = true
    }

    // ---- music: cava's bars, only while something plays and the wallpaper is moving ----
    property real bass: 0
    property real mid: 0
    property real treble: 0
    property real level: 0
    Behavior on bass { NumberAnimation { duration: 120 } }
    Behavior on mid { NumberAnimation { duration: 120 } }
    Behavior on treble { NumberAnimation { duration: 120 } }
    Behavior on level { NumberAnimation { duration: 120 } }
    // five bands for the bar's music pill
    property var bands: [0, 0, 0, 0, 0]
    readonly property bool listening: live && Sys.player !== null && Sys.player.isPlaying
                                      && ((moving && store.music) || (store.pillbars && !UPower.onBattery))
    Process {
        id: cava
        running: ws.listening
        command: Sys.clean.concat(["cava", "-p", Qt.resolvedUrl("wallpaper-cava.conf").toString().replace("file://", "")])
        stdout: SplitParser {
            onRead: line => {
                const v = line.split(";").filter(x => x !== "").map(Number)
                if (v.length < 8) return
                ws.bass = (v[0] + v[1]) / 200; ws.mid = (v[2] + v[3] + v[4]) / 300; ws.treble = (v[5] + v[6] + v[7]) / 300
                ws.level = v.reduce((a, b) => a + b, 0) / 800
                ws.bands = [(v[0] + v[1]) / 200, v[2] / 100, (v[3] + v[4]) / 200, v[5] / 100, (v[6] + v[7]) / 200]
            }
        }
        onRunningChanged: if (!running) { ws.bass = 0; ws.mid = 0; ws.treble = 0; ws.level = 0; ws.bands = [0, 0, 0, 0, 0] }
    }

    // ---- palette follows the scene or the clock (`palette follow scene|time|off`); nothing runs while it is off ----
    property string paletteFollow: "off"
    FileView { path: Quickshell.env("HOME") + "/.config/palette/follow-mode"; watchChanges: true; printErrors: false
        onFileChanged: reload(); onLoaded: ws.paletteFollow = text().trim(); onLoadFailed: ws.paletteFollow = "off" }
    property var paletteTimes: []
    FileView { path: Quickshell.env("HOME") + "/.config/palette/follow.json"; watchChanges: ws.paletteFollow === "time"; printErrors: false
        onFileChanged: reload(); onLoaded: { try { ws.paletteTimes = (JSON.parse(text()).times || []).map(t => t[0]) } catch (e) { ws.paletteTimes = [] } } }
    function paletteApply() { Sys.run(Sys.bin + "palette follow apply >/dev/null 2>&1") }
    Timer { id: paletteSoon; interval: 5000; onTriggered: ws.paletteApply() }
    Connections { target: store; function onSceneChanged() { if (ws.live && ws.paletteFollow === "scene") paletteSoon.restart() } }
    Timer { interval: 60000; repeat: true; running: ws.live && ws.paletteFollow === "time"
        onTriggered: if (ws.paletteTimes.indexOf(Qt.formatTime(new Date(), "HH:mm")) >= 0) ws.paletteApply() }
}
