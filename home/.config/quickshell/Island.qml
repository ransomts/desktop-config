// The island: a short message that grows out of the top centre of the bar, over the clock,
// and folds back. For things worth a glance and no more: a meeting is
// five minutes away, recording started, headphones connected, the keyboard layout or the
// charger changed. Notifications keep their own popups (NotifPopups.qml). Not track changes:
// they come too often (the user asked for them off, 2026-11-14).
//
//   qs ipc call island say "Title" "second line"     show something (scripts can use this)
//   qs ipc call island sayAs critical|normal|low "Title" "second line"   same, with an urgency
//                                                    (outline and fill as on notifications, Theme.msgEdge/msgFill)
//   qs ipc call island on|off|status
//
// Nothing here runs while it is hidden: the window only exists on screen for the few
// seconds a message is up. On battery it appears without the growing animation.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower

PanelWindow {
    id: island

    // ---- on / off, remembered ----
    property bool enabled: true
    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/island"
    FileView { path: island.stateFile; printErrors: false; onLoaded: island.enabled = text().trim() !== "off" }
    function setEnabled(on) { enabled = on; if (!on) fold(); Sys.run("echo " + (on ? "on" : "off") + " > '" + stateFile + "'") }

    // ---- what is showing, and what waits behind it ----
    property var now: null                  // { kind, glyph, image, title, sub, ms, run, urgency }
    // urgency as on notifications (critical | normal | low): from the message, else from its kind
    readonly property string level: !now ? "normal" : now.urgency ? now.urgency
        : String(now.kind || "").startsWith("clock-") ? "critical"
        : ["kb", "bt", "power", "quiet"].indexOf(now.kind) !== -1 ? "low" : "normal"
    property var queue: []
    property bool open: false               // grown to full size
    readonly property bool wide: !!screen && screen.width >= 1400       // not on the narrow portrait screen
    readonly property bool quiet: UPower.onBattery                       // no growing animation on battery

    // every message that reaches the screen is recorded (user journal + shell-messages.jsonl, see shell-log);
    // a queued one is recorded when its turn comes:  journalctl --user -t island
    function record(msg) {
        Sys.launch([Quickshell.env("HOME") + "/.local/bin/shell-log", "island", String(msg.title || ""), String(msg.sub || ""), "source=" + (msg.kind || "")])
    }
    function say(msg) {
        if (!enabled || !wide || !Sys.barVisible) return
        if (now && now.kind && now.kind === msg.kind) { record(msg); now = msg; hold.interval = msg.ms || 3500; hold.restart(); return }
        if (now) { if (queue.length < 3) queue = queue.concat([msg]); return }
        record(msg)
        now = msg
        visible = true
        open = true
        hold.interval = msg.ms || 3500
        hold.restart()
    }
    function fold() { hold.stop(); queue = []; open = false; if (quiet || !visible) done() ; else gone.restart() }
    function done() {
        now = null
        if (queue.length > 0 && enabled) { const q = queue.slice(); const m = q.shift(); queue = q; say(m) }
        else visible = false
    }
    Timer { id: hold; onTriggered: { island.open = false; if (island.quiet) island.done(); else gone.restart() } }
    Timer { id: gone; interval: 220; onTriggered: island.done() }

    // ---- sources (all pushed; the only timer is Sys's own minute tick) ----
    property bool settled: false            // nothing is announced in the first seconds after a (re)load
    Timer { interval: 5000; running: true; onTriggered: island.settled = true }

    readonly property string minute: Sys.nowHM
    onMinuteChanged: {
        const e = Sys.nextEvent
        if (!settled || !e || !e.start) return
        const hm = s => parseInt(s.slice(0, 2)) * 60 + parseInt(s.slice(3, 5))
        if (hm(e.start) - hm(minute) === 5)
            say({ kind: "event", glyph: Icons.calendar, title: "In 5 minutes: " + e.title, sub: e.start + (e.location ? "  ·  " + e.location : ""), ms: 9000 })
    }

    readonly property bool recording: Sys.rec.text !== ""
    onRecordingChanged: if (settled) say({ kind: "rec", glyph: "●", title: recording ? "Recording the screen" : "Recording saved", sub: recording ? "Click the red pill to stop" : "~/Videos/Recordings", ms: 2500 })

    readonly property string phones: Sys.bt.shortName
    onPhonesChanged: if (settled) say({ kind: "bt", glyph: Icons.headphones, title: phones !== "" ? phones : "Headphones disconnected", sub: phones !== "" ? (Sys.bt.pct >= 0 ? "Connected, battery " + Sys.bt.pct + "%" : "Connected") : "", ms: 3000 })

    readonly property string layout: Sys.layoutShort
    onLayoutChanged: if (settled && layout !== "") say({ kind: "kb", glyph: Icons.keyboard, title: layout === "DV" ? "Dvorak" : "US (QWERTY)", sub: "Keyboard layout", ms: 1800 })

    readonly property bool onBattery: UPower.onBattery
    onOnBatteryChanged: if (settled) {
        const d = UPower.displayDevice
        say({ kind: "power", glyph: onBattery ? Icons.battery[3] : Icons.batCharging, title: onBattery ? "On battery" : "Plugged in", sub: d && d.isPresent ? Math.round(d.percentage * 100) + "%" : "", ms: 2500 })
    }

    // ---- the window ----
    visible: false
    screen: {
        const m = Hyprland.focusedMonitor
        return Quickshell.screens.find(s => m && s.name === m.name) || Quickshell.screens[0]
    }
    color: "transparent"
    anchors.top: true
    margins.top: 8                           // level with the bar
    implicitWidth: 560
    implicitHeight: 64
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-island"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: card }              // only the card takes clicks (a click folds it)

    Rectangle {
        id: card
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        // from the size of the clock pill to the size of what it says
        width: island.open ? Math.min(island.width, row.implicitWidth + 36) : 168
        height: island.open ? 52 : 34
        radius: 17
        color: Theme.msgFill(island.level, Theme.solidBg)
        border.width: Theme.msgBorder
        border.color: Theme.msgEdge(island.level)
        clip: true
        Behavior on width { enabled: !island.quiet; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: !island.quiet; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 12
            opacity: island.open ? 1 : 0
            Behavior on opacity { enabled: !island.quiet; NumberAnimation { duration: 140 } }

            MsgIcon {
                anchors.verticalCenter: parent.verticalCenter
                image: island.now ? (island.now.image || "") : ""
                glyph: island.now ? (island.now.glyph || "") : ""
                glyphColor: island.now && island.now.kind === "rec" ? Theme.red : Theme.accent
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    text: island.now ? island.now.title : ""
                    width: Math.min(implicitWidth, 440)
                    elide: Text.ElideRight
                    color: Theme.msgInk(island.level)
                    font { family: Theme.font; pixelSize: Theme.msgTitle; bold: true }
                }
                Text {
                    visible: text !== ""
                    text: island.now ? (island.now.sub || "") : ""
                    width: Math.min(implicitWidth, 440)
                    elide: Text.ElideRight
                    color: Theme.msgFaint(island.level)
                    font { family: Theme.font; pixelSize: Theme.msgBody }
                }
            }
        }
        MouseArea { anchors.fill: parent; onClicked: { const r = island.now ? island.now.run : null; island.fold(); if (r) r() } }      // a message may carry something to do when clicked
    }
}
