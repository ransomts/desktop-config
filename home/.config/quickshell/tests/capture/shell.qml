// Tests for the webcam bubble (CamState.qml + CamView.qml). NOT part of the shell:
// ~/.local/bin/capture-test copies the real CamState, CamView, Theme (its is_dark watch pointed
// nowhere) and a FloatingWindow copy of CamBubble.qml (CamBubbleWin) next to this file with the
// stub Sys, and runs it offscreen. The camera is never opened: CamState.input is swapped for
// ffmpeg's generated test pattern (lavfi), so the real feed pipeline (ffmpeg -> JPEG ->
// two Images -> round Canvas) runs on made-up frames. CAM_FRAME_DIR and XDG_STATE_HOME are
// temporary folders.
//
// One 800x500 "screen" named TEST (a second, OTHER, by renaming), driven with synthetic mouse
// events (QtTest's TestEvent). Each case logs PASS or FAIL; the last line is
// "CTEST RESULT pass N fail M". Pictures: $CAM_TEST_OUT-dark.png and -light.png.
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

ShellRoot {
    CamBubbleWin { id: win2 }

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 800; implicitHeight: 500
        color: Theme.solidBg

        property int passed: 0
        property int failed: 0
        function check(what, ok, detail) {
            if (ok) passed++; else failed++
            console.log("CTEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
        }
        function near(a, b, tol) { return Math.abs(a - b) <= (tol === undefined ? 2 : tol) }
        TestEvent { id: ev }
        readonly property string out: Quickshell.env("CAM_TEST_OUT")
        readonly property var pattern: ["-f", "lavfi", "-i", "testsrc2=size=640x480:rate=15"]
        property int pid: 0
        property string probe: ""

        // drag the bubble from its centre by (dx, dy), in steps, in stage coordinates
        function drag(dx, dy) {
            const b = view.bubble
            const x0 = b.x + b.width / 2, y0 = b.y + b.height / 2
            ev.mousePress(stage, x0, y0, Qt.LeftButton, Qt.NoModifier, 0)
            for (let i = 1; i <= 8; i++)
                ev.mouseMove(stage, x0 + dx * i / 8, y0 + dy * i / 8, 0, Qt.LeftButton, Qt.NoModifier)
            ev.mouseRelease(stage, x0 + dx, y0 + dy, Qt.LeftButton, Qt.NoModifier, 0)
        }
        // is a process alive? (kill -0, our own feed's pid only)
        Process { id: alive; stdout: StdioCollector { onStreamFinished: win.probe = text.trim() } }

        Item {
            id: stage
            width: 800; height: 500
            Rectangle { anchors.fill: parent; color: Theme.dark ? "#2a2830" : "#cfc9c0" }   // the "wallpaper"
            // a made-up desktop under the bubble: two windows with some text
            Rectangle { x: 30; y: 30; width: 470; height: 300; radius: 10; color: Theme.panelBg; border.color: Theme.line
                Column { x: 20; y: 18; spacing: 10
                    Text { text: "Lecture 14: hash tables"; color: Theme.fg; font.family: Theme.font; font.pixelSize: 22; font.bold: true }
                    Repeater { model: ["open addressing: probe on collision", "load factor α = n / m", "resize when α > 0.75", "chaining keeps a list per bucket"]
                        Text { text: "• " + modelData; color: Theme.fg; font.family: Theme.font; font.pixelSize: 16 } }
                }
            }
            Rectangle { x: 380; y: 180; width: 380; height: 200; radius: 10; color: Theme.panelBg; border.color: Theme.line
                Text { x: 16; y: 14; text: "h(k) = k mod m"; color: Theme.accent; font.family: "monospace"; font.pixelSize: 18 } }
            CamView { id: view; anchors.fill: parent }
        }

        property var cases: [
            { name: "defaults, nothing running", run: function() {
                check("off at start", !CamState.shown && !CamState.feeding)
                check("size 220 and device from cam-bubble.json", CamState.cfg.size === 220 && CamState.cfg.device === "/nonexistent/video-test",
                      CamState.cfg.size + " " + CamState.cfg.device)
                const c = CamState.command.join(" ")
                check("camera command: v4l2 640x480 from the device, under setpriv --pdeathsig",
                      c.indexOf("-f v4l2 -video_size 640x480 -i /nonexistent/video-test") > 0 && CamState.feedScript.indexOf("exec setpriv --pdeathsig TERM ffmpeg") >= 0, c)
                check("frames: square crop, 480 px, 15 fps, atomic JPEG in CAM_FRAME_DIR",
                      CamState.feedScript.indexOf('crop=min(iw\\,ih):min(iw\\,ih),scale=480:480" -r 15') > 0
                      && CamState.feedScript.indexOf("-update 1 -atomic_writing 1") > 0 && CamState.frameDir === Quickshell.env("CAM_FRAME_DIR"), CamState.feedScript)
                check("no frame timer while hidden", !view.live && view.frames === 0)
                check("CamBubble window copy loaded, hidden, elliptic mask on the bubble",
                      win2 && !win2.visible && win2.mask && win2.mask.shape === RegionShape.Ellipse)
                CamState.input = win.pattern           // never the camera
                CamState.on()
                CamState.screenName = "TEST"
                return 2500
            } },
            { name: "on: frames arrive, bottom-right", run: function() {
                check("shown, feed running", CamState.shown && CamState.feeding, CamState.status())
                win.pid = CamState.feedPid
                check("feed has a pid", win.pid > 0, win.pid)
                check("frames drawn (" + view.frames + ")", view.frames >= 5 && view.current !== "", view.frames)
                check("loads in flight stay bounded (<= 3)", view.pending.length <= 3, view.pending.length)
                check("bottom-right with a 32 px margin", view.bubble.x === 800 - 220 - 32 && view.bubble.y === 500 - 220 - 32, view.bubble.x + "," + view.bubble.y)
                const st = JSON.parse(CamState.status())
                check("status JSON", st.shown && st.camera && st.size === 220 && st.screen === "TEST" && st.pid === win.pid && st.error === "", CamState.status())
                check("bubble window shown, mask follows the bubble", win2.visible && win2.mask.width === 220 && win2.mask.height === 220)
                drag(-300, -150)
                return 400
            } },
            { name: "drag moves it and remembers the place", run: function() {
                // MouseArea starts a drag only past its threshold, and the first step's distance is lost: 1/8 of it here
                check("moved by the drag", near(view.bubble.x, 248, 40) && near(view.bubble.y, 98, 20), view.bubble.x + "," + view.bubble.y)
                const p = CamState.posFor("TEST")
                check("centre saved as fractions", p && near(p[0], (view.bubble.x + 110) / 800, 0.002) && near(p[1], (view.bubble.y + 110) / 500, 0.002), JSON.stringify(p))
                drag(-900, -900)
                check("cannot leave the screen", view.bubble.x === 0 && view.bubble.y === 0, view.bubble.x + "," + view.bubble.y)
                drag(330, 170)
                return 200
            } },
            { name: "scroll resizes about the centre", run: function() {
                const cx = view.bubble.x + view.bubble.width / 2, cy = view.bubble.y + view.bubble.height / 2
                ev.mouseWheel(stage, cx, cy, Qt.NoButton, Qt.NoModifier, 0, 120, 0)
                check("scroll up: 240", CamState.cfg.size === 240 && view.bubble.width === 240, CamState.cfg.size)
                check("centre kept", near(view.bubble.x + 120, cx, 1) && near(view.bubble.y + 120, cy, 1), (view.bubble.x + 120) + "," + (view.bubble.y + 120) + " vs " + cx + "," + cy)
                for (let i = 0; i < 20; i++) ev.mouseWheel(stage, view.bubble.x + view.bubble.width / 2, view.bubble.y + view.bubble.height / 2, Qt.NoButton, Qt.NoModifier, 0, 120, 0)
                check("at most 480 (and inside the screen)", CamState.cfg.size === 480 && view.bubble.y + 480 <= 500 && view.bubble.y >= 0, CamState.cfg.size + " y " + view.bubble.y)
                ev.mouseWheel(stage, view.bubble.x + 240, view.bubble.y + 240, Qt.NoButton, Qt.NoModifier, 0, -120, 0)
                check("scroll down: 460", CamState.cfg.size === 460, CamState.cfg.size)
                check("ipc size 50 -> 120", CamState.setSize(50) === 120 && view.bubble.width === 120)
                CamState.setSize(220)
                check("ipc size 220, bubble on screen", view.bubble.width === 220 && view.bubble.x >= 0 && view.bubble.x + 220 <= 800 && view.bubble.y + 220 <= 500)
                win.lastTest = [view.bubble.x, view.bubble.y]
                CamState.screenName = "OTHER"
                return 100
            } },
            { name: "per screen", run: function() {
                check("another screen: bottom-right", view.bubble.x === 548 && view.bubble.y === 248, view.bubble.x + "," + view.bubble.y)
                drag(-100, 0)
                check("moved there", near(view.bubble.x, 448, 12), view.bubble.x)
                CamState.screenName = "TEST"
                check("back on TEST: its own place", near(view.bubble.x, win.lastTest[0], 1) && near(view.bubble.y, win.lastTest[1], 1),
                      view.bubble.x + "," + view.bubble.y + " vs " + win.lastTest)
                CamState.off()
                return 800
            } },
            { name: "off releases the camera", run: function() {
                check("feed stopped, no frame timer", !CamState.feeding && !view.live && view.frames === 0 && view.current === "")
                check("bubble window hidden", !win2.visible)
                alive.command = ["sh", "-c", "kill -0 " + win.pid + " 2>/dev/null && echo alive || echo gone"]
                alive.running = true
                return 400
            } },
            { name: "process gone; on again", run: function() {
                check("ffmpeg process " + win.pid + " is gone", win.probe === "gone", win.probe)
                CamState.on(); CamState.screenName = "TEST"
                return 1500
            } },
            { name: "on again: same place, frames again", run: function() {
                check("place restored", near(view.bubble.x, win.lastTest[0], 1) && near(view.bubble.y, win.lastTest[1], 1), view.bubble.x + "," + view.bubble.y)
                check("frames again", view.frames >= 3 && CamState.feedPid > 0 && CamState.feedPid !== win.pid, view.frames)
                // right-click opens the camera picker since 2026-11-17 (it used to hide the bubble)
                Sys.ran = []
                ev.mouseClick(stage, view.bubble.x + 110, view.bubble.y + 110, Qt.RightButton, Qt.NoModifier, 0)
                check("right-click asks for the camera picker, bubble stays", Sys.ran.length === 1 && Sys.ran[0] === Sys.bin + "cams pick" && CamState.shown, JSON.stringify(Sys.ran))
                CamState.off()
                check("off hides it", !CamState.shown)
                CamState.input = ["-f", "v4l2", "-i", "/nonexistent/video-missing"]
                CamState.on(); CamState.screenName = "TEST"
                return 1500
            } },
            { name: "a missing camera says so", run: function() {
                check("error set, nothing running", CamState.error.indexOf("No camera") === 0 && !CamState.feeding && !view.live, CamState.error)
                check("status carries the error", JSON.parse(CamState.status()).error !== "")
                CamState.off()
                check("off clears nothing it should not: error stays until next on", CamState.error !== "")
                CamState.input = win.pattern
                CamState.on(); CamState.screenName = "TEST"
                check("on clears the error", CamState.error === "")
                return 1500
            } },
            { name: "pictures", run: function() {
                Theme.dark = true
                return 400
            } },
            { name: "dark", run: function() {
                check("frames (dark)", view.frames > 0)
                if (win.out) stage.grabToImage(r => { r.saveToFile(win.out + "-dark.png"); Theme.dark = false })
                else Theme.dark = false
                return 600
            } },
            { name: "light", run: function() {
                check("frames (light)", view.frames > 0)
                if (win.out) stage.grabToImage(r => r.saveToFile(win.out + "-light.png"))
                return 300
            } },
            { name: "end", run: function() {
                CamState.off()
                return 600
            } }
        ]
        property var lastTest: [0, 0]
        property int at: 0
        Timer {
            id: step
            interval: 800
            running: true
            onTriggered: {
                if (win.at >= win.cases.length) {
                    console.log("CTEST RESULT pass " + win.passed + " fail " + win.failed)
                    quitSoon.start(); return
                }
                const c = win.cases[win.at++]
                console.log("CTEST case: " + c.name)
                let wait = 100
                try { wait = c.run() || 100 } catch (e) { win.check(c.name + " threw", false, e) }
                step.interval = wait; step.restart()
            }
        }
        Timer { id: quitSoon; interval: 600; onTriggered: Qt.quit() }
    }
}
