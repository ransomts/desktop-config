//@ pragma IconTheme Papirus-Dark
//@ pragma UseQApplication
// Quickshell entry point. Pieces live next to this file:
//   Bar.qml     the bar, one per screen
//   Panel.qml   the control panel (Super+C)
//   Osd.qml     volume / brightness popup for the media keys
//   Notif.qml, NotifPopups.qml   the notification daemon and its popups (in place of mako)
//   Launcher.qml   launcher (Super+D) with modes in LaunchView.qml      Overview.qml   desktops overview (Super+Tab)
//   Switcher.qml   window switcher (Alt+Tab)
//   Picker.qml     pick-a-line list for scripts (qs-pick: clipboard, emoji, window switcher)
//   Shot.qml       screenshot editor (Print): ShotEditor, ShotSelect, ShotMarks (+ Ink.qml), ShotButton, shot.js
//   Lecture.qml    lecture tools (state): LectureDraw (ink over the screen, Ink.qml), LectureSpot
//                  (spotlight), LectureKeys (key display, lecture-keys), LectureTimer, LecturePanel
//   Island.qml     short messages that grow out of the top centre of the bar
//   Quiet.qml (QuietCore.qml, quiet.js)  Do Not Disturb during lectures and other calendar events; Join.qml (join.js) the next online meeting
//   SharePick.qml  screen-share picker for xdg-desktop-portal-hyprland (qs-share-pick): SharePickView
//   WallMenu.qml   wallpaper popup (Super+W): scene, effects, weather, on/off
//   WallSeason.qml seasonal touches over the wallpaper; Pet.qml + PetSprite.qml the bar pet (a tiger cub)
//   Dashboard.qml  the day at a glance (Super+I): clock, weather, events, mail, music, machine (dashboard-data)
//   CursorFind.qml shake the mouse and the pointer grows (cursor-shake does the detecting)
//   DropPreview.qml outline of where a dragged tiled window will land (drop-preview works it out)
//   WifiList, BluetoothList, ProfileList, PowerMenu, MenuRow   the other pill popups
//   Lights.qml, LightsList.qml   the GVM video lights pill (~/.local/bin/gvm); IPC `lights`
//   Mixer.qml, MediaCard.qml, Calendar.qml, Slider.qml   pieces used by the panel and the pill popups
//   Wallpaper.qml  animated wallpaper, one per screen, under everything: scene shaders in shaders/,
//                  WallState.qml (scene, effects, feeds), WallSky.qml + sky.js (real night sky), WallAgenda.qml
//   Theme.qml   colours, following dark/light      Sys.qml    shared state
//   BatteryWarn.qml  low-battery notifications at 15% and 5%
//   Saver.qml   idle screensaver (SaverState.qml logic, SaverView.qml one screen, SaverRow.qml settings row)
//   Pill.qml    one pill                           Icons.qml  Nerd Font glyphs
//   Settings.qml   the settings window (Super+comma): SettingsBody + one Settings<Page>.qml per page,
//                  rows SettingsRow/Switch/Choice/Stepper/Slider/Text/Chips/Button/Info, JsonFile.qml
//   Clocks.qml     timers, alarms, stopwatch, world clock (ClocksCore.qml, clocks.js; ClockPanel.qml in the calendar popup, SettingsClock.qml)
//   Profiles.qml   focus profiles (ProfilesCore.qml, ~/.config/shell/profiles.json); FocusRow.qml for the panel
//
//   qs ipc call panel toggle        qs ipc call launcher toggle | open PREFIX        qs ipc call overview toggle
//   qs ipc call dashboard toggle | open | close       qs ipc call pet on | off | status | pat | feed | play | nap | chase | name NAME | point X
//   qs ipc call wallpaper season leaves|snow|petals|fireflies|none|auto      qs ipc call wallpaper gameday true|false
//   qs ipc call notif dnd | setDnd true|false | toggleDnd | clear | dismissAll
//   qs ipc call sound play NAME | enable true|false
//   qs ipc call bar on | off | status | refresh | popup NAME
//   qs ipc call lecture draw | hold | spot | spotsize PX | zoomin | zoomout | zoomreset | keys | timer MIN LABEL | timerpause | timerreset | timerstop | off | status
//   qs ipc call wallpaper status | on | off | scene NAME | next | speed 0.012 | effect NAME true|false | weather KIND
//   qs ipc call saver status | preview | stop | minutes N | scene same|cycle|NAME | clock true|false | battery true|false
//   qs ipc call session status | save | restore | list | on | off
//   qs ipc call quiet status | on | off | skip | resync      qs ipc call join status | open
//   qs ipc call clock timer 10m tea | alarm 7:30 | list | cancel ID | stopwatch start|stop|lap|reset | snooze      (Clocks.qml)
//   qs ipc call settings toggle | open PAGE | close           qs ipc call profile apply NAME | end | status | list
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    BatteryWarn {}

    Variants {
        model: Quickshell.screens
        Wallpaper {}
    }
    Variants {
        id: bars
        model: Quickshell.screens
        Bar {}
    }

    Panel { id: panel }
    Osd { id: osd }
    Connections { target: Notif; function onOsdNote(text, percent) { osd.show("", text, percent) } }
    NotifPopups { id: notifPopups }
    Launcher { id: launcher }
    // rows other features add to the launcher's app list (LaunchView.providers): "Join next meeting" (Join.qml),
    // "Focus: Teaching" and the other focus profiles (Profiles.qml)
    Component.onCompleted: {
        launcher.view.providers = [q => { const r = (q === "" || /^(join|meet)/i.test(q)) ? Join.row() : null; return r ? [r] : [] },
                                   q => Profiles.launcherRows(q, launcher.view),
                                   q => EventQuick.rows(q, launcher.view),
                                   q => Clocks.launcherRows(q, launcher.view)]      // "timer 10m tea", "alarm 7:30", "stopwatch", "timers"
        Profiles.island = island
        Lights.island = island                              // a light command that fails is said on the island
        Clocks.island = island                              // alarms and timers say themselves on the island; also starts Clocks with the shell
    }
    Overview { id: overview }
    Switcher { id: switcher }
    Dashboard { id: dashboard }
    Picker { id: picker }
    WallMenu { id: wallMenu }
    CursorFind { id: cursorFind }
    DropPreview { id: dropPreview }
    Island { id: island }
    LectureDraw {}
    LectureSpot {}
    LectureKeys {}
    LectureTimer {}
    Shot { id: shot }
    CamBubble {}            // webcam bubble (CamState.qml); off until `cam on`
    SharePick { id: sharePick }
    Saver {}
    Settings { id: settings; identify: displaysIdentify; island: island; launcherView: launcher.view; cursorFind: cursorFind; dropPreview: dropPreview }
    DisplaysIdentify { id: displaysIdentify }     // Settings > Displays > Identify: each screen's name on it (nothing exists until asked)
    // Fit check (Fit.qml): `qs ipc call fit check | sweep`, or ~/.local/bin/fit-check. The sweep opens each of
    // these on the focused screen, checks every shown window for things cut off, and closes it again.
    // Not swept: Picker, SharePick, Shot, Switcher (they act on a choice) and notification popups.
    Fit {
        id: fit
        roots: [bars, panel, osd, notifPopups, launcher, overview, switcher, dashboard, picker, wallMenu, island, sharePick, settings]
        property string settingsPageBefore: ""
        steps: {
            const s = [
                ["wallpaper menu", () => wallMenu.visible = true, () => wallMenu.visible = false],
                ["control panel", () => panel.visible = true, () => panel.visible = false],
                ["dashboard", () => dashboard.peek(), () => dashboard.visible = false],
                ["launcher", () => launcher.open(""), () => launcher.visible = false],
                ["overview", () => overview.visible = true, () => overview.visible = false],
                ["osd", () => osd.show("volume", "Volume", 64), () => {}],
                ["island", () => island.say({ kind: "say", glyph: "", title: "Fit check: a fairly long island title to see that it fits",
                                              sub: "and a subtitle under it, also on the long side", ms: 1500 }), () => {}]
            ]
            for (const p of ["calendar", "mixer", "media", "notifs", "wifi", "bluetooth", "profile", "power", "health", "teams", "pet", "lights"])
                s.push(["bar popup: " + p, () => Sys.popupRequest(p), () => Sys.popupRequest(p)])
            s.push(["settings (remember page)", () => { fit.settingsPageBefore = settings.page }, () => {}])
            for (const pg of settings.pages)
                s.push(["settings: " + pg.id, () => settings.open(pg.id), () => settings.close()])
            s.push(["settings (page put back)", () => { if (fit.settingsPageBefore) settings.page = fit.settingsPageBefore }, () => {}])
            return s
        }
    }
    // calendar-aware Do Not Disturb (Quiet.qml) and "join the meeting" (Join.qml): both put a message on the island
    Connections {
        target: Quiet
        function onAnnounce(title, sub) { island.say({ kind: "quiet", glyph: Icons.bellOff, title: title, sub: sub, ms: 5000 }) }
    }
    Connections {
        target: Join
        function onSoon(ev) {
            island.say({ kind: "join", glyph: Icons.calendar, title: "Join: " + ev.title, sub: ev.start + "  ·  click to open", ms: 20000,
                         run: function () { Join.open(ev.url) } })      // Island.qml: a click runs msg.run, when there is one
        }
    }
    // after the lock screen: an alarm that rang while the session was locked is shown on the island again (Clocks.qml)
    Connections { target: Pet; function onGreet() { Clocks.unlocked() } }
    // opt-in session restore (Session.qml): once per login the island offers to reopen last time's windows
    Connections {
        target: Session
        function onOffer(n, sub) {
            island.say({ kind: "session", glyph: "↺", title: "Reopen " + n + (n === 1 ? " window" : " windows") + " from last time?",
                         sub: sub + "  ·  click to reopen", ms: 15000, run: function () { Session.restore() } })
        }
    }
    // charge-limit travel reminder (ChargeTravel.qml, opt-in in ~/.config/shell/power.json) and break reminders (Breaks.qml, opt-in in breaks.json)
    ChargeTravel {
        onAsk: (title, date) => island.say({ kind: "charge", glyph: Icons.batPlugged, title: "Charge limit is on: switch to full before tomorrow?",
                                             sub: title + "  ·  click for full charge", ms: 20000, run: function () { Charge.set("full_charge") } })
    }
    Connections {
        target: Breaks
        function onNudge(minutes) {
            island.say({ kind: "break", glyph: Icons.clock, title: minutes + " minutes without a break", sub: "Stand up, look away for a minute", ms: 6000 })
            Pet.trick("spin")           // the pet's nearest thing to a stretch; it may be in no mood (Pet.obeys)
        }
    }
    readonly property bool petSound: PetSound.enabled      // starts PetSound.qml with the shell, so it hears pats, food and greetings

    // Media keys (hyprland.lua XF86Audio*) act on the player the bar's media pill shows
    // (Sys.player), not on playerctl's first player, which was Emacs's idle EMMS (2026-11-12).
    IpcHandler {
        target: "media"
        function toggle(): string { const p = Sys.player; if (p && p.canTogglePlaying) p.togglePlaying(); return p ? p.identity : "" }
        function next(): string { const p = Sys.player; if (p && p.canGoNext) p.next(); return p ? p.identity : "" }
        function previous(): string { const p = Sys.player; if (p && p.canGoPrevious) p.previous(); return p ? p.identity : "" }
        function player(): string { const p = Sys.player; return p ? p.identity + (p.isPlaying ? " playing" : " paused") : "" }
    }

    IpcHandler {
        target: "lecture"       // Lecture.qml; menu: ~/.local/bin/lecture-menu (Super+Z)
        function draw(): void { Lecture.toggleDraw() }              // start; while held: draw again; else leave (clears)
        function hold(): void { Lecture.toggleHold() }              // ink stays, clicks pass through (Tab while drawing)
        function spot(): void { Lecture.toggleSpot() }
        function spotsize(px: int): void { Lecture.setSpotSize(px) }  // radius in px (40-800)
        function zoomin(): void { Lecture.zoom(1) }                 // 1 1.5 2 3 4
        function zoomout(): void { Lecture.zoom(-1) }
        function zoomreset(): void { Lecture.zoomReset() }
        function keys(): void { Lecture.toggleKeys() }
        function keysoff(): void { Lecture.keysOff() }              // lock-screen calls this before locking
        function timer(minutes: real, label: string): void { Lecture.startTimer(minutes, label) }   // 0 stops it
        function timerstop(): void { Lecture.stopTimer() }
        function timerpause(): void { Lecture.pauseTimer() }       // pause, or carry on
        function timerreset(): void { Lecture.resetTimer() }       // back to the full length
        function ink(what: string): void { Lecture.inkCommand(what) }   // undo | redo | clear
        function off(): void { Lecture.allOff() }
        function status(): string { return Lecture.status() }
    }
    IpcHandler {
        target: "cursor"
        function shake(on: bool): void { cursorFind.enabled = on }
        function flash(x: int, y: int): void { cursorFind.flash(x, y) }
        function droppreview(on: bool): void { dropPreview.enabled = on }
    }
    IpcHandler {
        target: "wallpaper"
        function status(): string { return WallState.status() }
        function menu(): void { wallMenu.toggle() }
        function on(): void  { WallState.cfg.hidden = false; WallState.cfg.running = true }
        function off(): void { WallState.cfg.hidden = false; WallState.cfg.running = false }   // hold the current frame
        function force(on: bool): void { WallState.force(on) }   // move on battery and through the heat guard, until the power source or mode changes
        function hide(): void { WallState.cfg.hidden = true }                                  // plain hyprpaper image
        function scene(name: string): string { return WallState.setScene(name) }   // silk aurora contours ink ridges sky
        function next(): string { return WallState.nextScene() }
        function speed(v: real): void { WallState.cfg.speed = v }
        function fps(n: int): void { WallState.cfg.fps = Math.max(2, Math.min(60, n)) }
        function heat(rpm: int): void { WallState.cfg.fanMax = Math.max(1500, Math.min(6000, rpm)) }   // heat guard: rest when the fan averages this (rpm over 2 min)
        function heatcap(max: int): void { WallState.cfg.heatCap = Math.max(60, Math.min(98, max)) }   // ...or the CPU reaches this, C
        function effect(name: string, on: bool): void { WallState.setEffect(name, on) }   // daylight music weather pointer agenda desks
        function weather(kind: string): void { WallState.wxDemo = kind === "auto" ? "" : kind }   // rain fog snow clear auto
        function season(kind: string): void { WallState.seasonDemo = kind === "auto" ? "" : kind }   // leaves snow petals fireflies none auto
        function grab(path: string): void { WallState.grabRequest(path) }                            // PNG of the focused screen's wallpaper, even under windows
        function gameday(on: bool): void { WallState.gameDemo = on }                                 // try the game-day paw
    }
    IpcHandler {
        target: "saver"         // idle screensaver (SaverState.qml)
        function status(): string { return SaverState.status() }
        function minutes(n: int): string { SaverState.setMinutes(n); return SaverState.status() }       // 0: off
        function scene(name: string): string { return SaverState.setScene(name) }                       // same | cycle | a scene name
        function preview(): void { SaverState.preview(8000) }                                           // up now for 8 s, whatever the conditions
        function stop(): void { SaverState.stop() }
        function battery(on: bool): void { SaverState.cfg.battery = on }                               // also start on battery (held frame)
        function clock(on: bool): void { SaverState.cfg.clock = on }
    }
    IpcHandler {
        target: "pet"
        function on(): void  { Pet.setEnabled(true) }
        function off(): void { Pet.setEnabled(false) }
        function status(): string { return Pet.status() }
        function pat(): void { Pet.petIt() }
        function feed(): void { Pet.giveFood() }
        function play(): void { Pet.playWith() }
        function bond(n: int): string { return Pet.setBond(n) }               // set the bond (0..100) and start its climb again
        function calm(on: bool): void { Pet.setCalm(on) }                     // no wandering, chasing, moths or thought bubbles
        function name(name: string): void { Pet.setName(name) }
        function animal(name: string): string { return Pet.setAnimal(name) }   // cat dog frog bird
        function trick(name: string): void { Pet.trick(name) }                // sit, lie down, spin, jump, beg, play dead, speak
        function focus(minutes: int): void { Pet.startFocus(minutes) }        // a focus timer; 0 stops it
        function cycle(): string { return PetFocus.startCycle() }             // work and break cycles with the habit lengths (PetFocus.qml)
        function cyclefor(work: real, rest: real, long: real): string { return PetFocus.startCycle(work, rest, long) }   // minutes, fractions allowed
        function skip(): string { return PetFocus.skip() }                    // focus: to the break; break: to the next round
        function stopfocus(): string { return PetFocus.stop() }               // stop the timer or cycle
        function focusstatus(): string { return PetFocus.status() }
        function hat(name: string): string { return Pet.setHat(name) }        // auto none santa witch party cap grad
        function menu(page: string): void { Pet.menuPage = page; Sys.popupRequest("pet") }
        function open(page: string): void { Pet.menuPage = page; Sys.popupSet(""); Sys.popupSet("pet") }   // always shows PAGE     // tricks focus looks settings ("" main)
        function say(): string { return PetSay.ask() }                        // what's up? opens its briefing (a second call closes it) and prints it
        function brief(): string { PetSay.refresh(); return PetSay.asText() }   // the briefing as text, nothing opened (fresh data a second later)
        function remark(what: string): string { return PetSay.sayNow(what) }  // battery | event: one of its own remarks, now
        function drop(): void { Pet.drop() }                                  // a leaf / snowflake / petal lands for it
        function friend(name: string): string { return Pet.setFriend(name) }   // none cat dog frog bird
        function roam(on: bool): void { Pet.setRoam(on) }                     // come down to an empty desktop
        function desk(on: bool): void { Pet.deskDemo = on }                   // pretend the desktop is empty
        function greet(): void { Pet.greet() }                                // as when the screen is unlocked
        function scene(name: string): string { return PetPlay.start(name) }  // tag ball perch food: the pet and its friend play together (or why not); stop; "" what is on
        function bug(): void { Pet.bug() }                                    // send a moth along the bar
        function game(): string { return PetScore.toggle() }                // treat catch on the empty desktop; a second call stops it
        function shy(on: bool): void { Pet.setShy(on) }                       // hide while the screen or camera is captured
        function coat(name: string): string { return Pet.setCoat(name) }      // tiger white regalia tabby panther
        function nap(on: bool): void { Pet.napping = on }
        function chase(on: bool): void { Pet.setChase(on) }
        function point(x: int): void { Pet.pointDemo = x }      // pretend the pointer is at bar x; -1 ends it
        function journal(): string { return PetArc.report() }                 // days together, counts, milestones, diary
        function celebrate(id: string): string { return PetArc.replay(id) }   // show a milestone again ("" the latest); records nothing
        function sounds(on: bool): void { PetSound.setEnabled(on) }                   // its sounds (PetSound.qml), off unless turned on
        function soundlevel(name: string): string { return PetSound.setLevel(name) }  // quiet soft normal
        function sound(name: string): string { return PetSound.test(name) }           // play one now, or say why it stays quiet
        // its habits (PetPrefs.qml lists the keys): bedtime wake meeting lively bell hunger
        function set(key: string, value: string): string { return PetPrefs.setHabit(key, value) }
        function get(key: string): string { return PetPrefs.getHabit(key) }
        function habits(): string { return PetPrefs.list() }
        function resethabits(): string { return PetPrefs.reset() }
        function sign(name: string): string { return PetSign.setSign(name) }      // none mail battery event temp (PetSign.qml)
        function remind(when: string, text: string): string { return PetRemind.add(when, text) }   // 20m 1h30 14:45 2:30pm; prints what it understood
        function reminders(): string { return PetRemind.list() }
        function remindcancel(which: string): string { return PetRemind.cancelNth(which) }   // a number from `reminders`, or all
        function reminddone(): string { return PetRemind.done() }        // acknowledge the one showing now
        function secrets(): string { return PetSecrets.report() }                 // how many of its secrets are found (PetSecrets.qml)
        function secret(name: string): string { return PetSecrets.demo(name) }    // try one; nothing is recorded
        function secretday(day: string): string { return PetSecrets.pretend(day) }   // pretend it is that day ("" ends it); nothing is recorded
    }
    IpcHandler {
        target: "breaks"        // Breaks.qml: reminders to stand up; off until `on`
        function status(): string { return Breaks.status() }
        function on(): void { Breaks.setEnabled(true) }
        function off(): void { Breaks.setEnabled(false) }
        function reset(): void { Breaks.reset() }
        function set(key: string, value: string): string { return Breaks.setKey(key, value) }     // workMinutes restMinutes snoozeMinutes
    }
    IpcHandler {
        target: "charge"        // Charge.qml: battery charge limit (asks for the password through polkit)
        function status(): string { return Charge.status() }
        function set(name: string): void { Charge.set(name) }       // full_charge | balanced | max_lifespan | cap
        function toggle(): void { Charge.toggle() }                 // full charge <-> the docked cap
        function next(): void { Charge.next() }
    }
    IpcHandler {
        target: "panel"
        function toggle(): void { panel.visible = !panel.visible }
        function open(): void   { panel.visible = true }
        function close(): void  { panel.visible = false }
    }
    IpcHandler {
        target: "cam"           // webcam bubble (CamBubble.qml); screen-record --cam uses on/off/status
        function toggle(): void { CamState.toggle() }
        function on(): void { CamState.on() }           // also moves it to the focused screen
        function off(): void { CamState.off() }
        function size(px: int): int { return CamState.setSize(px) }   // diameter, 120-480
        function use(device: string): string { return CamState.use(device) }   // that camera (see `cams`); turns it on
        function next(): void { CamState.next() }       // the next camera
        function status(): string { return CamState.status() }
    }
    IpcHandler {
        target: "osd"
        function level(kind: string, text: string, percent: int): void { osd.show(kind, text, percent) }   // not "show": that is a qs ipc subcommand
    }
    IpcHandler {
        target: "switcher"      // Alt+Tab / Alt+Shift+Tab (Switcher.qml)
        function next(): void { switcher.step(1) }
        function prev(): void { switcher.step(-1) }
        function commit(): void { switcher.commit() }
    }
    IpcHandler {
        target: "launcher"
        function toggle(): void { launcher.toggle() }
        // straight into a mode: = calc, : emoji, v clipboard, w windows, / files, ? keys, o org ("" = apps);
        // the same prefix again while it is open closes it
        function open(prefix: string): void { launcher.open(prefix) }
        // apps with TEXT already typed, e.g. "event 2026-11-20 " (Calendar.qml's "+ Add event")
        function openWith(text: string): void { launcher.openWith(text) }
    }
    IpcHandler {
        target: "picker"
        // used by ~/.local/bin/qs-pick: file of lines, fifo for the answer, placeholder text
        function open(items: string, out: string, title: string): void { picker.open(items, out, title) }
        // the same, and run `cmd INDEX` each time the highlight moves (live preview)
        // the same as open, with results ordered by match quality (see Picker.qml "ranked")
        function openranked(items: string, out: string, title: string): void { picker.open(items, out, title); picker.ranked = true }
        // start: the line highlighted at first
        function openlive(items: string, out: string, title: string, cmd: string, start: int): void { picker.open(items, out, title); picker.startIndex = start; picker.liveCmd = cmd }
        // ask for a line of text (secret: show dots); the fifo gets "ok:<text>" or "cancel"
        function ask(out: string, title: string, secret: bool): void { picker.ask(out, title, secret) }
    }
    IpcHandler {
        target: "shot"          // ~/.local/bin/screenshot edit (Print)
        function edit(): void { shot.edit() }
        function cancel(): void { shot.cancel() }
    }
    IpcHandler {
        target: "sharepick"     // ~/.local/bin/qs-share-pick (xdph custom_picker_binary)
        // file with the parsed lists (JSON), fifo for the [SELECTION] line or "cancel"
        function open(lists: string, out: string): void { sharePick.open(lists, out) }
    }
    IpcHandler {
        target: "dashboard"
        function toggle(): void { dashboard.toggle() }
        function open(): void   { dashboard.visible = true }
        function close(): void  { dashboard.visible = false }
        function peek(): void   { dashboard.peek() }     // shown without taking the keyboard
    }
    IpcHandler {
        target: "overview"
        function toggle(): void { overview.toggle() }
    }
    IpcHandler {
        target: "sound"
        // play a cue by its freedesktop name (camera-shutter, complete, bell, ...), if sounds are on
        function play(name: string): void { Sys.sound(name) }
        function enable(on: bool): void { Sys.setSounds(on) }
    }
    IpcHandler {
        target: "notif"
        function dnd(): string { return Notif.dnd ? "on" : "off" }
        function setDnd(on: bool): void { Notif.setDnd(on) }
        function toggleDnd(): void { Notif.setDnd(!Notif.dnd) }
        function clear(): void { Notif.clear() }
        function forget(index: int): void { Notif.forget(index) }      // 0 = newest
        function dismissAll(): void { Notif.dismissAll() }
        // per-app rule: mute (dropped unless critical), list (no popup), normal
        function rule(app: string, mode: string): string { return Notif.setRule(app, mode) ? Notif.ruleFor(app) : "usage: rule APP mute|list|normal" }
        function rules(): string { return Notif.rulesText() }
        function snoozed(): int { return Notif.snoozed.length }
    }
    IpcHandler {
        target: "lights"        // the GVM video lights (Lights.qml); the pill is in Bar.qml
        function status(): string { return Lights.status() }
        function on(): void { Lights.on() }
        function off(): void { Lights.off() }
        function quick(): void { Lights.quick() }           // the pill's right-click
        function preset(name: string): void { Lights.preset(name) }
        function window(): void { Lights.openWindow() }
    }
    IpcHandler {
        target: "bar"
        function on(): void     { Sys.barVisible = true }    // ("show" collides with `qs ipc show`)
        function off(): void    { Sys.barVisible = false }
        function status(): string { return Sys.barVisible ? "shown" : "hidden" }
        // a script-backed pill changed (sent by ~/.local/bin/bar-refresh)
        function refresh(): void { Sys.refreshNow() }
        // open or close a pill popup on the focused screen:
        // calendar | mixer | wifi | bluetooth | profile | power | media | notifs | pet | lights
        function popup(name: string): void { Sys.popupRequest(name) }
        // the same without toggling, for scripts: open is a no-op when it is already open, close when none is
        function open(name: string): void { Sys.popupSet(name) }
        function close(): void { Sys.popupSet("") }
    }
    // background jobs (Health.qml, ~/.local/bin/shell-health): the pill is in Bar.qml; a job that
    // just went from ok to failing or stale is said once on the island
    Connections {
        target: Health
        function onNewFailure(job) {
            island.say({ kind: "health", urgency: "critical", glyph: "⚠", title: job.name + (job.state === "failed" ? " is failing" : " is behind"), sub: job.why, ms: 6000 })
        }
        function onRecovered(job) {
            island.say({ kind: "health", glyph: "✓", title: job.name + " is working again", sub: job.why, ms: 4000 })
        }
    }
    // low disk or "restart needed", once per boot each (Health.noticeSay); other notices stay in the popup
    Connections {
        target: Health
        function onNoticeSay(row) {
            island.say({ kind: "health", glyph: "ℹ", title: row.name, sub: row.why, ms: 7000 })
        }
    }
    IpcHandler {
        target: "health"        // Health.qml
        function status(): string { return Health.summary() }
        function refresh(): void  { Health.refresh() }
        function list(): string   { return Health.table() }
    }
    IpcHandler {
        target: "island"        // the short message that grows out of the top centre of the bar (Island.qml)
        function say(title: string, sub: string): void { island.say({ kind: "say", glyph: "", title: title, sub: sub, ms: 4000 }) }
        function sayAs(urgency: string, title: string, sub: string): void { island.say({ kind: "say", urgency: urgency, glyph: "", title: title, sub: sub, ms: urgency === "critical" ? 8000 : 4000 }) }
        function on(): void     { island.setEnabled(true) }
        function off(): void    { island.setEnabled(false) }
        function status(): string { return island.enabled ? "on" : "off" }
    }
    IpcHandler {
        target: "quiet"         // calendar-aware Do Not Disturb (Quiet.qml, rules in ~/.config/shell/quiet.json)
        function status(): string { return Quiet.status() }
        function on(): void     { Quiet.setEnabled(true) }
        function off(): void    { Quiet.setEnabled(false) }
        function skip(): string { return Quiet.skip() }              // leave the event now under way un-silenced
        function resync(): void { Quiet.resync() }                   // display-menu after it ends presenting
    }
    IpcHandler {
        target: "session"       // Session.qml; opt-in session restore, settings in ~/.config/shell/session.json
        function status(): string  { Session.refresh(); return Session.status() }
        function save(): void      { Session.save() }
        function restore(): void   { Session.restore() }
        function list(): string    { Session.refresh(); return Session.listing }      // what the last refresh saw
        function on(): void        { Session.setEnabled(true) }
        function off(): void       { Session.setEnabled(false) }
    }
    IpcHandler {
        target: "settings"      // Settings.qml (Super+comma)
        function toggle(): void { settings.toggle() }
        function open(page: string): void { settings.open(page) }      // appearance bar notifications quiet saver lecture recording pet launcher power health session focus about
        function close(): void { settings.close() }
    }
    IpcHandler {
        target: "profile"       // focus profiles (Profiles.qml, ~/.config/shell/profiles.json)
        function apply(name: string): string { return Profiles.apply(name) }
        function end(): string { return Profiles.end() }
        function status(): string { return Profiles.status() }
        function list(): string { return Profiles.listText() }
    }
    IpcHandler {
        target: "clock"         // Clocks.qml: timers, alarms, stopwatch (qs ipc call clock list)
        function timer(spec: string): string { return Clocks.timerSpec(spec) }        // 10m tea | 1h30 | 25 (minutes) | 90s
        function alarm(spec: string): string { return Clocks.alarmSpec(spec) }        // 7:30 | 6:45am weekdays stand-up | tomorrow 9
        function list(): string { return Clocks.list() }
        function cancel(id: string): string { return Clocks.cancel(id) }              // a timer or alarm id from list, or all (timers)
        function stopwatch(action: string): string { return Clocks.stopwatchAction(action) }   // start stop toggle lap reset status
        function snooze(): string { return Clocks.snooze() }                          // the alarm that is ringing
    }
    IpcHandler {
        target: "join"          // Join.qml
        function status(): string { return Join.status() }
        function open(): void   { const e = Join.event; if (e) Join.open(e.url) }
    }
}
