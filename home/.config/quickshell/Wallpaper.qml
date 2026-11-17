// Animated wallpaper: one layer per screen under the windows, drawn by a scene shader
// (shaders/NAME.frag.qsb) in the desktop palette. Scenes: silk, aurora, contours, ink,
// ridges, sky (the real night sky, WallSky.qml). Effects that sit on any scene: time-of-day
// colours, music, weather, pointer, agenda band (WallAgenda.qml), a different view per desktop,
// seasonal touches (WallSeason.qml: leaves, snow, petals, fireflies, the game-day paw).
// State, feeds and settings are in WallState.qml. The pattern is continuous across screens
// because each one passes its position in the layout. Moves on mains power only.
//
//   qs ipc call wallpaper status | on | off | scene NAME | next | speed 0.012
//   qs ipc call wallpaper effect NAME true|false      (daylight music weather pointer agenda desks)
//   qs ipc call wallpaper weather rain|fog|snow|clear|auto      (try the weather overlay)
//   ~/.local/bin/wallpaper-menu      pick a scene or flip an effect
//
// hyprpaper is the fallback: WallState starts it when this is hidden and stops it otherwise.
// Shaders: edit shaders/src/, then run shaders/build.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: wall
    required property var modelData
    screen: modelData
    readonly property string scene: WallState.cfg.scene
    readonly property bool dark: Theme.dark
    property int fade: 900                    // ms, colour crossfade on dark/light and time of day

    readonly property var monitor: Hyprland.monitorFor(modelData)
    readonly property int desktop: monitor && monitor.activeWorkspace && monitor.activeWorkspace.id >= 11
                                   ? Math.floor(monitor.activeWorkspace.id / 10) : Sys.desktop
    property real deskPos: WallState.cfg.desks ? desktop : 1
    Behavior on deskPos { enabled: WallState.moving; NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }

    // "rest": a screen whose desktop has a tiled window on it is mostly hidden, so it holds
    // its frame and draws nothing new. When the windows go it catches up to the shared
    // clock over a moment (the scene stays continuous with the other screens).
    // (also while the screensaver is drawing the scene on top: no point rendering it twice)
    readonly property bool covered: SaverState.shown || (WallState.cfg.rest && monitor && monitor.activeWorkspace
        && Hyprland.toplevels.values.some(t => t.workspace && t.workspace.id === wall.monitor.activeWorkspace.id
                                               && !(t.lastIpcObject && t.lastIpcObject.floating)))
    // nothing at all open on this screen's desktop, and this is the screen the pet is on
    readonly property bool empty: !!monitor && !!monitor.activeWorkspace
        && !Hyprland.toplevels.values.some(t => t.workspace && t.workspace.id === wall.monitor.activeWorkspace.id)
    readonly property bool petHere: Pet.roam && (empty || Pet.deskDemo)
        && Pet.showsOn(Pet.screenKey(modelData), !!monitor && !!Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === monitor.name)
    readonly property real sharedTime: WallState.clock * WallState.cfg.speed
    property real heldTime: 0
    property real lag: 0
    readonly property real sceneTime: covered ? heldTime : sharedTime - lag
    onCoveredChanged: {
        catchUp.stop()
        if (covered) heldTime = sharedTime - lag
        else { lag = sharedTime - heldTime; catchUp.start() }
    }
    NumberAnimation { id: catchUp; target: wall; property: "lag"; to: 0; duration: 1400; easing.type: Easing.InOutCubic }

    visible: !WallState.cfg.hidden
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-wallpaper"
    // Bottom, not Background: hyprpaper re-creates its background layer on every dark/light
    // switch, which would land on top of this one if they shared a layer
    WlrLayershell.layer: WlrLayer.Bottom
    // the keyboard only while the pet's menu is open here, so Escape can close it (as Panel.qml)
    WlrLayershell.keyboardFocus: menuAt !== null ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: Theme.solidBg

    // ---- the pet's menu when it is down on the desktop: it opens above the pet, not from the
    // bar a screen-height away (and works with the bar hidden) ----
    property Item menuAt: null
    onPetHereChanged: if (!petHere) menuAt = null
    // While its menu is open here, and afterwards until the focus is back on this screen (or the
    // pointer has left it), the pet stays put (Pet.hold): the menu closing sends the keyboard
    // focus to the last window used, which on an empty desktop is on some other screen.
    readonly property string petKey: Pet.screenKey(modelData)
    readonly property bool focusedHere: !!monitor && !!Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === monitor.name
    function letGo() { holdCheck.stop(); holdEnd.stop(); if (Pet.hold === petKey) Pet.hold = "" }
    onMenuAtChanged: {
        if (menuAt !== null) petPop.last = menuAt
        if (menuAt !== null) { holdCheck.stop(); holdEnd.stop(); Pet.hold = petKey }
        else if (Pet.hold === petKey) { holdCheck.restart(); holdEnd.restart() }
    }
    onFocusedHereChanged: if (focusedHere && menuAt === null && holdEnd.running && !holdCheck.running) letGo()
    Timer { id: holdCheck; interval: 600; onTriggered: if (wall.focusedHere) wall.letGo() }      // the focus never left
    Timer { id: holdEnd; interval: 20000; onTriggered: wall.letGo() }
    Connections { target: petHover; function onHoveredChanged() { if (!petHover.hovered && wall.menuAt === null && holdEnd.running) wall.letGo() } }
    PopupWindow {
        id: petPop
        visible: wall.menuAt !== null
        anchor.item: content
        // where the pet is, or was when the menu closed: falling back to 0,0 showed the menu in
        // the corner of the screen for a frame on its way out
        property Item last: null
        readonly property Item at: wall.menuAt || last
        anchor.rect.x: at ? at.x : 0
        anchor.rect.y: at ? at.y + at.height - at.size - 6 : 0
        anchor.rect.width: at ? at.size : 1
        anchor.rect.height: 1
        anchor.edges: Edges.Top
        anchor.gravity: Edges.Top
        color: "transparent"
        implicitWidth: 290 + 32
        implicitHeight: petPopBody.implicitHeight + 32 + 8
        Rectangle {
            anchors.fill: parent
            anchors.bottomMargin: 8
            radius: 12
            color: Theme.panelBg
            border.width: 2
            border.color: Theme.accentBg
            focus: true                         // the popup is what gets the keys (checked on the bar's, 2026-11-12)
            Keys.onEscapePressed: wall.menuAt = null
            Loader {
                id: petPopBody
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                active: wall.menuAt !== null
                sourceComponent: Component { PetMenu { screenKey: Pet.screenKey(wall.modelData); onDone: wall.menuAt = null } }
            }
        }
    }
    // click-outside-to-close, armed a moment after the popup shows (as on the bar)
    property bool petGrab: false
    Timer { id: petGrabDelay; interval: 120; onTriggered: wall.petGrab = petPop.visible }
    Connections { target: petPop; function onVisibleChanged() { wall.petGrab = false; if (petPop.visible) petGrabDelay.restart() } }
    HyprlandFocusGrab { windows: [petPop, wall]; active: wall.petGrab; onCleared: wall.menuAt = null }

    function grab(path) { content.grabToImage(function(res) { res.saveToFile(path) }) }
    Connections {
        target: WallState
        function onGrabRequest(path) {
            if (wall.monitor && Hyprland.focusedMonitor && wall.monitor.name === Hyprland.focusedMonitor.name) wall.grab(path)
        }
    }

    Item {
        id: content
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: wall.menuAt = null

        // pointer, eased so the scene follows rather than snaps
        HoverHandler { id: hover; enabled: WallState.cfg.pointer && WallState.moving && !wall.covered }
        property real ptrX: hover.point.position.x
        property real ptrY: hover.point.position.y
        property real ptrOn: hover.hovered ? 1 : 0
        Behavior on ptrX { SmoothedAnimation { velocity: 1600 } }
        Behavior on ptrY { SmoothedAnimation { velocity: 1600 } }
        Behavior on ptrOn { NumberAnimation { duration: 600 } }

        ShaderEffect {
            id: fx
            anchors.fill: parent
            // kept as a texture: something moving over it (the pet) then costs a blit, not a
            // fresh run of the scene shader over the whole screen
            layer.enabled: true
            fragmentShader: Qt.resolvedUrl("shaders/" + (wall.scene === "sky" ? "skybg" : wall.scene) + ".frag.qsb")
            property real time: wall.sceneTime
            property real unit: 1500
            // sky: the horizon's y in layout px; other scenes: lighting strength
            property real relief: wall.scene === "sky" ? sky.horizonY : 0.9
            property point origin: Qt.point(wall.modelData.x, wall.modelData.y)
            property point size: Qt.point(width, height)
            property color c0: WallState.tone(wall.scene, wall.dark, 0)
            property color c1: WallState.tone(wall.scene, wall.dark, 1)
            property color c2: WallState.tone(wall.scene, wall.dark, 2)
            property color c3: WallState.tone(wall.scene, wall.dark, 3)
            property color c4: WallState.tone(wall.scene, wall.dark, 4)
            property vector4d stops: WallState.stops(wall.scene, wall.dark)
            property vector4d audio: wall.covered || !WallState.cfg.music ? Qt.vector4d(0, 0, 0, 0) : Qt.vector4d(WallState.bass, WallState.mid, WallState.treble, WallState.level)
            property vector4d pointer: Qt.vector4d(wall.modelData.x + content.ptrX, wall.modelData.y + content.ptrY, content.ptrOn, 0)
            property real darkAmt: wall.dark ? 1 : 0
            property vector4d env: Qt.vector4d(WallState.dayPhase, WallState.sunSin, wall.deskPos, darkAmt)
            property vector4d wx: Qt.vector4d(WallState.wxRain, WallState.wxFog, WallState.wxCloud, WallState.wxSnow)
            property vector4d box: Qt.vector4d(WallState.layoutBox.x, WallState.layoutBox.y, WallState.layoutBox.width, WallState.layoutBox.height)
            // the terrain scene's height map; other scenes have no such sampler and ignore it
            property var terrain: Image {
                source: wall.scene === "terrain" ? Qt.resolvedUrl("assets/terrain-clemson.png") : ""
                visible: false; smooth: false; cache: true
            }
            Behavior on c0 { ColorAnimation { duration: wall.fade } }
            Behavior on c1 { ColorAnimation { duration: wall.fade } }
            Behavior on c2 { ColorAnimation { duration: wall.fade } }
            Behavior on c3 { ColorAnimation { duration: wall.fade } }
            Behavior on c4 { ColorAnimation { duration: wall.fade } }
            Behavior on darkAmt { NumberAnimation { duration: wall.fade } }
        }

        WallSky {
            id: sky
            anchors.fill: parent
            visible: wall.scene === "sky"
            origin: Qt.point(wall.modelData.x, wall.modelData.y)
            dark: wall.dark
            box: WallState.layoutBox
            sunAlt: WallState.sunAlt
            lat: WallState.cfg.lat
            lng: WallState.cfg.lng
            when: WallState.nowOverride
            live: WallState.live
            moving: WallState.moving
        }

        ShaderEffect {
            anchors.fill: parent
            visible: WallState.wxRain + WallState.wxFog + WallState.wxSnow > 0.01
            fragmentShader: Qt.resolvedUrl("shaders/weather.frag.qsb")
            property real time: wall.covered ? 0 : WallState.clock
            property real unit: 1500
            property point origin: fx.origin
            property point size: fx.size
            property color c3: fx.c3
            property vector4d wx: fx.wx
            // the rest of the shared uniform block, unused by this shader
            property real relief: 0
            property color c0: fx.c0
            property color c1: fx.c1
            property color c2: fx.c2
            property color c4: fx.c4
            property vector4d stops: fx.stops
            property vector4d audio: fx.audio
            property vector4d pointer: fx.pointer
            property vector4d env: fx.env
            property vector4d box: fx.box
        }

        WallSeason {
            anchors.fill: parent
            visible: WallState.cfg.season && (WallState.seasonKind !== "" || WallState.gameShown !== null)
            time: wall.covered ? 0 : WallState.clock
            dark: wall.dark
        }

        // A click anywhere on the wallpaper closes the pet's menu. The focus grab cannot do it:
        // this window is on its list (so the pet stays clickable), and on an empty desktop
        // this window is everything there is to click on.
        MouseArea {
            anchors.fill: parent
            z: 20
            enabled: wall.menuAt !== null
            acceptedButtons: Qt.AllButtons
            onPressed: wall.menuAt = null
        }
        PetSky { anchors.fill: parent }     // now and then something crosses the sky (PetSecrets.qml)

        // The pet (Pet.qml) comes down here from the bar when this desktop has nothing open
        // on it: twice the size, the whole width to itself, following the pointer.
        HoverHandler { id: petHover }
        Repeater {
            model: 2                        // the pet, and its friend if it has one
            PetSprite {
                required property int index
                who: index
                k: 2
                baseZ: 5
                floorGap: 46                // clear of the agenda band
                spotTag: "#desk"
                screenName: Pet.screenKey(wall.modelData)
                shown: wall.petHere
                gaps: [{ from: 24, to: content.width - 24 }]
                bellX: content.width - 24 - size
                musicX: content.width / 2
                clockX: content.width / 2 - size
                pointerX: petHover.hovered ? petHover.point.position.x : -1
                id: deskPet
                onMenuRequested: wall.menuAt = wall.menuAt === deskPet ? null : deskPet
            }
        }
        PetGame { anchors.fill: parent; z: 6; here: wall.petHere; pointerX: petHover.hovered ? petHover.point.position.x : -1 }     // treat catch with the pet (PetScore.qml)
        Rectangle {     // its tooltip down here (the bar draws tooltips only for its own window)
            readonly property Item at: Sys.tipWindow === wall ? Sys.tipTarget : null
            visible: at !== null && Sys.tipText !== "" && wall.menuAt === null
            z: 10
            width: deskTip.implicitWidth + 22; height: deskTip.implicitHeight + 16; radius: 8
            x: at ? Math.max(8, Math.min(content.width - width - 8, at.x)) : 0
            y: at ? at.y + at.height - at.size - height - 8 : 0
            color: Theme.solidBg
            border.width: 1
            border.color: Theme.accentBg
            Text {
                id: deskTip
                anchors.centerIn: parent
                textFormat: Text.StyledText
                text: Sys.tipText.replace(/\n/g, "<br>")
                color: Theme.fg
                font { family: Theme.font; pixelSize: 13 }
            }
        }

        WallAgenda {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
            visible: WallState.cfg.agenda
        }
    }
}
