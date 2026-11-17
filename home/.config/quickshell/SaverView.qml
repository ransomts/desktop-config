// One screen of the screensaver (SaverState.qml has the logic, Saver.qml the windows): the
// scene full-screen, dimmed, a large faint clock and date that drift slowly round the screen
// (no pixel holds the same light for long), and on one screen the pet asleep beside the clock.
// Fades in over 1.5 s; any key, click, scroll or pointer move takes it away fast.
import QtQuick
import Quickshell

Item {
    id: view
    required property var screenObj           // x, y, name of this screen in the layout
    property int index: 0                     // which screen: each drifts on its own path
    property bool flat: false                 // a plain stand-in for the scene shader (test pictures)
    readonly property string scene: SaverState.scene
    readonly property bool dark: Theme.dark
    readonly property bool petHere: !!screenObj && screenObj.name === SaverState.petScreen

    // in slowly, out fast (two animations: a Behavior picked its duration before `shown` flipped)
    opacity: 0
    NumberAnimation { id: fadeIn; target: view; property: "opacity"; to: 1; duration: 1500; easing.type: Easing.InOutQuad }
    NumberAnimation { id: fadeOut; target: view; property: "opacity"; to: 0; duration: 220; easing.type: Easing.OutQuad }
    function fade() {
        firstPos = Qt.point(-1, -1)
        if (SaverState.shown) { fadeOut.stop(); fadeIn.start() } else { fadeIn.stop(); fadeOut.start() }
    }
    Component.onCompleted: if (SaverState.shown) fade()

    // ---- input: anything at all dismisses (the idle monitor usually beats us to it) ----
    focus: true
    Keys.onPressed: event => { SaverState.dismiss(); event.accepted = true }
    property point firstPos: Qt.point(-1, -1)
    // a surface appearing under a resting pointer gets an "enter": only real movement counts,
    // and nothing in the first half second
    MouseArea {
        anchors.fill: parent
        z: 50
        hoverEnabled: view.visible
        acceptedButtons: Qt.AllButtons
        cursorShape: Qt.BlankCursor
        onPressed: SaverState.dismiss()
        onWheel: SaverState.dismiss()
        onPositionChanged: mouse => {
            if (view.firstPos.x < 0 || !SaverState.shown || Date.now() - SaverState.shownAt < 500) { view.firstPos = Qt.point(mouse.x, mouse.y); return }
            if (Math.abs(mouse.x - view.firstPos.x) + Math.abs(mouse.y - view.firstPos.y) > 6) SaverState.dismiss()
        }
    }
    Connections { target: SaverState; function onShownChanged() { view.fade() } }

    // ---- the scene: the wallpaper's shader and its whole uniform block (shaders/src/common.glsl) ----
    readonly property real sceneTime: WallState.clock * WallState.cfg.speed
    ShaderEffect {
        id: fx
        anchors.fill: parent
        visible: !view.flat
        // held frame: kept as a texture, so the clock moving once a minute costs a blit
        layer.enabled: !SaverState.moving
        fragmentShader: Qt.resolvedUrl("shaders/" + (view.scene === "sky" ? "skybg" : view.scene) + ".frag.qsb")
        property real time: view.sceneTime
        property real unit: 1500
        property real relief: view.scene === "sky" ? WallState.layoutBox.y + WallState.layoutBox.height * 0.92 : 0.9
        property point origin: Qt.point(view.screenObj ? view.screenObj.x : 0, view.screenObj ? view.screenObj.y : 0)
        property point size: Qt.point(width, height)
        property color c0: WallState.tone(view.scene, view.dark, 0)
        property color c1: WallState.tone(view.scene, view.dark, 1)
        property color c2: WallState.tone(view.scene, view.dark, 2)
        property color c3: WallState.tone(view.scene, view.dark, 3)
        property color c4: WallState.tone(view.scene, view.dark, 4)
        property vector4d stops: WallState.stops(view.scene, view.dark)
        property vector4d audio: Qt.vector4d(0, 0, 0, 0)
        property vector4d pointer: Qt.vector4d(0, 0, 0, 0)
        property vector4d env: Qt.vector4d(WallState.dayPhase, WallState.sunSin, WallState.cfg.desks ? Sys.desktop : 1, view.dark ? 1 : 0)
        property vector4d wx: Qt.vector4d(0, 0, WallState.wxCloud, 0)
        property vector4d box: Qt.vector4d(WallState.layoutBox.x, WallState.layoutBox.y, WallState.layoutBox.width, WallState.layoutBox.height)
        property var terrain: Image {
            source: view.scene === "terrain" ? Qt.resolvedUrl("assets/terrain-clemson.png") : ""
            visible: false; smooth: false; cache: true
        }
    }
    Rectangle {                               // the stand-in: the scene's own colours, low to high
        anchors.fill: parent
        visible: view.flat
        gradient: Gradient {
            GradientStop { position: 0.0; color: fx.c0 }
            GradientStop { position: 0.6; color: fx.c1 }
            GradientStop { position: 1.0; color: fx.c3 }
        }
    }
    // the sky scene's stars and moon, drawn once when it comes up (as LockView.qml)
    Loader {
        anchors.fill: parent
        enabled: false
        active: view.scene === "sky" && view.visible
        source: Qt.resolvedUrl("WallSky.qml")
        onLoaded: {
            item.live = false
            item.origin = Qt.binding(() => fx.origin)
            item.box = Qt.binding(() => WallState.layoutBox)
            item.dark = Qt.binding(() => view.dark)
            item.lat = Qt.binding(() => WallState.cfg.lat)
            item.lng = Qt.binding(() => WallState.cfg.lng)
            item.sunAlt = Qt.binding(() => WallState.sunAlt)
            item.when = new Date()
        }
    }
    Rectangle { anchors.fill: parent; color: Theme.tint(Theme.solidBg, view.dark ? 0.38 : 0.30) }

    // ---- the clock: drifts along a slow Lissajous path inside the screen ----
    // t moves with the scene's frames while it animates and once a minute on a held frame.
    property real t: Date.now() / 1000
    Connections {
        target: WallState
        enabled: view.visible && SaverState.moving
        function onClockChanged() { view.t = Date.now() / 1000 }
    }
    SystemClock { id: wall; enabled: view.visible; precision: SystemClock.Minutes; onDateChanged: view.t = Date.now() / 1000 }
    // where a w x h block sits at time t (seconds) on a W x H screen: a full sweep across
    // takes about 11 minutes, up and down about 7, each screen out of step with the others
    function drift(t, W, H, w, h) {
        const mx = Math.max(24, W * 0.06), my = Math.max(24, H * 0.08)
        const fx = (Math.sin(t * 2 * Math.PI / 660 + index * 1.7) + 1) / 2
        const fy = (Math.sin(t * 2 * Math.PI / 430 + index * 2.3 + 0.9) + 1) / 2
        return Qt.point(mx + Math.max(0, W - 2 * mx - w) * fx, my + Math.max(0, H - 2 * my - h) * fy)
    }
    // room is kept on the clock's right for the pet (LockPet sits beside it when it fits)
    readonly property point at: drift(t, width, height, stack.width + (pet.active ? 190 : 0), stack.height)
    Column {
        id: stack
        objectName: "clock"
        visible: SaverState.cfg.clock
        x: Math.round(view.at.x)
        y: Math.round(view.at.y)
        spacing: 4
        Text {
            text: Qt.formatDateTime(wall.date, "HH:mm")
            color: Theme.fg
            opacity: 0.62
            font { family: Theme.font; pixelSize: Math.round(Math.min(view.width, view.height * 1.6) * 0.085); bold: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(wall.date, "dddd, MMMM d")
            color: Theme.fg
            opacity: 0.5
            font { family: Theme.font; pixelSize: Math.round(Math.min(view.width, view.height * 1.6) * 0.017) }
        }
    }

    // The pet asleep beside the clock: the lock screen's (LockPet.qml), by file name so a fault
    // there costs the pet and not the saver. No timers in it; it reads its saved state only.
    QtObject { id: calm; property string phase: "idle"; property string typed: ""; property bool unlocking: false; property int fails: 0 }
    Loader {
        id: pet
        anchors.fill: parent
        enabled: false
        active: view.petHere && SaverState.cfg.clock && view.visible
        source: Qt.resolvedUrl("LockPet.qml")
        onLoaded: { item.ctl = calm; item.around = stack }
    }
}
