// Tests for the idle screensaver (SaverState.qml + SaverView.qml). NOT part of the shell:
// ~/.local/bin/saver-test copies the real SaverState, SaverView, SaverRow, LockPet, WallSky,
// Theme (its is_dark watch pointed nowhere) and the scene shaders next to this file with the
// stub WallState and Sys, and runs it offscreen with SAVER_HARNESS=1: no Wayland idle
// monitor, no Hyprland, no layer windows. The idle signal is SaverState.idle, set here.
//
// Two "screens" (SaverViews, 640x360 each, the second at x 640) in one floating window are
// driven with synthetic keys and mouse events (QtTest's TestEvent). Each case logs PASS or
// FAIL; the last line is "SAVERTEST RESULT pass N fail M". Pictures: $SAVER_TEST_OUT-dark.png
// and -light.png. SAVER_FLAT=1 draws a flat gradient in place of the scene shader.
//
// Adding a case: append { name, run } to `cases`; `run` does its events and checks and
// returns how many milliseconds to wait before the next case.
import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell

ShellRoot {
    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 1280; implicitHeight: 360 + 60
        color: Theme.solidBg

        property int passed: 0
        property int failed: 0
        function check(what, ok, detail) {
            if (ok) passed++; else failed++
            console.log("SAVERTEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
        }
        TestEvent { id: ev }
        readonly property bool flat: Quickshell.env("SAVER_FLAT") === "1"

        // everything neutral: awake, on mains, nothing in the way
        function reset() {
            SaverState.previewing = false
            SaverState.idle = false
            SaverState.blank = false
            SaverState.dismissed = false
            SaverState.onBattery = false; WallState.onBattery = false
            SaverState.fullscreen = false
            SaverState.screencast = false
            SaverState.videoInUse = false
            SaverState.keepAwake = false
            SaverState.locked = false; SaverState.presenting = false
            SaverState.probeCmd = "echo false"
            SaverState.focusedScreen = "A"
            SaverState.cfg.minutes = 5
            SaverState.cfg.battery = false
            SaverState.cfg.clock = true
            SaverState.cfg.scene = "same"
            WallState.hot = false
            WallState.cfg.running = true
        }
        function goIdle() { SaverState.idle = true }      // the probe runs, then it shows
        function stack(v) {
            for (let i = 0; i < v.children.length; i++) if (v.children[i].objectName === "clock") return v.children[i]
            return null
        }
        property real t0: 0
        property var blockers: [
            ["on battery", () => { SaverState.onBattery = true; WallState.onBattery = true }],
            ["a full-screen window", () => SaverState.fullscreen = true],
            ["screen share (video stream)", () => SaverState.videoInUse = true],
            ["screencast event", () => SaverState.screencast = true],
            ["keep awake", () => SaverState.keepAwake = true],
            ["presenting file", () => SaverState.probeCmd = "echo false; echo presenting"],
            ["session locked", () => SaverState.probeCmd = "echo true"]
        ]
        property int bi: 0

        Item {
            id: stage
            width: 1280; height: 420
            Rectangle {                         // under the row: what a panel looks like
                y: 360; width: 1280; height: 60
                color: Theme.solidBg
                SaverRow {
                    id: srow
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 14 }
                    width: 520
                }
            }
            SaverView {
                id: va; x: 0; width: 640; height: 360; flat: win.flat; index: 0
                screenObj: ({ x: 0, y: 0, name: "A" })
            }
            SaverView {
                id: vb; x: 640; width: 640; height: 360; flat: win.flat; index: 1
                screenObj: ({ x: 640, y: 0, name: "B" })
            }
        }

        property var cases: [
            { name: "defaults", run: function() {
                reset()
                check("minutes 5", SaverState.cfg.minutes === 5)
                check("scene same (the wallpaper's)", SaverState.cfg.scene === "same" && SaverState.scene === "contours", SaverState.scene)
                check("clock on, battery off", SaverState.cfg.clock && !SaverState.cfg.battery)
                check("not shown while active", !SaverState.shown && va.opacity === 0)
                goIdle()
                return 250
            } },
            { name: "idle: it comes up", run: function() {
                check("shown after idle + probe", SaverState.shown, SaverState.status())
                check("moving on mains", SaverState.moving)
                check("pet on the focused screen only", va.petHere && !vb.petHere)
                check("fading in, not there yet", va.opacity > 0 && va.opacity < 1, va.opacity)
                check("status says shown", SaverState.status().indexOf("shown") === 0, SaverState.status())
                win.t0 = va.sceneTime
                return 1600
            } },
            { name: "faded in and animating", run: function() {
                check("opacity 1 after 1.5 s", va.opacity === 1, va.opacity)
                check("scene time advances", va.sceneTime > win.t0, win.t0 + " -> " + va.sceneTime)
                const s = stack(va)
                check("clock on screen", s && s.visible && s.x >= 0 && s.y >= 0 && s.x + s.width <= 640 && s.y + s.height <= 360, s ? s.x + "," + s.y : "none")
                ev.keyPress(Qt.Key_Shift, Qt.NoModifier, -1)
                ev.keyRelease(Qt.Key_Shift, Qt.NoModifier, -1)
                return 350
            } },
            { name: "a key dismisses fast", run: function() {
                check("hidden after a key", !SaverState.shown, SaverState.status())
                check("faded out within 350 ms", va.opacity === 0, va.opacity)
                check("stays down while still idle (no second showing)", SaverState.dismissed && !SaverState.shown)
                SaverState.idle = false
                check("activity clears the dismissal", !SaverState.dismissed)
                goIdle()
                return 250
            } },
            { name: "a click dismisses", run: function() {
                check("up again on the next idle spell", SaverState.shown)
                ev.mouseClick(vb, 300, 200, Qt.LeftButton, Qt.NoModifier, 0)
                check("hidden after a click", !SaverState.shown)
                SaverState.idle = false; goIdle()
                return 800
            } },
            { name: "pointer motion dismisses, a twitch does not", run: function() {
                check("up again", SaverState.shown)
                ev.mouseMove(va, 200, 200, 0, Qt.NoButton, Qt.NoModifier)       // the "enter" a new surface gets
                ev.mouseMove(va, 203, 201, 0, Qt.NoButton, Qt.NoModifier)
                check("a 4 px twitch leaves it up", SaverState.shown)
                ev.mouseMove(va, 260, 240, 0, Qt.NoButton, Qt.NoModifier)
                check("a real move takes it down", !SaverState.shown)
                return 50
            } },
            { name: "the pointer resting where it appears does not dismiss", run: function() {
                SaverState.idle = false; goIdle()
                return 250
            } },
            { name: "...", run: function() {
                ev.mouseMove(va, 400, 100, 0, Qt.NoButton, Qt.NoModifier)       // first event in the first half second: just recorded
                check("first event recorded, not a dismissal", SaverState.shown)
                reset()
                return 50
            } },
            // every "never starts while" condition, one after the other
            { name: "blockers", run: function() {
                reset()
                const b = win.blockers[win.bi]
                b[1]()
                goIdle()
                return 250
            } },
            { name: "blocker check", run: function() {
                const b = win.blockers[win.bi]
                check("does not start: " + b[0], !SaverState.shown && va.opacity === 0, SaverState.status())
                check("status names it: " + b[0], SaverState.status().indexOf("not starting") >= 0, SaverState.status())
                win.bi++
                if (win.bi < win.blockers.length) win.at -= 2       // run the pair again for the next one
                reset()
                return 50
            } },
            { name: "battery rule", run: function() {
                SaverState.onBattery = true; WallState.onBattery = true
                SaverState.cfg.battery = true
                goIdle()
                return 250
            } },
            { name: "battery rule check", run: function() {
                check("with battery on it starts on battery", SaverState.shown, SaverState.status())
                check("...as a held frame", !SaverState.moving && SaverState.status().indexOf("held frame") >= 0, SaverState.status())
                win.t0 = va.sceneTime
                return 300
            } },
            { name: "held frame stays held", run: function() {
                check("scene time unchanged on battery", va.sceneTime === win.t0, win.t0 + " -> " + va.sceneTime)
                SaverState.onBattery = true; SaverState.cfg.battery = false
                check("battery switched off while up: it goes", !SaverState.shown)
                reset()
                WallState.hot = true
                goIdle()
                return 250
            } },
            { name: "heat guard: held frame", run: function() {
                check("shown while the fan is busy", SaverState.shown)
                check("not moving", !SaverState.moving)
                win.t0 = va.sceneTime
                return 300
            } },
            { name: "heat guard check", run: function() {
                check("scene time unchanged while hot", va.sceneTime === win.t0)
                WallState.hot = false
                check("moves again when the fan calms", SaverState.moving)
                SaverState.fullscreen = true
                check("a full-screen window while up takes it down", !SaverState.shown)
                reset()
                SaverState.cfg.minutes = 0
                goIdle()
                return 250
            } },
            { name: "minutes 0", run: function() {
                check("minutes 0: never starts", !SaverState.shown)
                check("status off", SaverState.status().indexOf("off") === 0, SaverState.status())
                check("setMinutes clamps", SaverState.setMinutes(-3) === 0 && SaverState.setMinutes(999) === 240)
                reset()
                goIdle()
                return 250
            } },
            { name: "blanking", run: function() {
                check("up", SaverState.shown)
                SaverState.blank = true                // hypridle's DPMS time
                check("screens blanking: it goes and stops", !SaverState.shown && !SaverState.moving)
                SaverState.locked = true; SaverState.blank = false
                check("locked while up (a suspend): down", !SaverState.shown)
                reset()
                SaverState.preview(400)
                return 100
            } },
            { name: "preview", run: function() {
                check("preview shows without idle", SaverState.shown && SaverState.status().indexOf("preview") === 0, SaverState.status())
                return 450
            } },
            { name: "preview ends", run: function() {
                check("preview ends by itself", !SaverState.shown)
                SaverState.onBattery = true; SaverState.fullscreen = true
                SaverState.preview(300)
                check("preview ignores the blockers (it is asked for)", SaverState.shown)
                SaverState.stop()
                check("stop ends it", !SaverState.shown)
                reset()
                return 50
            } },
            { name: "scenes", run: function() {
                check("unknown scene refused", SaverState.setScene("nope") === "same")
                check("named scene", SaverState.setScene("ink") === "ink" && SaverState.scene === "ink")
                SaverState.setScene("cycle")
                check("cycle starts after the wallpaper's scene", SaverState.scene === "ink", SaverState.scene)    // contours -> ink
                SaverState.cycleAt++
                check("cycle moves on", SaverState.scene === "ridges", SaverState.scene)
                reset()
                return 50
            } },
            { name: "clock drift stays on screen", run: function() {
                const sizes = [[640, 360], [1920, 1080], [2560, 1440], [1080, 1920], [1366, 768]]
                let bad = "", minX = 1e9, maxX = -1e9
                for (const v of [va, vb]) {
                    const s = stack(v), room = s.width + 190
                    for (const sz of sizes) {
                        for (let t = 0; t < 7200; t += 3) {
                            const p = v.drift(t, sz[0], sz[1], room, s.height)
                            if (p.x < 0 || p.y < 0 || p.x + room > sz[0] + 0.5 || p.y + s.height > sz[1] + 0.5) { bad = sz + " t=" + t + " " + p; break }
                            if (sz[0] === 1920) { minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x) }
                        }
                    }
                }
                check("inside every screen size for two hours", bad === "", bad)
                check("it really travels (>1000 px across a 1920 screen)", maxX - minX > 1000, minX + ".." + maxX)
                const a = va.drift(100, 1920, 1080, 500, 200), b = vb.drift(100, 1920, 1080, 500, 200)
                check("screens drift out of step", Math.abs(a.x - b.x) + Math.abs(a.y - b.y) > 20)
                const p1 = va.drift(1000, 1920, 1080, 500, 200), p2 = va.drift(1001, 1920, 1080, 500, 200)
                check("slow: under 20 px a second", Math.hypot(p2.x - p1.x, p2.y - p1.y) < 20, Math.hypot(p2.x - p1.x, p2.y - p1.y))
                SaverState.cfg.clock = false
                check("clock off hides it", !stack(va).visible)
                reset()
                return 50
            } },
            { name: "settings row", run: function() {
                check("row says on", srow.on)
                SaverState.setMinutes(0)
                check("row says off", !srow.on)
                SaverState.setMinutes(7)
                return 400                              // the state file is written 300 ms after a change
            } },
            // pictures: dark, then light (the runner checks them and the state file)
            { name: "picture dark", run: function() {
                reset(); Theme.dark = true
                SaverState.preview(60000)
                return 1800
            } },
            { name: "grab dark", run: function() {
                check("up for the picture", SaverState.shown && va.opacity === 1)
                const out = Quickshell.env("SAVER_TEST_OUT")
                if (out) stage.grabToImage(r => r.saveToFile(out + "-dark.png"))
                return 400
            } },
            { name: "light", run: function() {
                Theme.dark = false
                return 900
            } },
            { name: "grab light", run: function() {
                const out = Quickshell.env("SAVER_TEST_OUT")
                if (out) stage.grabToImage(r => r.saveToFile(out + "-light.png"))
                return 600
            } }
        ]

        property int at: 0
        Timer {
            interval: 600; running: true
            onTriggered: {
                if (win.at >= win.cases.length) {
                    console.log("SAVERTEST RESULT pass " + win.passed + " fail " + win.failed)
                    SaverState.setMinutes(7)
                    quitSoon.start()
                    return
                }
                const c = win.cases[win.at++]
                console.log("SAVERTEST case: " + c.name)
                let wait = 100
                try { wait = c.run() } catch (e) { win.failed++; console.log("SAVERTEST FAIL " + c.name + " threw: " + e) }
                interval = Math.max(20, wait || 100)
                restart()
            }
        }
        Timer { id: quitSoon; interval: 600; onTriggered: Qt.quit() }
    }
}
