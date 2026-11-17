// The bar: one per screen, drawn from Theme, Sys and the Quickshell services.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    // a narrow screen (the portrait Dell is only 1080 px wide) gets fewer pills.
    // By width, not serial number: Qt did not always report the serial, and the full
    // set of pills then ran over the clock (seen 2026-11-11).
    readonly property bool compact: modelData.width < 1400
    readonly property var monitor: Hyprland.monitorFor(modelData)
    readonly property int slot: monitor ? Math.max(1, Sys.slotOf(monitor.name)) : 1
    readonly property int desktop: monitor && monitor.activeWorkspace && monitor.activeWorkspace.id >= 11
                                   ? Math.floor(monitor.activeWorkspace.id / 10) : Sys.desktop

    // nothing open on this screen's desktop: the pet is down on the wallpaper, not up here
    readonly property bool deskEmpty: !!monitor && !!monitor.activeWorkspace
        && !Hyprland.toplevels.values.some(t => t.workspace && t.workspace.id === bar.monitor.activeWorkspace.id)
    // (not while the scene is switched off: the wallpaper window, and the pet on it, are hidden then)
    readonly property bool petBelow: Pet.roam && !WallState.cfg.hidden && (deskEmpty || Pet.deskDemo)

    visible: Sys.barVisible
    color: "transparent"
    anchors { top: !Sys.barAtBottom; bottom: Sys.barAtBottom; left: true; right: true }
    margins { top: Sys.barAtBottom ? 0 : 8; bottom: Sys.barAtBottom ? 8 : 0; left: 8; right: 8 }
    implicitHeight: 34
    WlrLayershell.namespace: "qs-bar"        // blurred by a layer rule in hyprland.lua
    WlrLayershell.layer: WlrLayer.Top
    // the keyboard only while a popup is open, so Escape can close it (as Panel.qml)
    WlrLayershell.keyboardFocus: popup !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    IdleInhibitor { window: bar; enabled: Sys.keepAwake && bar.visible }

    // ---- title of the window in front on this screen ----
    property string title: ""
    readonly property var top: Hyprland.activeToplevel
    function syncTitle() {
        if (!monitor) return
        const ws = monitor.activeWorkspace
        if (ws && ws.toplevels.values.length === 0) { title = ""; return }
        if (top && top.workspace && ws && top.workspace.id === ws.id) title = top.title || ""
    }
    onTopChanged: syncTitle()
    Connections { target: bar.top; function onTitleChanged() { bar.syncTitle() } }
    Connections { target: bar.monitor; function onActiveWorkspaceChanged() { bar.syncTitle() } }
    Connections { target: Hyprland; function onRawEvent(event) { if (event.name === "closewindow" || event.name === "openwindow") bar.syncTitle() } }

    Item {
        id: root
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: bar.popup = ""

        // a click on an empty stretch of the bar closes whatever popup is open (the focus grab
        // only sees clicks outside the bar and the popup)
        MouseArea { anchors.fill: parent; z: -5; enabled: bar.popup !== ""; acceptedButtons: Qt.AllButtons; onPressed: bar.popup = "" }
        // the pet (Pet.qml): walks the empty stretches either side of the clock and music pill
        HoverHandler { id: barHover }
        PetSprite {
            id: petSprite
            screenName: Pet.screenKey(bar.modelData)      // its remembered place: by monitor, not by DP-N (renumbered at every dock attach)
            pointerX: barHover.hovered && bar.popup === "" ? barHover.point.position.x : -1
            onMenuRequested: bar.togglePopup("pet", petSprite)
            readonly property real midRight: (media.visible ? media.x + media.width : clockPill.x + clockPill.width)
            shown: Pet.showsOn(Pet.screenKey(bar.modelData), !!bar.monitor && !!Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === bar.monitor.name) && !bar.petBelow
            gaps: [{ from: leftRow.width + 10, to: clockPill.x - 10 }, { from: midRight + 10, to: rightRow.x - 10 }]
            bellX: rightRow.x - 10 - 32
            clockX: clockPill.x - 10 - 32
            musicX: midRight + 12
            // pills it can be put down on (PetAntics.qml): the bell rings, the clock is sat on
            spans: ({ bell: { from: rightRow.x + notifPill.x, to: rightRow.x + notifPill.x + notifPill.width }, clock: { from: clockPill.x, to: clockPill.x + clockPill.width } })
        }
        // its friend, if it has one: a second animal with the same run of the bar
        PetSprite {
            id: petFriend
            who: 1
            screenName: Pet.screenKey(bar.modelData)
            pointerX: barHover.hovered && bar.popup === "" ? barHover.point.position.x : -1
            onMenuRequested: bar.togglePopup("pet", petFriend)
            readonly property real midRight: (media.visible ? media.x + media.width : clockPill.x + clockPill.width)
            shown: Pet.showsOn(Pet.screenKey(bar.modelData), !!bar.monitor && !!Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === bar.monitor.name) && !bar.petBelow
            gaps: [{ from: leftRow.width + 10, to: clockPill.x - 10 }, { from: midRight + 10, to: rightRow.x - 10 }]
            bellX: rightRow.x - 10 - 32
            clockX: clockPill.x - 10 - 32
            musicX: midRight + 12
            // pills it can be put down on (PetAntics.qml): the bell rings, the clock is sat on
            spans: ({ bell: { from: rightRow.x + notifPill.x, to: rightRow.x + notifPill.x + notifPill.width }, clock: { from: clockPill.x, to: clockPill.x + clockPill.width } })
        }

        // ================= left =================
        Row {
            id: leftRow
            anchors.left: parent.left
            height: parent.height
            spacing: 6

            Pill {
                id: desks
                pad: 4
                readonly property var list: {
                    const seen = {}
                    seen[bar.desktop] = true
                    for (const w of Hyprland.workspaces.values) if (w.id >= 11) seen[Math.floor(w.id / 10)] = true
                    return Object.keys(seen).map(Number).sort((a, b) => a - b)
                }
                function wsHere(n) { return Hyprland.workspaces.values.find(w => w.id === n * 10 + bar.slot) }
                function urgent(n) { return Hyprland.workspaces.values.some(w => Math.floor(w.id / 10) === n && w.urgent) }
                onScrolled: direction => Sys.goDesktop(bar.desktop - direction)
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: desks.list
                        Rectangle {
                            id: btn
                            required property int modelData
                            readonly property bool current: modelData === bar.desktop
                            readonly property bool here: { const w = desks.wsHere(modelData); return !!w && w.toplevels.values.length > 0 }
                            readonly property bool urgent: desks.urgent(modelData)
                            width: num.implicitWidth + 16
                            height: 26
                            radius: 7
                            color: current ? Theme.accentBg : urgent ? Theme.alt : hit.containsMouse ? Theme.hover : "transparent"
                            Text {
                                id: num
                                anchors.centerIn: parent
                                text: btn.modelData
                                color: btn.current ? Theme.accentInk : btn.urgent ? Theme.altInk : (btn.here || hit.containsMouse) ? Theme.fg : Theme.dim
                                font { family: Theme.font; pixelSize: 13 }
                            }
                            MouseArea { id: hit; anchors.fill: parent; hoverEnabled: true; onClicked: Sys.goDesktop(btn.modelData) }
                        }
                    }
                }
            }

            Pill {
                visible: !bar.compact && bar.title !== ""
                maxText: 480
                text: bar.title.length > 60 ? bar.title.slice(0, 59) + "…" : bar.title
            }
        }

        // ================= centre =================
        // The clock sits dead centre; the media pill hangs off its right side and
        // shortens its text to whatever room is left before the right-hand pills.
        Item {
            anchors.fill: parent

            Pill {
                id: clockPill
                // centred, but it moves left when the right-hand pills reach it (they ran over it on
                // the laptop screen 2026-11-12: long Wi-Fi name + drive pill), never into the left row
                x: Math.max(leftRow.width + 12, Math.min((parent.width - width) / 2, rightRow.x - 12 - width))
                text: Qt.formatDateTime(Sys.now, "ddd MMM dd  HH:mm")
                ink: Theme.accent
                bold: true
                tip: "<b>" + Qt.formatDateTime(Sys.now, "dddd, MMMM d") + "</b>"
                     + (Sys.currentEvent ? "\nNow: " + Sys.currentEvent.title + " (until " + Sys.currentEvent.end + ")" : "")
                     + (Sys.nextEvent ? "\nNext: " + Sys.nextEvent.start + " " + Sys.nextEvent.title : (Sys.today.length > 0 ? "\nNothing more today" : ""))
                     + (Clocks.tipFor(Sys.nowHM) !== "" ? "\n" + Clocks.tipFor(Sys.nowHM) : "")
                     + "\nClick: calendar and agenda\nRight-click: control panel"
                onClicked: bar.togglePopup("calendar", clockPill)
                onRightClicked: Sys.panelToggle()
                // what the pet does to it (PetAntics.qml): sat on, it sinks a little; knocked
                // off by the cat, it drops out of the bar and bounces back
                transform: [
                    Translate { y: petSprite.weigh || petFriend.weigh ? 3 : 0; Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutBack } } },
                    Translate { id: clockFall },
                    Rotation { id: clockTilt; origin.x: clockPill.width / 2; origin.y: 17 }
                ]
                SequentialAnimation {
                    id: clockPush
                    ParallelAnimation {
                        NumberAnimation { target: clockFall; property: "y"; to: 46; duration: 380; easing.type: Easing.InQuad }
                        NumberAnimation { target: clockTilt; property: "angle"; to: 16; duration: 380 }
                    }
                    PauseAnimation { duration: 1200 }
                    ParallelAnimation {
                        NumberAnimation { target: clockFall; property: "y"; to: 0; duration: 900; easing.type: Easing.OutBounce }
                        NumberAnimation { target: clockTilt; property: "angle"; to: 0; duration: 900; easing.type: Easing.OutElastic }
                    }
                }
                Connections { target: petSprite; function onPushed() { clockPush.restart() } }
            }

            // Music: cover, live bars (or a pause mark), the title (a long one slides while hovered),
            // and a thin line along the bottom for how far into the track we are.
            Pill {
                id: media
                anchors.left: clockPill.right
                anchors.leftMargin: 6
                readonly property var player: Sys.player
                readonly property bool playing: player !== null && player.isPlaying
                readonly property string what: !player ? "" : [player.trackTitle, player.trackArtist].filter(s => s && s !== "").join("  ·  ")
                // room for the text: up to the right-hand pills, less the cover, the bars and padding
                readonly property int room: rightRow.x - (clockPill.x + clockPill.width) - 12 - 24 - 22 - 20 - 16
                readonly property real progress: player && player.lengthSupported && player.length > 0
                                                 ? Math.max(0, Math.min(1, player.position / player.length)) : 0
                visible: !bar.compact && what !== "" && room >= 70
                tip: !player ? "" : "<b>" + (player.trackTitle || "") + "</b>"
                     + (player.trackArtist ? "\n" + player.trackArtist : "") + (player.trackAlbum ? "\n" + player.trackAlbum : "")
                     + "\n(" + player.identity + ")\nClick: player controls\nRight-click: play / pause\nMiddle-click or click the cover: open the player"
                function openPlayer() {
                    Sys.tipTarget = null
                    const p = media.player
                    if (!p) return
                    if (p.identity === "MPD" || p.desktopEntry === "mpd-mpris")
                        Sys.run("$HOME/.local/bin/music")
                    else if (p.canRaise)
                        p.raise()
                }
                onClicked: bar.togglePopup("media", media)
                onRightClicked: if (player && player.canTogglePlaying) player.togglePlaying()
                onMiddleClicked: openPlayer()

                Item {
                    width: mediaRow.width
                    height: parent.height
                    Row {
                        id: mediaRow
                        height: parent.height
                        spacing: 8
                        Rectangle {
                            width: 22; height: 22; radius: 5
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.track
                            clip: true
                            Image {
                                id: cover
                                anchors.fill: parent
                                source: media.player ? (media.player.trackArtUrl || "") : ""
                                sourceSize: Qt.size(44, 44)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: status === Image.Ready
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !cover.visible
                                text: Icons.playerDefault
                                color: Theme.faint
                                font { family: Theme.font; pixelSize: 12 }
                            }
                            // The cover opens the player: MPD's ncmpcpp via ~/.local/bin/music
                            // (its own special workspace), anything else through MPRIS Raise.
                            // Left button only, so right/middle clicks still reach the pill.
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: media.openPlayer()
                            }
                        }
                        Item {
                            width: 20; height: parent.height
                            readonly property bool live: media.playing && WallState.listening && WallState.cfg.pillbars
                            Row {
                                visible: parent.live
                                anchors.centerIn: parent
                                height: 16
                                spacing: 2
                                Repeater {
                                    model: 5
                                    Rectangle {
                                        required property int index
                                        width: 2; radius: 1
                                        height: 3 + 13 * Math.min(1, WallState.bands[index] || 0)
                                        anchors.bottom: parent.bottom
                                        color: Theme.accent
                                    }
                                }
                            }
                            Text {
                                visible: !parent.live
                                anchors.centerIn: parent
                                // what a click does, like the play button in MediaCard and MediaPop
                                text: media.playing ? Icons.paused : Icons.playing
                                color: media.playing ? Theme.accent : Theme.dim
                                font { family: Theme.font; pixelSize: 13 }
                            }
                        }
                        Item {
                            id: slot
                            width: Math.min(mediaLabel.implicitWidth, Math.min(360, media.room))
                            height: parent.height
                            clip: true
                            readonly property real over: Math.max(0, mediaLabel.implicitWidth - width)
                            Text {
                                id: mediaLabel
                                anchors.verticalCenter: parent.verticalCenter
                                text: media.what
                                color: media.playing ? Theme.fg : Theme.dim
                                font { family: Theme.font; pixelSize: 13 }
                                onTextChanged: x = 0
                            }
                            // long titles slide to their end and back, pausing at each side
                            SequentialAnimation {
                                id: slide
                                running: slot.over > 0 && media.hovered      // only while pointed at: no idle redraws
                                loops: Animation.Infinite
                                PauseAnimation { duration: 500 }
                                NumberAnimation { target: mediaLabel; property: "x"; to: -slot.over; duration: slot.over * 45 }
                                PauseAnimation { duration: 1500 }
                                NumberAnimation { target: mediaLabel; property: "x"; to: 0; duration: slot.over * 45 }
                                onRunningChanged: if (!running) mediaLabel.x = 0
                            }
                        }
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 3
                        width: parent.width * media.progress
                        height: 2; radius: 1
                        color: Theme.accent
                        opacity: media.playing ? 0.9 : 0.4
                        visible: media.progress > 0
                    }
                }
            }
        }

        // ================= right =================
        // One rule for every pill's buttons:
        //   click         opens its list or card when it has one, otherwise does its one thing
        //   right-click   the quick action (mute, Do Not Disturb, play / pause, eject, reconnect,
        //                 next power profile), or its settings when it has no quick action
        //   middle-click  the full app (pavucontrol, the music player, ...), where there is one
        //   scroll        only where it changes a level: desktops (left) and volume
        // Nothing that cuts something off (eject, reconnect) sits on a plain click.
        Row {
            id: rightRow
            anchors.right: parent.right
            height: parent.height
            spacing: 6

            Pill {    // screen recording in progress
                text: Sys.rec.text
                tip: Sys.rec.tooltip
                fill: Theme.red; edge: Theme.red; ink: Theme.accentInk; bold: true
                onClicked: { Sys.run(Sys.bin + "screen-record stop"); Sys.refreshSoon() }
            }

            Pill {    // something is using the mic or capturing video
                visible: Sys.micInUse || Sys.videoInUse
                // muted while something is listening ("you are muted in the call"): a struck-through mic
                readonly property bool micMuted: Sys.source && Sys.source.audio ? Sys.source.audio.muted : false
                ink: Theme.red
                edge: Qt.rgba(229/255, 72/255, 77/255, 0.7)
                fill: Sys.micInUse && micMuted ? Theme.tint(Theme.red, 0.22) : Theme.bg
                text: [Sys.micInUse ? (micMuted ? Icons.micMuted : Icons.mic) : "", Sys.videoInUse ? "▣" : ""].filter(s => s !== "").join(" ")
                tip: "<b>In use</b>: " + [Sys.micInUse ? (micMuted ? "microphone (you are MUTED)" : "microphone") : "", Sys.videoInUse ? "screen or camera" : ""].filter(s => s !== "").join(", ")
                     + (Sys.micInUse ? "\nClick or right-click: unmute / mute (also Super+Ctrl+M)" : "")
                onClicked: if (Sys.micInUse) Sys.run(Sys.bin + "mic toggle")
                onRightClicked: if (Sys.micInUse) Sys.run(Sys.bin + "mic toggle")
            }

            Pill {    // the Org clock running in Emacs
                visible: !bar.compact && Sys.orgClock.text !== ""
                text: Sys.orgClock.text
                tip: Sys.orgClock.tooltip
                ink: Theme.accent
                maxText: 220
                onClicked: Sys.focusEmacs()
            }

            Pill {    // unread mail (a count only; hidden while notifications are silenced)
                visible: !bar.compact && !Notif.dnd && Sys.mail.text !== ""
                text: Sys.mail.text
                tip: Sys.mail.tooltip
                onClicked: Sys.focusEmacs()
            }

            Pill {    // unread Teams chats (from the local Matrix bridge; hidden while notifications are silenced)
                id: teamsPill
                visible: !bar.compact && !Notif.dnd && Sys.teams.text !== ""
                text: Sys.teams.text
                tip: Sys.teams.tooltip
                ink: Sys.teams.cls === "mention" ? Theme.accent : Theme.fg
                bold: Sys.teams.cls === "mention"
                onClicked: bar.togglePopup("teams", teamsPill)       // the unread chats
                onRightClicked: Sys.teamsOpen("")                    // the oldest unread chat
                onMiddleClicked: Sys.teamsList()                     // every chat, in Emacs
            }

            Pill {    // Tailscale, only while an exit node carries the traffic
                visible: Sys.tail.cls === "on" && Sys.tail.text !== ""
                text: "⇄ " + Sys.tail.text
                tip: Sys.tail.tooltip + "\nClick: control panel"
                ink: Theme.accent
                maxText: 140
                onClicked: Sys.panelToggle()
            }

            Pill {    // tray
                id: tray
                visible: !bar.compact && SystemTray.items.values.length > 0
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Repeater {
                        model: SystemTray.items
                        MouseArea {
                            id: trayItem
                            required property var modelData
                            width: 16; height: 16
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            function menu() {
                                const p = trayItem.mapToItem(null, 0, trayItem.height + 10)
                                modelData.display(bar, p.x, p.y)
                            }
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) { if (modelData.hasMenu) menu() }
                                else if (mouse.button === Qt.MiddleButton) modelData.secondaryActivate()
                                else if (modelData.onlyMenu && modelData.hasMenu) menu()
                                else modelData.activate()
                            }
                            IconImage { anchors.fill: parent; source: trayItem.modelData.icon; implicitSize: 16 }
                        }
                    }
                }
            }

            Pill {    // keep awake
                visible: !bar.compact
                text: Sys.keepAwake ? Icons.awake : Icons.sleepy
                fill: Sys.keepAwake ? Theme.accentBg : Theme.bg
                ink: Sys.keepAwake ? Theme.accentInk : Theme.fg
                tip: Sys.keepAwake ? "<b>Keep awake</b>: on, the screen won't dim or lock\nClick: allow sleep"
                                   : "<b>Keep awake</b>: off\nClick: keep the screen awake"
                onClicked: Sys.keepAwake = !Sys.keepAwake
            }

            // a background job is stale or failing (Health.qml); invisible while all is well
            HealthPill { id: healthPill; onClicked: bar.togglePopup("health", healthPill) }

            Pill {    // notifications: a count of the unseen ones, the list on click, Do Not Disturb on right-click
                id: notifPill
                text: (Notif.dnd ? Icons.bellOff : Icons.bell) + (Notif.unseen > 0 ? " " + Notif.unseen : "")
                bold: Notif.unseen > 0
                fill: Notif.dnd ? Theme.accentBg : Theme.bg
                ink: Notif.dnd ? Theme.accentInk : Notif.unseenCritical ? Theme.red : Notif.unseen > 0 ? Theme.accent : Theme.fg
                tip: "<b>Notifications</b>: " + (Notif.unseen > 0 ? Notif.unseen + " new" : "nothing new")
                     + (Notif.dnd ? ", Do Not Disturb is on" : "")
                     + "\nClick: the list\nRight-click: Do Not Disturb " + (Notif.dnd ? "off" : "on")
                onClicked: bar.togglePopup("notifs", notifPill)
                onRightClicked: Notif.setDnd(!Notif.dnd)
                onMiddleClicked: Notif.setDnd(!Notif.dnd)
                // the pet, put down on it, rings it (PetAntics.qml)
                SequentialAnimation {
                    id: bellSwing
                    NumberAnimation { target: notifPill; property: "rotation"; to: 16; duration: 70 }
                    NumberAnimation { target: notifPill; property: "rotation"; to: -13; duration: 110 }
                    NumberAnimation { target: notifPill; property: "rotation"; to: 9; duration: 110 }
                    NumberAnimation { target: notifPill; property: "rotation"; to: -5; duration: 110 }
                    NumberAnimation { target: notifPill; property: "rotation"; to: 0; duration: 110 }
                }
                Connections { target: petSprite; function onRang() { bellSwing.restart() } }
                Connections { target: petFriend; function onRang() { bellSwing.restart() } }
            }

            Pill {    // dark / light
                visible: !bar.compact
                text: Theme.dark ? "◑" : "◐"
                textSize: 15
                hoverInk: Theme.accent
                tip: "<b>Theme</b>: " + (Theme.dark ? "dark\nClick: switch to light" : "light\nClick: switch to dark")
                onClicked: Sys.run(Sys.bin + "cosmic-theme-toggle")
            }

            Pill {    // keyboard layout
                visible: !bar.compact && Sys.layoutShort !== ""
                text: Icons.keyboard + " " + Sys.layoutShort
                tip: "<b>Keyboard</b>: " + Sys.layout + "\nClick: switch layout (also Super+Space)"
                onClicked: Sys.run("hyprctl switchxkblayout all next")
            }

            Pill {    // bluetooth headphones
                id: btPill
                visible: !bar.compact && Sys.bt.text !== ""
                text: Sys.bt.text
                tip: Sys.bt.tooltip
                ink: Sys.bt.cls === "low" ? Theme.warn : Theme.fg
                onClicked: bar.togglePopup("bluetooth", btPill)           // device list
                onRightClicked: Sys.run(Sys.bin + "bt-audio-status bounce")  // reconnect: fixes silent audio
                onMiddleClicked: Sys.run(Sys.bin + "bt-audio-status mode")   // Pixel Buds call / music mode
            }

            Pill {    // removable drives
                visible: !bar.compact && Sys.drives.text !== ""
                text: Sys.drives.text
                tip: Sys.drives.tooltip
                ink: Theme.accent
                maxText: 140
                onClicked: Sys.run(Sys.bin + "drives open")
                onRightClicked: { Sys.run(Sys.bin + "drives eject"); Sys.refreshSoon() }
            }

            Pill {    // volume
                id: vol
                readonly property var audio: Sys.sink ? Sys.sink.audio : null
                readonly property int pct: audio ? Math.round(audio.volume * 100) : 0
                readonly property bool phones: !!Sys.sink && /bluez|headphone|headset/i.test(Sys.sink.name)
                visible: audio !== null
                ink: audio && audio.muted ? Theme.dim : Theme.fg
                text: !audio ? "" : audio.muted ? Icons.volMuted + " muted"
                    : (phones ? Icons.headphones : pct < 34 ? Icons.volLow : pct < 67 ? Icons.volMid : Icons.volHigh) + " " + pct + "%"
                tip: "<b>Sound</b>: " + (Sys.sink ? (Sys.sink.description || Sys.sink.name) : "") + ", " + pct
                     + "%\nClick: outputs and per-app volume\nRight-click: mute\nMiddle-click: pavucontrol\nScroll: volume"
                onClicked: bar.togglePopup("mixer", vol)
                onRightClicked: if (audio) audio.muted = !audio.muted
                onMiddleClicked: Sys.run("pavucontrol")
                onScrolled: direction => { if (audio) audio.volume = Math.max(0, Math.min(1, audio.volume + direction * 0.05)) }
            }

            Pill {    // microphone
                id: micPill
                readonly property var audio: Sys.source ? Sys.source.audio : null
                visible: audio !== null
                text: audio && audio.muted ? Icons.micMuted : Icons.mic
                ink: audio && audio.muted ? Theme.dim : Theme.accent
                tip: "<b>Microphone</b>: " + (Sys.source ? (Sys.source.description || Sys.source.name) : "") + ", "
                     + (audio ? Math.round(audio.volume * 100) : 0) + "%" + (audio && audio.muted ? " (muted)" : "")
                     + "\nClick: microphones and sound\nRight-click: mute / unmute (also Super+Ctrl+M)"
                onClicked: bar.togglePopup("mixer", micPill)
                onRightClicked: if (audio) audio.muted = !audio.muted
            }

            Pill {    // network
                id: netPill
                visible: !bar.compact
                maxText: 160
                ink: Sys.netKind === "offline" ? Theme.dim : Sys.netUnusual ? Theme.warn : Theme.fg
                text: Sys.netKind === "wifi" ? Icons.wifi : Sys.netKind === "wired" ? Icons.wired + " wired" : Icons.offline + " offline"
                tip: "<b>Network</b>: " + (Sys.netKind === "offline" ? "offline" : Sys.netName) + (Sys.netUnusual ? " (not a usual network)" : "")
                     + "\nClick: Wi-Fi networks\nRight-click or middle-click: connection settings"
                onClicked: bar.togglePopup("wifi", netPill)
                onRightClicked: Sys.run("nm-connection-editor")
                onMiddleClicked: Sys.run("nm-connection-editor")
            }

            Pill {    // power profile
                id: profilePill
                text: Sys.profile.text
                tip: Sys.profile.tooltip
                ink: Sys.profile.cls === "performance" ? Theme.accent : Sys.profile.cls === "battery" ? Theme.ok : Theme.fg
                onClicked: bar.togglePopup("profile", profilePill)
                onRightClicked: Sys.nextProfile()
            }

            Pill {    // battery
                id: bat
                readonly property var dev: UPower.displayDevice
                readonly property int pct: dev ? Math.round(dev.percentage * 100) : 0
                readonly property bool charging: !!dev && dev.state === UPowerDeviceState.Charging
                readonly property bool plugged: !!dev && (dev.state === UPowerDeviceState.FullyCharged || dev.state === UPowerDeviceState.PendingCharge)
                readonly property bool critical: !charging && !plugged && pct <= 12
                function span(s) {
                    if (!s || s <= 0) return ""
                    const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60)
                    return (h > 0 ? h + " h " : "") + m + " min"
                }
                visible: !!dev && dev.isPresent
                fill: critical ? Theme.alt : Theme.bg
                ink: critical ? Theme.altInk : (charging || plugged) ? Theme.accent : pct <= 25 ? Theme.warn : Theme.fg
                text: (charging ? Icons.batCharging : plugged ? Icons.batPlugged : Icons.battery[Math.min(4, Math.floor(pct / 20))]) + " " + pct + "%"
                tip: "<b>Battery</b>: " + pct + "%" + (charging ? (span(dev.timeToFull) ? ", full in " + span(dev.timeToFull) : ", charging")
                     : plugged ? ", plugged in" : (span(dev ? dev.timeToEmpty : 0) ? ", " + span(dev.timeToEmpty) + " left" : ""))
                     + (Charge.tip !== "" ? "\n" + Charge.tip : "")
                     + "\nClick: power profile"
                onClicked: bar.togglePopup("profile", bat)
            }

            Pill {    // power menu
                id: powerPill
                text: Icons.power
                ink: Theme.accent
                hoverFill: Theme.accentBg
                hoverInk: Theme.accentInk
                tip: "<b>Power</b>\nClick: lock, suspend, log out, reboot or shut down"
                onClicked: bar.togglePopup("power", powerPill)
            }
        }
    }

    // ---- popups that drop from a pill: calendar, mixer, Wi-Fi, Bluetooth, power profile, power, notifications ----
    property string popup: ""
    property Item popupAnchor: null
    function togglePopup(name, item) {
        Sys.tipTarget = null
        if (popup === name) { popup = ""; return }
        popupAnchor = item
        popup = name
        // the pet keeps walking: place the popup by where its anchor is now, not where it was last time
        Qt.callLater(function() { if (pop.anchor.updateAnchor) pop.anchor.updateAnchor() })
    }
    Connections {
        target: Sys
        function onPopupRequest(name) {
            if (!bar.visible || !bar.monitor || !Hyprland.focusedMonitor || Hyprland.focusedMonitor.name !== bar.monitor.name) return
            const at = { mixer: vol, wifi: netPill, bluetooth: btPill.visible ? btPill : netPill, profile: profilePill, power: powerPill, notifs: notifPill, health: healthPill.visible ? healthPill : notifPill, pet: petSprite.active ? petSprite : clockPill,
                         media: media.visible ? media : clockPill, teams: teamsPill.visible ? teamsPill : notifPill }
            bar.togglePopup(name, at[name] || clockPill)
        }
    }
    PopupWindow {
        id: pop
        visible: bar.popup !== ""
        anchor.item: bar.popupAnchor !== null ? bar.popupAnchor : root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        color: "transparent"
        implicitWidth: (bar.popup === "calendar" ? 300 : bar.popup === "media" ? 320 : bar.popup === "notifs" ? 360 : bar.popup === "health" ? 380 : bar.popup === "pet" ? 290 : bar.popup === "power" || bar.popup === "profile" ? 220 : bar.popup === "teams" ? 340 : 300) + 32
        implicitHeight: popBody.implicitHeight + 32 + 8
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 8
            radius: 12
            color: Theme.panelBg
            border.width: 2
            border.color: Theme.accentBg
            focus: true
            Keys.onEscapePressed: bar.popup = ""
            // in the notifications list (Super+N), c clears them all
            Keys.onPressed: event => {
                if (bar.popup === "notifs" && event.key === Qt.Key_C && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                    if (popBody.item) popBody.item.fresh = 0
                    Notif.clear()
                    event.accepted = true
                }
            }
            Loader {
                id: popBody
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                sourceComponent: ({ calendar: calendarView, mixer: mixerView, wifi: wifiView, bluetooth: bluetoothView,
                                    profile: profileView, power: powerView, media: mediaView, notifs: notifsView, pet: petView, health: healthView, teams: teamsView })[bar.popup] || null
            }
        }
    }
    Component { id: calendarView; Calendar { today: Sys.now } }
    Component { id: mixerView; Mixer {} }
    Component { id: mediaView; MediaPop {} }
    Component { id: notifsView; NotifList {} }
    Component { id: healthView; HealthList { onDone: bar.popup = "" } }
    Component { id: petView; PetMenu { screenKey: Pet.screenKey(bar.modelData); onDone: bar.popup = "" } }
    Component { id: wifiView; WifiList { onDone: bar.popup = "" } }
    Component { id: bluetoothView; BluetoothList { onDone: bar.popup = "" } }
    Component { id: profileView; ProfileList { onDone: bar.popup = "" } }
    Component { id: teamsView; TeamsList { onDone: bar.popup = "" } }
    Component { id: powerView; PowerMenu { onDone: bar.popup = "" } }
    // Click-outside-to-close. The grab is switched on a moment after the popup is
    // shown: armed in the same instant, the popup's surface doesn't exist yet, isn't
    // on the grab's list, and a click inside the popup closes it (seen 2026-11-10).
    property bool popGrab: false
    Timer { id: popGrabDelay; interval: 120; onTriggered: bar.popGrab = pop.visible }
    Connections { target: pop; function onVisibleChanged() { bar.popGrab = false; if (pop.visible) popGrabDelay.restart() } }
    HyprlandFocusGrab {
        windows: [pop, bar]
        active: bar.popGrab
        onCleared: bar.popup = ""
    }

    // ---- tooltip for whichever pill the pointer rests on ----
    PopupWindow {
        visible: Sys.tipTarget !== null && Sys.tipWindow === bar && Sys.tipText !== "" && bar.popup === ""
        anchor.item: Sys.tipTarget !== null && Sys.tipWindow === bar ? Sys.tipTarget : root
        anchor.edges: Sys.barAtBottom ? Edges.Top : Edges.Bottom
        anchor.gravity: Sys.barAtBottom ? Edges.Top : Edges.Bottom
        color: "transparent"
        implicitWidth: tipLabel.implicitWidth + 22
        implicitHeight: tipLabel.implicitHeight + 22
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 6
            radius: 8
            color: Theme.solidBg
            border.width: 1
            border.color: Theme.accentBg
            Text {
                id: tipLabel
                anchors.centerIn: parent
                textFormat: Text.StyledText
                text: Sys.tipText.replace(/\n/g, "<br>")
                color: Theme.fg
                font { family: Theme.font; pixelSize: 13 }
            }
        }
    }
}
