// Tests for the bar's popups and the small panel pieces (qml-panels-test): Mixer, WifiList,
// BluetoothList, TeamsList, MediaCard, MediaPop, PowerMenu, BatteryWarn, ProfileList, WallMenu,
// MsgIcon, Slider, ScriptSource, and an "every Settings page loads" pass. NOT part of the shell:
// ~/.local/bin/qml-panels-test copies the real files next to these stubs (Mixer, BluetoothList and
// BatteryWarn without their Quickshell.Services imports, which the stubs here stand in for; WallMenu
// as a plain window) and runs it offscreen on a 1920x1080 screen. Every popup sits in a window drawn
// like Bar.qml's PopupWindow (its width per popup, 16 px padding) and is checked with the real Fit.qml
// in dark and light. Calls are recorded by the stubs (Sys.run never runs anything); nmcli and the
// scripts in $PANELS_BIN are stand-ins. Lines: STEST PASS/FAIL ..., last "STEST RESULT pass N fail M".
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "pwnodetype.js" as PwStub

ShellRoot {
    id: root
    property int passed: 0
    property int failed: 0
    function check(what, ok, detail) {
        if (ok) passed++; else failed++
        console.log("STEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
    }
    function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: Quickshell.env("PANELS_DIR")          // fixtures and stub logs
    readonly property string bin: Quickshell.env("PANELS_BIN")
    readonly property var pageFiles: (Quickshell.env("PANELS_PAGES") || "").split(" ").filter(s => s !== "")

    TestEvent { id: ev }
    Fit { id: fit }

    // ---- files ----
    FileView { id: hand; printErrors: false; blockLoading: true; blockWrites: true }
    function readFile(path) { hand.path = ""; hand.path = path; try { return hand.text() || "" } catch (e) { return "" } }
    function writeFile(path, s) { hand.path = path; hand.setText(s) }
    function setDark(d) { writeFile(home + "/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark", d ? "true\n" : "false\n"); Theme.reload() }

    // ---- finding things ----
    function findAll(it, pred, out) {
        out = out || []
        if (!it) return out
        if (pred(it)) out.push(it)
        const k = it.children || []
        for (let i = 0; i < k.length; i++) findAll(k[i], pred, out)
        return out
    }
    function isText(o) { return !!o && o.elide !== undefined && o.truncated !== undefined && o.text !== undefined }
    function texts(it) { return findAll(it, o => isText(o) && o.visible && String(o.text) !== "").map(o => String(o.text)) }
    function textItem(it, s) { return findAll(it, o => isText(o) && o.visible && String(o.text) === s)[0] || null }
    function has(it, s) { return textItem(it, s) !== null }
    function rows(it) { return findAll(it, o => o.visible && o.danger !== undefined && o.detail !== undefined && o.label !== undefined) }
    function row(it, label) { return rows(it).find(r => r.label === label) || null }
    function labels(it) { return rows(it).map(r => r.label) }
    function sliders(it) { return findAll(it, o => o.visible && o.off !== undefined && o.value !== undefined && typeof o.rightClicked === "function") }
    function click(item, button, fx, fy) {
        if (!item) { check("click target exists", false, "null"); return }
        const w = item.Window.window
        if (w && !w.active) w.requestActivate()
        const p = item.mapToItem(null, (fx === undefined ? 0.5 : fx) * item.width, (fy === undefined ? 0.5 : fy) * item.height)
        ev.mouseClick(w, p.x, p.y, button || Qt.LeftButton, Qt.NoModifier, -1)
    }
    function clickText(it, s, button) { const t = textItem(it, s); if (!t) { check("text to click: " + s, false, texts(it).join(" | ")); return } click(t, button) }
    function last(list) { return list.length ? list[list.length - 1] : "" }
    function near(a, b) { return Math.abs(a - b) < 0.03 }

    // ---- a popup window, as Bar.qml's PopupWindow draws one ----
    property var w: null
    readonly property var pop: w ? w.item : null
    Component {
        id: popComp
        FloatingWindow {
            id: pw
            property int bodyWidth: 300
            property Component body
            property int doneCount: 0
            readonly property var item: ld.item
            visible: true
            color: "transparent"
            implicitWidth: bodyWidth + 32
            implicitHeight: ld.implicitHeight + 32 + 8
            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 8
                radius: 12
                color: Theme.panelBg
                border.width: 2
                border.color: Theme.accentBg
                Loader {
                    id: ld
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                    sourceComponent: pw.body
                }
            }
            Connections { target: ld.item; ignoreUnknownSignals: true; function onDone() { pw.doneCount++ } }
        }
    }
    function open(comp, width) {
        if (w) w.destroy()
        w = popComp.createObject(root, { body: comp, bodyWidth: width })
        Sys.reset()
        return w
    }
    // pin the window to its content's size (a shown FloatingWindow keeps its first size otherwise)
    function lock(win) {
        const q = Qt.size(Math.ceil(win.implicitWidth), Math.ceil(win.implicitHeight))
        win.maximumSize = Qt.size(9999, 9999); win.minimumSize = q; win.maximumSize = q
    }
    function fitProblems(win, tag) {
        fit.roots = [win]
        const r = fit.checkNow(tag)
        return r.problems.concat(r.windows.length ? [] : ["window not seen by the check"])
    }
    // three cases: pin the size, check it fits in dark, switch to light and check again
    function fitCases(label, getWin) {
        return [
            { name: label + ": fit (dark)", run: function() { lock(getWin()); return 200 } },
            { name: label + ": fit (dark) check", run: function() {
                const p = fitProblems(getWin(), label)
                check(label + ": nothing cut off (dark)", p.length === 0, p.join(" || "))
                setDark(false); return 400
            } },
            { name: label + ": fit (light)", run: function() {
                check(label + ": light theme is on", !Theme.dark)
                lock(getWin()); return 200
            } },
            { name: label + ": fit (light) check", run: function() {
                const p = fitProblems(getWin(), label)
                check(label + ": nothing cut off (light)", p.length === 0, p.join(" || "))
                setDark(true); return 400
            } }
        ]
    }

    // ---- stand-in data ----
    Component { id: audioC; QtObject { property real volume: 0.5; property bool muted: false } }
    Component {
        id: nodeC
        QtObject {
            property int id; property string name; property string description; property string nickname
            property bool isStream: false; property bool isSink: false; property int type: 0
            property var properties: ({}); property var audio: null
        }
    }
    function node(o) {
        const n = nodeC.createObject(root, { id: o.id, name: o.name || ("node" + o.id), description: o.description || "", isStream: !!o.isStream,
                                             isSink: !!o.isSink, type: o.type || 0, properties: o.properties || {} })
        n.audio = audioC.createObject(n, { volume: o.volume === undefined ? 0.5 : o.volume })
        return n
    }
    property var nodes: ({})
    function pipewireData() {
        const N = {
            speakers: node({ id: 1, description: "Laptop speakers", isSink: true, type: PwStub.AudioSink, volume: 0.9 }),
            buds:     node({ id: 2, description: "MOMENTUM 4", isSink: true, type: PwStub.AudioSink, volume: 0.4 }),
            firefox:  node({ id: 10, isStream: true, isSink: true, type: PwStub.AudioOutStream, properties: { "application.name": "Firefox" }, volume: 0.6 }),
            speech:   node({ id: 11, isStream: true, isSink: true, type: PwStub.AudioOutStream, properties: { "application.name": "speech-dispatcher-dummy" } }),
            zoomIn:   node({ id: 12, isStream: true, type: PwStub.AudioInStream, properties: { "application.name": "Zoom mic" } }),
            mic:      node({ id: 20, description: "Built-in mic", type: PwStub.AudioSource, volume: 0.7 }),
            budsMic:  node({ id: 21, description: "MOMENTUM 4 mic", type: PwStub.AudioSource })
        }
        nodes = N
        Pipewire.nodes.values = Object.values(N)
        Pipewire.preferredDefaultAudioSink = null; Pipewire.preferredDefaultAudioSource = null
        Sys.sink = N.buds; Sys.source = N.mic
    }

    Component {
        id: playerC
        QtObject {
            property string identity: "Music Player Daemon"
            property string dbusName: "org.mpris.MediaPlayer2.mpd"
            property string desktopEntry: ""
            property string trackTitle: "A fairly long track title that has to wrap onto a second line here"
            property string trackArtist: "Some Artist"
            property string trackAlbum: "The Album"
            property string trackArtUrl: ""
            property bool isPlaying: true
            property bool canGoPrevious: true
            property bool canGoNext: true
            property bool canTogglePlaying: true
            property bool canSeek: true
            property bool canControl: true
            property bool lengthSupported: true
            property real length: 200
            property real position: 65
            property bool volumeSupported: true
            property real volume: 0.5
            property var calls: []
            function previous() { calls = calls.concat(["previous"]) }
            function next() { calls = calls.concat(["next"]) }
            function togglePlaying() { calls = calls.concat(["togglePlaying"]) }
        }
    }

    property var btLog: []
    Component { id: adapterC; QtObject { property bool enabled: true; readonly property QtObject devices: QtObject { property var values: [] } } }
    Component {
        id: devC
        QtObject {
            property string name; property string address; property string icon: ""
            property bool paired: true; property bool connected: false
            property bool batteryAvailable: false; property real battery: 0
            function connect() { root.btLog = root.btLog.concat(["connect " + name]) }
            function disconnect() { root.btLog = root.btLog.concat(["disconnect " + name]) }
        }
    }
    function btData() {
        const a = adapterC.createObject(root)
        a.devices.values = [
            devC.createObject(a, { name: "MOMENTUM 4", address: "80:C3:BA:00:00:01", paired: true }),
            devC.createObject(a, { name: "Pixel Buds Pro 2", address: "AC:3E:B1:00:00:02", connected: true, batteryAvailable: true, battery: 0.8, icon: "audio-headset" }),
            devC.createObject(a, { name: "Somebody's speaker", address: "11:22:33:00:00:F4", paired: false })
        ]
        Bluetooth.defaultAdapter = a
        btLog = []
        return a
    }

    // ---- the popups ----
    Component { id: mixerC; Mixer {} }
    Component { id: wifiC; WifiList {} }
    Component { id: btC; BluetoothList {} }
    Component { id: teamsC; TeamsList {} }
    Component { id: mediaPopC; MediaPop {} }
    Component { id: mediaCardC; MediaCard {} }
    Component { id: powerC; PowerMenu {} }
    Component { id: profileC; ProfileList {} }
    Component { id: battC; BatteryWarn {} }
    property var batt: null

    WallMenu { id: wallMenu }

    // MsgIcon and Slider in a window of their own
    property var sliderLog: []
    FloatingWindow {
        id: bits
        visible: false
        implicitWidth: 320; implicitHeight: 160
        color: Theme.solidBg
        Row {
            x: 10; y: 10; spacing: 10
            MsgIcon { id: iconArt }
            MsgIcon { id: iconMissing }
            MsgIcon { id: iconGlyph }
            MsgIcon { id: iconApp }
            MsgIcon { id: iconEmpty }
        }
        Slider {
            id: slider
            x: 20; y: 100; width: 200
            value: 0.5
            onMoved: v => root.sliderLog = root.sliderLog.concat(["moved " + v.toFixed(2)])
            onRightClicked: root.sliderLog = root.sliderLog.concat(["right"])
        }
    }

    // ScriptSource instances
    ScriptSource { id: ssFile; active: false; exec: "cat '" + root.dir + "/ss.out'" }
    ScriptSource { id: ssTick; active: false; interval: 150; exec: "echo x >> '" + root.dir + "/ss.ticks'; echo '{\"text\":\"t\"}'" }

    // ---- Settings pages ----
    QtObject {
        id: winStub
        property bool visible: true
        property string page: ""
        readonly property var pages: []
        readonly property int pageIndex: 0
        readonly property var island: QtObject { property bool enabled: true; function say(o) {} function setEnabled(on) { enabled = on } }
        readonly property var launcherView: QtObject { readonly property var modes: [{ id: "apps", prefix: "" }, { id: "calc", prefix: "=", hint: "Calculate" }]; function close() {} }
        readonly property var cursorFind: QtObject { property bool enabled: true }
        readonly property var dropPreview: QtObject { property bool enabled: true }
        readonly property var identify: QtObject { function flash() {} }
    }
    Component {
        id: pageWinC
        FloatingWindow { visible: true; implicitWidth: 760; implicitHeight: 900; color: Theme.solidBg }
    }
    property var pageWins: []
    property var pageObjs: ({})

    property var cases: [
        // ================= Mixer =================
        { name: "Mixer: two outputs, apps, two mics", run: function() {
            pipewireData()
            open(mixerC, 300)
            return 300
        } },
        { name: "Mixer: rows", run: function() {
            const t = texts(pop)
            check("Mixer: both outputs listed", has(pop, "Laptop speakers") && has(pop, "MOMENTUM 4"), t.join(" | "))
            const cur = textItem(pop, "MOMENTUM 4"), other = textItem(pop, "Laptop speakers")
            check("Mixer: the default output is marked", cur && cur.parent.current === true && other && other.parent.current === false)
            check("Mixer: output level shown", has(pop, "40%"), t.join(" | "))
            check("Mixer: playing app listed with its level", has(pop, "Firefox") && has(pop, "60%"))
            check("Mixer: speech-dispatcher placeholder hidden", t.every(s => s.indexOf("speech-dispatcher") < 0))
            check("Mixer: a recording stream is not an app", !has(pop, "Zoom mic"))
            check("Mixer: both microphones listed", has(pop, "Built-in mic") && has(pop, "MOMENTUM 4 mic"))
            check("Mixer: microphone level shown", has(pop, "70%"))
            check("Mixer: three level bars (output, app, mic)", sliders(pop).length === 3, sliders(pop).length)
            clickText(pop, "Laptop speakers")
            return 100
        } },
        { name: "Mixer: clicks", run: function() {
            check("Mixer: click an output makes it the default", Pipewire.preferredDefaultAudioSink === nodes.speakers, String(Pipewire.preferredDefaultAudioSink))
            clickText(pop, "MOMENTUM 4 mic")
            check("Mixer: click a mic makes it the default", Pipewire.preferredDefaultAudioSource === nodes.budsMic)
            const s = sliders(pop)
            click(s[0], Qt.RightButton)
            check("Mixer: right-click the level mutes the output", nodes.buds.audio.muted === true)
            check("Mixer: muted shown", has(pop, "muted"))
            click(s[0], Qt.RightButton)
            check("Mixer: right-click again unmutes", nodes.buds.audio.muted === false)
            click(s[0], Qt.LeftButton, 0.25)
            check("Mixer: click the bar sets the output level", near(nodes.buds.audio.volume, 0.25), nodes.buds.audio.volume)
            click(s[1], Qt.LeftButton, 0.75)
            check("Mixer: the app's bar sets the app's level", near(nodes.firefox.audio.volume, 0.75) && near(nodes.buds.audio.volume, 0.25), nodes.firefox.audio.volume)
            click(s[1], Qt.RightButton)
            check("Mixer: right-click the app's bar mutes the app only", nodes.firefox.audio.muted && !nodes.buds.audio.muted)
            click(s[2], Qt.LeftButton, 0.5)
            check("Mixer: the mic bar sets the mic level", near(nodes.mic.audio.volume, 0.5), nodes.mic.audio.volume)
            check("Mixer: nothing run through Sys", Sys.calls.length === 0, Sys.calls.join("; "))
            nodes.firefox.audio.muted = false
            return 100
        } },
    ].concat(fitCases("Mixer", () => root.w)).concat([
        { name: "Mixer: one mic, no apps", run: function() {
            Pipewire.nodes.values = [nodes.speakers, nodes.buds, nodes.mic]
            return 100
        } },
        { name: "Mixer: one mic, no apps check", run: function() {
            check("Mixer: no Apps heading without apps", !has(pop, "Apps"))
            check("Mixer: a single mic is named beside its level, not listed", has(pop, "Built-in mic") && sliders(pop).length === 2, texts(pop).join(" | "))
            Pipewire.nodes.values = []; Sys.sink = null; Sys.source = null
            return 100
        } },
        { name: "Mixer: empty", run: function() {
            check("Mixer: no output says so", has(pop, "no output"), texts(pop).join(" | "))
            check("Mixer: no Microphone heading", !has(pop, "Microphone"))
            const s = sliders(pop)
            check("Mixer: only the output bar, at 0", s.length === 1 && s[0].value === 0, s.length)
            click(s[0], Qt.RightButton); click(s[0], Qt.LeftButton, 0.5)
            check("Mixer: clicking the bar with no output does nothing (no error)", true)
            return 100
        } },
    ]).concat(fitCases("Mixer (empty)", () => root.w)).concat([

        // ================= WifiList =================
        { name: "Wi-Fi: scan", run: function() {
            writeFile(dir + "/nmcli.out", "*:72:WPA2:Torus Shaped Earth\n :55:WPA2 802.1X:eduroam\n :80:WPA2 802.1X:eduroam\n :30::Cafe\\:Guest\n :90:WPA2:\n :41:WPA2:Tim's Phone\n")
            writeFile(dir + "/nmcli.log", "")
            Sys.netKind = "wifi"; Sys.netName = "Torus Shaped Earth"
            open(wifiC, 300)
            return 700
        } },
        { name: "Wi-Fi: rows", run: function() {
            const log = readFile(dir + "/nmcli.log")
            check("Wi-Fi: listed with nmcli, no rescan on open", /-t -f IN-USE,SIGNAL,SECURITY,SSID dev wifi list --rescan no/.test(log), log)
            const L = labels(pop)
            check("Wi-Fi: four networks, connected first, then by signal; duplicate and blank SSIDs dropped",
                  same(L.slice(0, 4), ["Torus Shaped Earth", "eduroam", "Tim's Phone", "Cafe:Guest"]), L.join(" | "))
            check("Wi-Fi: the connected one is marked", row(pop, "Torus Shaped Earth").current && !row(pop, "eduroam").current)
            check("Wi-Fi: strongest of a duplicate kept, locked shown", row(pop, "eduroam").detail === "locked  80%", row(pop, "eduroam").detail)
            check("Wi-Fi: open network has no lock", row(pop, "Cafe:Guest").detail === "30%", row(pop, "Cafe:Guest").detail)
            check("Wi-Fi: QR row offered on Wi-Fi", row(pop, "Share via QR") !== null)
            check("Wi-Fi: not scanning any more", has(pop, "Wi-Fi") && !has(pop, "No networks found"))
            click(row(pop, "eduroam"))
            return 100
        } },
        { name: "Wi-Fi: clicks", run: function() {
            check("Wi-Fi: click a network connects, wifi-menu as the fallback", last(Sys.calls) === "run nmcli -w 20 dev wifi connect 'eduroam' || " + bin + "/wifi-menu", last(Sys.calls))
            check("Wi-Fi: and closes the popup", w.doneCount === 1, w.doneCount)
            click(row(pop, "Tim's Phone"))
            check("Wi-Fi: a quote in the name is shell-quoted", last(Sys.calls) === "run nmcli -w 20 dev wifi connect 'Tim'\\''s Phone' || " + bin + "/wifi-menu", last(Sys.calls))
            const n = Sys.calls.length
            click(row(pop, "Torus Shaped Earth"))
            check("Wi-Fi: click the connected one only closes", Sys.calls.length === n && w.doneCount === 3, Sys.calls.join("; "))
            click(row(pop, "More options…"))
            check("Wi-Fi: More options runs wifi-menu", last(Sys.calls) === "run " + bin + "/wifi-menu" && w.doneCount === 4, last(Sys.calls))
            click(row(pop, "Connection settings"))
            check("Wi-Fi: Connection settings runs nm-connection-editor", last(Sys.calls) === "run nm-connection-editor" && w.doneCount === 5, last(Sys.calls))
            writeFile(dir + "/nmcli.log", "")
            clickText(pop, "Rescan")
            return 700
        } },
        { name: "Wi-Fi: rescan and QR", run: function() {
            check("Wi-Fi: Rescan asks nmcli to rescan", /--rescan yes/.test(readFile(dir + "/nmcli.log")), readFile(dir + "/nmcli.log"))
            check("Wi-Fi: rows still there after the rescan", labels(pop).indexOf("eduroam") >= 0)
            click(row(pop, "Share via QR"))
            return 600
        } },
        { name: "Wi-Fi: QR shown", run: function() {
            check("Wi-Fi: QR caption names the network", has(pop, "Scan to join Torus Shaped Earth"), texts(pop).join(" | "))
            const te = findAll(pop, o => o.visible && o.selectByMouse !== undefined && o.readOnly === true)[0]
            check("Wi-Fi: password shown, selectable", te && te.text === "hunter2 secret", te ? te.text : "none")
            const img = findAll(pop, o => o.visible && o.fillMode !== undefined && o.status !== undefined && String(o.source).indexOf("qr.png") >= 0)[0]
            check("Wi-Fi: QR picture loaded", img && img.status === Image.Ready, img ? img.status + " " + img.source : "none")
            check("Wi-Fi: row now says Hide QR", row(pop, "Hide QR") !== null)
            check("Wi-Fi: QR does not close the popup", w.doneCount === 5)
            return 100
        } },
    ]).concat(fitCases("Wi-Fi (with QR)", () => root.w)).concat([
        { name: "Wi-Fi: hide QR, wired", run: function() {
            click(row(pop, "Hide QR"))
            check("Wi-Fi: Hide QR hides it", !has(pop, "Scan to join Torus Shaped Earth") && row(pop, "Share via QR") !== null)
            Sys.netKind = "wired"
            check("Wi-Fi: no QR row on a wired connection", row(pop, "Share via QR") === null)
            writeFile(dir + "/nmcli.out", "")
            open(wifiC, 300)
            return 700
        } },
        { name: "Wi-Fi: nothing found", run: function() {
            check("Wi-Fi: empty list says so", has(pop, "No networks found"), texts(pop).join(" | "))
            check("Wi-Fi: only the two fixed rows", same(labels(pop), ["More options…", "Connection settings"]), labels(pop).join(" | "))
            return 100
        } },
    ]).concat(fitCases("Wi-Fi (empty)", () => root.w)).concat([
        { name: "Wi-Fi: long names", run: function() {
            writeFile(dir + "/nmcli.out", "*:99:WPA3:A very long network name that goes on and on past the edge\n :12:WPA2:x\n")
            Sys.netKind = "wifi"
            open(wifiC, 300)
            return 700
        } },
    ]).concat(fitCases("Wi-Fi (long SSID)", () => root.w)).concat([

        // ================= BluetoothList =================
        { name: "Bluetooth: a connected and a paired device", run: function() {
            btData()
            open(btC, 300)
            return 200
        } },
        { name: "Bluetooth: rows and clicks", run: function() {
            const L = labels(pop)
            check("Bluetooth: connected first, then paired; unpaired left out", same(L, ["Pixel Buds Pro 2", "MOMENTUM 4", "Bluetooth manager…"]), L.join(" | "))
            check("Bluetooth: connected marked, with battery", row(pop, "Pixel Buds Pro 2").current && row(pop, "Pixel Buds Pro 2").detail === "connected  80%", row(pop, "Pixel Buds Pro 2").detail)
            check("Bluetooth: paired one not marked, no detail", !row(pop, "MOMENTUM 4").current && row(pop, "MOMENTUM 4").detail === "")
            check("Bluetooth: Turn off offered", has(pop, "Turn off"))
            click(row(pop, "MOMENTUM 4"))
            check("Bluetooth: click a paired device connects it", last(btLog) === "connect MOMENTUM 4", btLog.join("; "))
            click(row(pop, "Pixel Buds Pro 2"))
            check("Bluetooth: click the connected device disconnects it", last(btLog) === "disconnect Pixel Buds Pro 2", btLog.join("; "))
            check("Bluetooth: device clicks keep the popup open", w.doneCount === 0)
            click(row(pop, "Bluetooth manager…"))
            check("Bluetooth: manager row runs blueman-manager and closes", last(Sys.calls) === "run blueman-manager" && w.doneCount === 1, Sys.calls.join("; "))
            return 100
        } },
    ]).concat(fitCases("Bluetooth", () => root.w)).concat([
        { name: "Bluetooth: turn off", run: function() {
            clickText(pop, "Turn off")
            check("Bluetooth: Turn off switches the adapter off", Bluetooth.defaultAdapter.enabled === false)
            return 100
        } },
        { name: "Bluetooth: off", run: function() {
            check("Bluetooth: off says so, no devices", has(pop, "Bluetooth is off") && same(labels(pop), ["Bluetooth manager…"]), labels(pop).join(" | "))
            check("Bluetooth: Turn on offered", has(pop, "Turn on"))
            clickText(pop, "Turn on")
            check("Bluetooth: Turn on switches it back", Bluetooth.defaultAdapter.enabled === true)
            Bluetooth.defaultAdapter.devices.values = []
            return 100
        } },
        { name: "Bluetooth: none paired", run: function() {
            check("Bluetooth: no paired devices leaves only the manager row", same(labels(pop), ["Bluetooth manager…"]), labels(pop).join(" | "))
            Bluetooth.defaultAdapter = null
            return 100
        } },
        { name: "Bluetooth: no adapter", run: function() {
            check("Bluetooth: no adapter says so", has(pop, "No Bluetooth adapter"), texts(pop).join(" | "))
            check("Bluetooth: no Turn on/off without an adapter", !has(pop, "Turn on") && !has(pop, "Turn off"))
            return 100
        } },
    ]).concat(fitCases("Bluetooth (no adapter)", () => root.w)).concat([

        // ================= TeamsList =================
        { name: "Teams: two chats", run: function() {
            Sys.teams.data = { text: "4", rooms: [
                { id: "!ops:local", name: "Ops channel with a rather long name that must elide", count: 3, mentions: 1, preview: "Tim, can you look at the build that broke this morning?" },
                { id: "!gen:local", name: "General", count: 1, mentions: 0, preview: "" }
            ] }
            open(teamsC, 340)
            return 200
        } },
        { name: "Teams: rows and clicks", run: function() {
            check("Teams: heading says unread", has(pop, "Teams: unread"))
            check("Teams: both chats listed", has(pop, "Ops channel with a rather long name that must elide") && has(pop, "General"), texts(pop).join(" | "))
            check("Teams: a mention shows @ and the count", has(pop, "@ 3") && has(pop, "1"))
            check("Teams: preview shown when there is one", has(pop, "Tim, can you look at the build that broke this morning?"))
            clickText(pop, "General")
            check("Teams: click a chat opens it", last(Sys.calls) === "teamsOpen !gen:local" && w.doneCount === 1, Sys.calls.join("; "))
            clickText(pop, "Ops channel with a rather long name that must elide")
            check("Teams: click the other chat opens that one", last(Sys.calls) === "teamsOpen !ops:local", Sys.calls.join("; "))
            click(row(pop, "All chats in Emacs"))
            check("Teams: All chats runs the list", last(Sys.calls) === "teamsList" && w.doneCount === 3, Sys.calls.join("; "))
            return 100
        } },
    ]).concat(fitCases("Teams", () => root.w)).concat([
        { name: "Teams: nothing unread", run: function() {
            Sys.teams.data = {}
            return 100
        } },
        { name: "Teams: empty", run: function() {
            check("Teams: empty says nothing unread", has(pop, "Teams: nothing unread"), texts(pop).join(" | "))
            check("Teams: only the Emacs row", same(labels(pop), ["All chats in Emacs"]), labels(pop).join(" | "))
            return 100
        } },

        // ================= MediaCard / MediaPop =================
        { name: "Media: a player", run: function() {
            const mpd = playerC.createObject(root)
            const ff = playerC.createObject(root, { identity: "Firefox", trackTitle: "Some video", isPlaying: false, dbusName: "org.mpris.MediaPlayer2.firefox" })
            Sys.realPlayers = [mpd, ff]; Sys.player = mpd; Sys.playerPin = ""
            open(mediaCardC, 300)
            return 200
        } },
        { name: "MediaCard: shown and buttons", run: function() {
            const p = Sys.player
            check("MediaCard: shown with a track", pop.visible === true)
            check("MediaCard: title and artist", has(pop, p.trackTitle) && has(pop, "Some Artist"))
            check("MediaCard: play/pause shows pause while playing", has(pop, Icons.paused))
            clickText(pop, "◀◀"); clickText(pop, Icons.paused); clickText(pop, "▶▶")
            check("MediaCard: previous, play/pause, next", same(p.calls, ["previous", "togglePlaying", "next"]), p.calls.join(","))
            p.canGoNext = false
            clickText(pop, "▶▶")
            check("MediaCard: next not called when the player can't", same(p.calls, ["previous", "togglePlaying", "next"]), p.calls.join(","))
            p.canGoNext = true
            check("MediaCard: no art shows the glyph", has(pop, Icons.playerDefault))
            return 100
        } },
    ]).concat(fitCases("MediaCard", () => root.w)).concat([
        { name: "MediaCard: nothing playing", run: function() {
            Sys.player.trackTitle = ""
            check("MediaCard: hidden with no title", pop.visible === false)
            const keep = Sys.player
            Sys.player = null
            check("MediaCard: hidden with no player", pop.visible === false)
            Sys.player = keep; keep.trackTitle = "A fairly long track title that has to wrap onto a second line here"
            open(mediaPopC, 320)
            return 200
        } },
        { name: "MediaPop: shown and clicks", run: function() {
            const p = Sys.player
            p.calls = []
            check("MediaPop: title, artist, album", has(pop, p.trackTitle) && has(pop, "Some Artist") && has(pop, "The Album"))
            check("MediaPop: position and length", has(pop, "1:05") && has(pop, "3:20"), texts(pop).join(" | "))
            check("MediaPop: player volume row", has(pop, "Music Player Daemon volume") && has(pop, "50%"))
            const s = sliders(pop)
            check("MediaPop: seek and volume bars", s.length === 2, s.length)
            click(s[0], Qt.LeftButton, 0.5)
            check("MediaPop: click the seek bar seeks", Math.abs(p.position - 100) < 5, p.position)
            p.canSeek = false; click(s[0], Qt.LeftButton, 0.9)
            check("MediaPop: no seek when the player can't", Math.abs(p.position - 100) < 5, p.position)
            click(s[1], Qt.LeftButton, 0.3)
            check("MediaPop: the volume bar sets the player's volume", near(p.volume, 0.3), p.volume)
            clickText(pop, "◀◀"); clickText(pop, Icons.paused); clickText(pop, "▶▶")
            check("MediaPop: previous, play/pause, next", same(p.calls, ["previous", "togglePlaying", "next"]), p.calls.join(","))
            clickText(pop, "Live bars in the pill: on")
            check("MediaPop: live bars switch", last(WallState.calls) === "setEffect pillbars false" && has(pop, "Live bars in the pill: off"), WallState.calls.join("; "))
            check("MediaPop: Follow chips with two players", has(pop, "Follow") && has(pop, "Automatic") && has(pop, "Firefox"))
            clickText(pop, "Firefox")
            check("MediaPop: a chip pins that player", Sys.playerPin === "Firefox", Sys.playerPin)
            clickText(pop, "Automatic")
            check("MediaPop: Automatic unpins", Sys.playerPin === "")
            check("MediaPop: nothing run through Sys", Sys.calls.length === 0, Sys.calls.join("; "))
            return 100
        } },
    ]).concat(fitCases("MediaPop", () => root.w)).concat([
        { name: "MediaPop: nothing playing", run: function() {
            Sys.realPlayers = []; Sys.player = null
            return 100
        } },
        { name: "MediaPop: empty", run: function() {
            check("MediaPop: says Nothing playing", has(pop, "Nothing playing"), texts(pop).join(" | "))
            check("MediaPop: no bars, no Follow", sliders(pop).length === 0 && !has(pop, "Follow"), sliders(pop).length)
            clickText(pop, Icons.playing)
            check("MediaPop: play with no player does nothing (no error)", true)
            return 100
        } },
    ]).concat(fitCases("MediaPop (empty)", () => root.w)).concat([

        // ================= PowerMenu =================
        { name: "Power menu", run: function() {
            open(powerC, 220)
            return 150
        } },
        { name: "Power menu: rows and clicks", run: function() {
            check("Power: five rows", same(labels(pop), ["Lock", "Suspend", "Log out", "Reboot", "Shut down"]), labels(pop).join(" | "))
            click(row(pop, "Lock"))
            check("Power: Lock runs lock-now at once", last(Sys.calls) === "run $HOME/.local/bin/lock-now" && w.doneCount === 1, Sys.calls.join("; "))
            click(row(pop, "Suspend"))
            check("Power: Suspend at once", last(Sys.calls) === "run systemctl suspend" && w.doneCount === 2, Sys.calls.join("; "))
            const n = Sys.calls.length
            click(row(pop, "Shut down"))
            check("Power: Shut down asks first", Sys.calls.length === n && row(pop, "Click again to shut down") !== null && row(pop, "Click again to shut down").danger, labels(pop).join(" | "))
            click(row(pop, "Reboot"))
            check("Power: arming another moves the question", Sys.calls.length === n && row(pop, "Click again to reboot") !== null && row(pop, "Shut down") !== null)
            click(row(pop, "Click again to reboot"))
            check("Power: second click reboots, after saving the session", last(Sys.calls) === "run $HOME/.local/bin/session-save --if-enabled; systemctl reboot" && w.doneCount === 3, last(Sys.calls))
            return 100
        } },
        { name: "Power menu: arm Log out", run: function() {
            click(row(pop, "Log out"))
            check("Power: Log out armed", row(pop, "Click again to log out") !== null)
            return 100
        } },
    ]).concat(fitCases("Power menu (armed)", () => root.w)).concat([
        { name: "Power menu: log out", run: function() {
            click(row(pop, "Click again to log out"))
            check("Power: Log out on the second click", last(Sys.calls) === "run $HOME/.local/bin/session-save --if-enabled; uwsm stop", last(Sys.calls))
            click(row(pop, "Shut down")); click(row(pop, "Click again to shut down"))
            check("Power: Shut down on the second click", last(Sys.calls) === "run $HOME/.local/bin/session-save --if-enabled; systemctl poweroff", last(Sys.calls))
            return 100
        } },

        // ================= ProfileList =================
        { name: "Profiles", run: function() {
            Sys.profileCls = "balanced"
            Charge.profile = "balanced"; Charge.end = 90; Charge.loaded = true; Charge.calls = []
            open(profileC, 220)
            return 150
        } },
        { name: "Profiles: rows and clicks", run: function() {
            const L = labels(pop)
            check("Profiles: three profiles, the cap, the limit in force, full", same(L, ["Battery", "Balanced", "Performance", "Stop at 80%", "Balanced (stops at 90%)", "Full charge"]), L.join(" | "))
            check("Profiles: the current profile is marked", row(pop, "Balanced").current && !row(pop, "Battery").current)
            check("Profiles: the limit set elsewhere is marked; cap and full not", row(pop, "Balanced (stops at 90%)").current && !row(pop, "Stop at 80%").current && !row(pop, "Full charge").current)
            check("Profiles: Charge refreshed on open", Charge.calls.indexOf("refresh") >= 0, Charge.calls.join(","))
            click(row(pop, "Performance"))
            check("Profiles: click a profile sets it", last(Sys.calls) === "run system76-power profile performance" && w.doneCount === 1, Sys.calls.join("; "))
            click(row(pop, "Stop at 80%"))
            check("Profiles: Stop at 80% sets the cap", last(Charge.calls) === "set cap" && w.doneCount === 2, Charge.calls.join(","))
            click(row(pop, "Full charge"))
            check("Profiles: Full charge", last(Charge.calls) === "set full_charge" && w.doneCount === 3, Charge.calls.join(","))
            const n = Charge.calls.length
            click(row(pop, "Balanced (stops at 90%)"))
            check("Profiles: the limit-in-force row is only shown, not a button", Charge.calls.length === n && w.doneCount === 3)
            Sys.profileCls = "battery"
            check("Profiles: follows the profile", row(pop, "Battery").current && !row(pop, "Balanced").current)
            Charge.profile = "custom"; Charge.end = 80
            check("Profiles: capped: Stop at 80% marked, no extra row", row(pop, "Stop at 80%").current && labels(pop).length === 5, labels(pop).join(" | "))
            Charge.profile = "full_charge"; Charge.end = 100
            check("Profiles: full: Full charge marked", row(pop, "Full charge").current && !row(pop, "Stop at 80%").current && labels(pop).length === 5)
            Charge.loaded = false
            check("Profiles: unknown limit marks nothing", !row(pop, "Full charge").current && !row(pop, "Stop at 80%").current)
            Charge.profile = "balanced"; Charge.end = 90; Charge.loaded = true
            return 100
        } },
    ]).concat(fitCases("Profiles", () => root.w)).concat([

        // ================= BatteryWarn =================
        { name: "BatteryWarn", run: function() {
            UPower.onBattery = false; UPower.displayDevice.percentage = 0.8; UPower.displayDevice.isLaptopBattery = true; UPower.displayDevice.ready = true
            batt = battC.createObject(root)
            Sys.reset()
            const d = UPower.displayDevice
            const notes = () => Sys.calls.filter(c => c.indexOf("notify-send") >= 0)
            UPower.onBattery = true; d.percentage = 0.5
            check("BatteryWarn: nothing at 50%", notes().length === 0, Sys.calls.join("; "))
            d.percentage = 0.15
            check("BatteryWarn: a warning at 15%", notes().length === 1 && /^run notify-send -a Battery -i battery-low 'Battery at 15%'/.test(notes()[0]) && notes()[0].indexOf("critical") < 0, notes().join("; "))
            d.percentage = 0.12; d.percentage = 0.08
            check("BatteryWarn: once per discharge", notes().length === 1, notes().join("; "))
            d.percentage = 0.05
            check("BatteryWarn: a critical one at 5%", notes().length === 2 && /^run notify-send -u critical -a Battery -i battery-caution 'Battery at 5%'/.test(notes()[1]), notes().join("; "))
            d.percentage = 0.03
            check("BatteryWarn: the critical one once too", notes().length === 2)
            UPower.onBattery = false
            check("BatteryWarn: plugging in warns nothing", notes().length === 2)
            d.percentage = 0.10; UPower.onBattery = true
            check("BatteryWarn: unplugged again at 10%: warned again (re-armed)", notes().length === 3 && notes()[2].indexOf("Battery at 10%") >= 0, notes().join("; "))
            UPower.onBattery = false; d.percentage = 0.9; UPower.onBattery = true; d.isLaptopBattery = false; d.percentage = 0.04; d.percentage = 0.02
            check("BatteryWarn: no battery (a UPS, a desktop): nothing", notes().length === 3, notes().join("; "))
            d.percentage = 0; d.isLaptopBattery = true
            check("BatteryWarn: 0% (not read yet): nothing", notes().length === 3, notes().join("; "))
            batt.destroy()
            return 100
        } },

        // ================= WallMenu =================
        { name: "WallMenu: open", run: function() {
            if (w) { w.destroy(); w = null }
            WallState.calls = []; WallState.cfg.weather = false; WallState.cfg.fps = 20; WallState.cfg.running = true; WallState.cfg.hidden = false
            Sys.reset()
            check("WallMenu: starts hidden", wallMenu.visible === false)
            wallMenu.toggle()
            return 300
        } },
        { name: "WallMenu: chips and clicks", run: function() {
            const m = wallMenu.contentItem
            check("WallMenu: toggle shows it", wallMenu.visible === true)
            check("WallMenu: twelve scenes", WallState.scenes.every(s => has(m, s.charAt(0).toUpperCase() + s.slice(1))), texts(m).join(" | "))
            clickText(m, "Aurora")
            check("WallMenu: a scene chip sets the scene", last(WallState.calls) === "setScene aurora" && WallState.cfg.scene === "aurora", WallState.calls.join("; "))
            clickText(m, "Music")
            check("WallMenu: an effect chip flips the effect", last(WallState.calls) === "setEffect music false", WallState.calls.join("; "))
            clickText(m, "−")
            check("WallMenu: fan − lowers the limit by 100", WallState.cfg.fanMax === 3600 && has(m, "3600"), WallState.cfg.fanMax)
            clickText(m, "+")
            check("WallMenu: fan + raises it", WallState.cfg.fanMax === 3700)
            clickText(m, "Rain")
            check("WallMenu: a weather chip turns weather on and forces it", WallState.cfg.weather === true && WallState.wxDemo === "rain")
            clickText(m, "None")
            check("WallMenu: None turns weather off", WallState.cfg.weather === false)
            clickText(m, "Still")
            check("WallMenu: Still stops the animation", WallState.cfg.running === false && WallState.cfg.hidden === false)
            check("WallMenu: status says still", has(m, "still"))
            clickText(m, "Plain wallpaper")
            check("WallMenu: Plain hides the scene", WallState.cfg.hidden === true && has(m, "plain wallpaper"))
            clickText(m, "Moving")
            check("WallMenu: Moving runs it again", WallState.cfg.running === true && WallState.cfg.hidden === false)
            clickText(m, "30")
            check("WallMenu: frames-a-second chip", WallState.cfg.fps === 30)
            check("WallMenu: the screensaver row is there", has(m, "Screensaver"))
            check("WallMenu: still open after all that (stays open)", wallMenu.visible === true)
            check("WallMenu: nothing run through Sys", Sys.calls.length === 0, Sys.calls.join("; "))
            WallState.fanAvg = 3456; WallState.cpuTemp = 71.4
            return 100
        } },
    ]).concat(fitCases("WallMenu", () => wallMenu)).concat([
        { name: "WallMenu: Escape closes", run: function() {
            const qw = wallMenu.contentItem.Window.window
            if (qw && !qw.active) qw.requestActivate()
            ev.keyClick(Qt.Key_Escape, Qt.NoModifier, -1)
            return 150
        } },
        { name: "WallMenu: closed", run: function() {
            check("WallMenu: Escape closes it", wallMenu.visible === false)
            wallMenu.toggle(); wallMenu.toggle()
            check("WallMenu: toggle twice leaves it closed", wallMenu.visible === false)
            return 50
        } },

        // ================= MsgIcon / Slider =================
        { name: "MsgIcon", run: function() {
            iconArt.image = dir + "/art.png"
            iconMissing.image = dir + "/missing.png"
            iconGlyph.glyph = "★"
            iconApp.icon = dir + "/art.png"
            bits.visible = true
            return 500
        } },
        { name: "MsgIcon: states", run: function() {
            check("MsgIcon: a bare path becomes a file URL", iconArt.url("/a/b.png") === "file:///a/b.png" && iconArt.url("image://icon/x") === "image://icon/x")
            check("MsgIcon: a picture loads and shows", iconArt.hasArt && iconArt.visible && !iconArt.hasIcon)
            check("MsgIcon: a missing picture leaves no tile", !iconMissing.hasArt && !iconMissing.visible)
            check("MsgIcon: a glyph shows", iconGlyph.visible && !iconGlyph.hasArt && has(iconGlyph, "★"))
            check("MsgIcon: an app icon shows", iconApp.hasIcon && iconApp.visible)
            check("MsgIcon: nothing given, nothing shown", !iconEmpty.visible)
            check("MsgIcon: the tile is Theme.msgIcon square", iconArt.width === Theme.msgIcon && iconArt.height === Theme.msgIcon)
            iconMissing.glyph = "!"
            check("MsgIcon: a missing picture falls back to the glyph", iconMissing.visible && has(iconMissing, "!"))
            sliderLog = []
            click(slider, Qt.LeftButton, 0.25)
            check("Slider: click at a quarter moves to 0.25", same(sliderLog, ["moved 0.25"]), sliderLog.join(","))
            click(slider, Qt.RightButton, 0.9)
            check("Slider: right-click is the secondary action, no move", same(sliderLog, ["moved 0.25", "right"]), sliderLog.join(","))
            sliderLog = []
            ev.mouseWheel(slider, 100, 7, Qt.NoButton, Qt.NoModifier, 0, 120, -1)
            ev.mouseWheel(slider, 100, 7, Qt.NoButton, Qt.NoModifier, 0, -120, -1)
            check("Slider: wheel up/down steps 0.05 from the value", same(sliderLog, ["moved 0.55", "moved 0.45"]), sliderLog.join(","))
            slider.value = 1; sliderLog = []
            ev.mouseWheel(slider, 100, 7, Qt.NoButton, Qt.NoModifier, 0, 120, -1)
            check("Slider: never past 1", same(sliderLog, ["moved 1.00"]), sliderLog.join(","))
            sliderLog = []
            click(slider, Qt.LeftButton, 0); click(slider, Qt.LeftButton, 1)
            check("Slider: the ends are 0 and 1", same(sliderLog, ["moved 0.00", "moved 1.00"]), sliderLog.join(","))
            slider.value = 0
            const fill = slider.children[0]
            check("Slider: at 0 the fill is still a round dot", fill.width === slider.height)
            slider.off = true
            check("Slider: off draws the fill grey", Qt.colorEqual(fill.color, Theme.dim))
            return 50
        } },
    ]).concat(fitCases("MsgIcon + Slider", () => bits)).concat([

        // ================= ScriptSource =================
        { name: "ScriptSource: good JSON", run: function() {
            bits.visible = false
            writeFile(dir + "/ss.out", '{"text":"5","tooltip":"two\nlines","class":"warn","rooms":[{"id":"a"}]}\n')
            ssFile.refresh()
            return 400
        } },
        { name: "ScriptSource: bad JSON keeps the last answer", run: function() {
            check("ScriptSource: text, class, data", ssFile.text === "5" && ssFile.cls === "warn" && ssFile.data.rooms && ssFile.data.rooms[0].id === "a", JSON.stringify(ssFile.data))
            check("ScriptSource: a raw newline inside a string is read", ssFile.tooltip === "two\nlines", JSON.stringify(ssFile.tooltip))
            writeFile(dir + "/ss.out", "Traceback (most recent call last): oops\n")
            ssFile.refresh()
            return 400
        } },
        { name: "ScriptSource: empty output clears", run: function() {
            check("ScriptSource: bad output never reaches the bar", ssFile.text === "5" && ssFile.cls === "warn", ssFile.text)
            writeFile(dir + "/ss.out", "")
            ssFile.refresh()
            return 400
        } },
        { name: "ScriptSource: timer", run: function() {
            check("ScriptSource: empty output clears everything", ssFile.text === "" && ssFile.tooltip === "" && ssFile.cls === "" && Object.keys(ssFile.data).length === 0, JSON.stringify(ssFile.data))
            check("ScriptSource: inactive source never ran on its own", readFile(dir + "/ss.ticks") === "")
            ssTick.active = true
            return 800
        } },
        { name: "ScriptSource: stop", run: function() {
            const n = readFile(dir + "/ss.ticks").split("\n").filter(s => s).length
            check("ScriptSource: active: runs at once and then on its interval", n >= 3 && ssTick.text === "t", n)
            ssTick.active = false
            root.ticksAtStop = n
            return 600
        } },
        { name: "ScriptSource: stopped", run: function() {
            const n = readFile(dir + "/ss.ticks").split("\n").filter(s => s).length
            check("ScriptSource: inactive: no more runs", n <= root.ticksAtStop + 1, n + " after " + root.ticksAtStop)
            return 50
        } },

        // ================= every Settings page loads =================
        { name: "Settings pages: build each (dark)", run: function() {
            check("Settings pages: the runner found the pages", pageFiles.length >= 14, pageFiles.join(" "))
            for (const f of pageFiles) {
                const c = Qt.createComponent(f + ".qml")
                if (c.status !== Component.Ready) { check("page builds: " + f, false, c.errorString()); continue }
                const win = pageWinC.createObject(root)
                const pg = c.createObject(win.contentItem, { win: winStub, width: 760, height: 900 })
                if (!pg) { check("page builds: " + f, false, c.errorString()); win.destroy(); continue }
                pageWins.push(win)
                const o = Object.assign({}, pageObjs); o[f] = pg; pageObjs = o
            }
            return 1500
        } },
        { name: "Settings pages: look (dark)", run: function() {
            for (const f of pageFiles) {
                const pg = pageObjs[f]
                if (!pg) continue
                check("page loads: " + f, pg.title !== "" && pg.pageId !== "" && pg.shown && pg.contentHeight > 120, pg.title + " " + pg.pageId + " " + pg.contentHeight)
            }
            setDark(false)
            return 600
        } },
        { name: "Settings pages: light", run: function() {
            check("Settings pages: light theme is on", !Theme.dark)
            for (const f of pageFiles) { const pg = pageObjs[f]; if (pg) check("page still there in light: " + f, pg.visible && pg.contentHeight > 120) }
            setDark(true)
            return 400
        } },
        { name: "Settings pages: close", run: function() {
            console.log("STEST note: closing the pages")
            for (const f of pageFiles) if (pageObjs[f]) pageObjs[f].destroy()
            pageObjs = ({})
            return 300
        } },
        { name: "Settings pages: close windows", run: function() {
            for (const win of pageWins) win.destroy()
            pageWins = []
            return 300
        } }
    ])
    property int ticksAtStop: 0

    property int at: 0
    Timer {
        id: stepper
        interval: 900; running: true
        onTriggered: {
            if (root.at >= root.cases.length) {
                console.log("STEST RESULT pass " + root.passed + " fail " + root.failed)
                done.start()
                return
            }
            const c = root.cases[root.at++]
            console.log("STEST case: " + c.name)
            let wait = 100
            try { wait = c.run() } catch (e) { root.failed++; console.log("STEST FAIL " + c.name + " threw: " + e + " " + e.stack) }
            interval = Math.max(20, wait || 100)
            restart()
        }
    }
    Timer { id: done; interval: 300; onTriggered: Qt.quit() }
}
