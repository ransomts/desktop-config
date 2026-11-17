// What one screen shows while locked: a still frame of the wallpaper scene, dimmed,
// with the time, the date and the password field. Every screen shows the same state, but
// only one (`form`) has the field, the pet and the notes; the rest have the clock and the date.
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "palettes.js" as Pal
import "sky.js" as Sky

Item {
    id: view
    required property var ctl               // the ShellRoot: typed, phase, key(), dark, scene
    required property var screenObj
    property bool demo: false               // preview mode: show a few dots and no focus
    // the one screen with the password field, the pet and the notes (lockscreen.qml's formScreen);
    // the others show the wallpaper, the clock and the date
    readonly property bool form: !screenObj || !ctl.formScreen || screenObj.name === ctl.formScreen

    readonly property string font: "FiraCode Nerd Font"
    readonly property color ink: "#e6e1dc"
    readonly property color accent: ctl.dark ? "#f56600" : "#ff8f2e"
    readonly property color red: "#e5484d"
    readonly property string scene: !Pal.palettes[ctl.scene] ? "contours" : ctl.scene
    // the sky and the ridges are drawn for where the sun really is (as Wallpaper.qml, from sky.js);
    // worked out when locking and again as the minute clock turns, the stars every five minutes
    readonly property bool lit: scene === "sky" || scene === "ridges"
    property real sunAlt: -30               // degrees
    property real dayPhase: 0.5             // 0 midnight .. 1
    property var skyWhen: null
    function sunNow() {
        if (!lit) return
        try {
            const d = new Date()
            sunAlt = Sky.sunAltitude(d, ctl.lat, ctl.lng).alt
            dayPhase = (d.getHours() * 60 + d.getMinutes()) / 1440
            if (!skyWhen || d.getTime() - skyWhen.getTime() >= 290000) skyWhen = d
        } catch (e) { }
    }
    onLitChanged: sunNow()
    Component.onCompleted: { sunNow(); fadeIn.start() }

    // ---- it fades in from the dark when the lock comes up, and out again once the password is
    // right (after a moment for the pet's heart; lockscreen.qml opens the lock 600 ms after
    // `unlocking`). The desktop itself cannot be faded: the compositor swaps it in one step. ----
    NumberAnimation { id: fadeIn; target: view; property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: fadeOut
        PauseAnimation { duration: 300 }
        NumberAnimation { target: view; property: "opacity"; to: 0; duration: 280; easing.type: Easing.InCubic }
    }
    Connections {
        target: view.ctl
        function onUnlockingChanged() { if (view.ctl.unlocking) { fadeIn.stop(); view.opacity = 1; fadeOut.start() } }
    }
    readonly property var pal: Pal.palettes[scene][ctl.dark ? "dark" : "light"]
    readonly property rect box: {
        let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
        for (const s of Quickshell.screens) {
            x0 = Math.min(x0, s.x); y0 = Math.min(y0, s.y)
            x1 = Math.max(x1, s.x + s.width); y1 = Math.max(y1, s.y + s.height)
        }
        return x1 > x0 ? Qt.rect(x0, y0, x1 - x0, y1 - y0) : Qt.rect(0, 0, 1920, 1080)
    }

    focus: !demo
    Keys.onPressed: event => { view.ctl.key(event); event.accepted = true }
    SystemClock { id: clock; precision: SystemClock.Minutes; onDateChanged: view.sunNow() }

    ShaderEffect {
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("shaders/" + (view.scene === "sky" ? "skybg" : view.scene) + ".frag.qsb")
        property real time: 37.0                     // one fixed frame: nothing animates while locked
        property real unit: 1500
        property real relief: view.scene === "sky" ? view.box.y + view.box.height * 0.92 : 0.9     // sky: the horizon's y (as WallSky.horizonY)
        property point origin: Qt.point(view.screenObj ? view.screenObj.x : 0, view.screenObj ? view.screenObj.y : 0)
        property point size: Qt.point(width, height)
        property color c0: view.pal.c[0]
        property color c1: view.pal.c[1]
        property color c2: view.pal.c[2]
        property color c3: view.pal.c[3]
        property color c4: view.pal.c[4]
        property vector4d stops: Qt.vector4d(view.pal.s[0], view.pal.s[1], view.pal.s[2], view.pal.s[3])
        property vector4d audio: Qt.vector4d(0, 0, 0, 0)
        property vector4d pointer: Qt.vector4d(0, 0, 0, 0)
        property vector4d env: view.lit ? Qt.vector4d(view.dayPhase, Math.sin(view.sunAlt * Math.PI / 180), 1, view.ctl.dark ? 1 : 0)
                                        : Qt.vector4d(0.5, 0.5, 1, view.ctl.dark ? 1 : 0)
        property vector4d wx: Qt.vector4d(0, 0, 0, 0)
        property vector4d box: Qt.vector4d(view.box.x, view.box.y, view.box.width, view.box.height)
        property var terrain: Image {
            source: view.scene === "terrain" ? Qt.resolvedUrl("assets/terrain-clemson.png") : ""
            visible: false; smooth: false
        }
    }
    // the sky scene's stars, planets and moon (WallSky.qml, the wallpaper's own, given this screen's
    // window onto the layout). By file name, so a fault in it costs the stars and not the lock.
    Loader {
        anchors.fill: parent
        enabled: false
        active: view.scene === "sky"
        source: Qt.resolvedUrl("WallSky.qml")
        onLoaded: {
            item.live = false
            item.origin = Qt.binding(() => Qt.point(view.screenObj ? view.screenObj.x : 0, view.screenObj ? view.screenObj.y : 0))
            item.box = Qt.binding(() => view.box)
            item.dark = Qt.binding(() => view.ctl.dark)
            item.lat = Qt.binding(() => view.ctl.lat)
            item.lng = Qt.binding(() => view.ctl.lng)
            item.sunAlt = Qt.binding(() => view.sunAlt)
            item.when = Qt.binding(() => view.skyWhen)
        }
    }
    Rectangle { anchors.fill: parent; color: "#0b0b0e"; opacity: view.ctl.dark ? 0.38 : 0.30 }

    Column {
        id: stack
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -parent.height * 0.06
        spacing: 10
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            color: view.ink
            font { family: view.font; pixelSize: 112; bold: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "dddd, MMMM d")
            color: view.accent
            font { family: view.font; pixelSize: 22 }
        }
        // how long until the next calendar event (LockNext.qml): loaded by file name, as the pet
        // below, so a mistake in that file leaves this line empty instead of breaking the lock
        Loader {
            id: nextNote
            anchors.horizontalCenter: parent.horizontalCenter
            height: 20
            enabled: false
            visible: view.form
            source: Qt.resolvedUrl("LockNext.qml")
            onLoaded: item.now = Qt.binding(() => clock.date)
        }
        Item { width: 1; height: 16; visible: view.form }

        Rectangle {
            id: field
            visible: view.form
            anchors.horizontalCenter: parent.horizontalCenter
            width: 340; height: 52; radius: 12
            color: Qt.rgba(22 / 255, 22 / 255, 26 / 255, 0.86)
            border.width: 2
            border.color: view.ctl.unlocking ? "#5fb36a" : view.ctl.phase === "wrong" || view.ctl.phase === "error" ? view.red
                        : view.ctl.phase === "checking" ? "#7a4fb0" : view.accent
            Behavior on border.color { ColorAnimation { duration: 150 } }
            readonly property int count: view.demo ? 6 : view.ctl.typed.length

            Row {
                anchors.centerIn: parent
                spacing: 9
                visible: field.count > 0 && view.ctl.phase !== "checking" && !view.ctl.unlocking
                Repeater {
                    model: Math.min(field.count, 22)
                    Rectangle { width: 9; height: 9; radius: 4.5; color: view.ink }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: field.count === 0 || view.ctl.phase === "checking" || view.ctl.unlocking
                text: view.ctl.unlocking ? "Welcome back" : view.ctl.phase === "checking" ? "Checking…" : "Type your password"
                color: "#8a8580"
                font { family: view.font; pixelSize: 14 }
            }
            transform: Translate { id: nudge }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: nudge; property: "x"; to: -12; duration: 50 }
                NumberAnimation { target: nudge; property: "x"; to: 12; duration: 80 }
                NumberAnimation { target: nudge; property: "x"; to: -8; duration: 70 }
                NumberAnimation { target: nudge; property: "x"; to: 0; duration: 60 }
            }
            Connections {
                target: view.ctl
                function onPhaseChanged() { if (view.ctl.phase === "wrong" || view.ctl.phase === "error") shake.restart() }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            height: 20
            visible: view.form
            readonly property bool failed: view.ctl.phase === "wrong" || view.ctl.phase === "error"
            text: view.ctl.phase === "wrong" ? "That password didn't match" + (view.ctl.fails === 2 ? " (one more try, then the standard lock screen)" : "")
                : view.ctl.phase === "error" ? "The password check could not run"
                : view.ctl.caps === true ? "Caps Lock is on" : ""
            color: failed ? view.red : view.accent
            font { family: view.font; pixelSize: 13 }
        }
    }

    // The pet, asleep beside the clock (LockPet.qml). Loaded by file name, so a mistake in that
    // file leaves this empty instead of breaking the lock; disabled, so it takes no focus or input.
    Loader {
        anchors.fill: parent
        asynchronous: false
        enabled: false
        active: view.form
        source: Qt.resolvedUrl("LockPet.qml")
        onLoaded: {
            item.ctl = view.ctl; item.around = stack
            // minutes to the next event (0: none in sight), so it can sit up when one is close
            item.toNext = Qt.binding(() => nextNote.item && nextNote.item.upcoming ? nextNote.item.mins : 0)
        }
    }

    // What is playing and how much is unread, bottom left (LockInfo.qml), by file name as the pet.
    Loader {
        anchors { left: parent.left; bottom: parent.bottom; margins: 28 }
        enabled: false
        active: view.form
        source: Qt.resolvedUrl("LockInfo.qml")
        onLoaded: item.now = Qt.binding(() => clock.date)
    }

    Text {
        anchors { right: parent.right; bottom: parent.bottom; margins: 28 }
        visible: UPower.displayDevice && UPower.displayDevice.isLaptopBattery
        text: UPower.displayDevice ? Math.round(UPower.displayDevice.percentage * 100) + "%" + (UPower.onBattery ? "" : "  charging") : ""
        // red when it is running down: under 15% and not plugged in
        color: UPower.displayDevice && UPower.onBattery && UPower.displayDevice.percentage < 0.15 ? view.red : "#8a8580"
        font { family: view.font; pixelSize: 13 }
    }
}
