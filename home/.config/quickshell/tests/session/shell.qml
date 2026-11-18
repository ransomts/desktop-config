// Tests for Session.qml (the Quickshell side of session restore). NOT part of the shell:
// ~/.local/bin/session-test copies Session.qml next to this file with the stub Sys and runs it
// offscreen with SESSION_HARNESS=1 (no timers). The scripts it calls are the real session-save and
// session-restore, run against a fake hyprctl on PATH, in a temporary XDG_STATE_HOME / XDG_CONFIG_HOME /
// XDG_RUNTIME_DIR. Each case logs PASS or FAIL; the last line is "SESSIONQML RESULT pass N fail M".
import QtQuick
import Quickshell

ShellRoot {
    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 200; implicitHeight: 100
        property int passed: 0
        property int failed: 0
        property var offers: []
        readonly property string rt: Quickshell.env("XDG_RUNTIME_DIR")
        function check(what, ok, detail) {
            if (ok) passed++; else failed++
            console.log("SESSIONQML " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
        }
        Connections { target: Session; function onOffer(n, sub) { win.offers = win.offers.concat([{ n: n, sub: sub }]) } }

        property int at: 0
        readonly property var cases: [
            { name: "harness: no timers, nothing started by itself", run: function() {
                check("live is false under SESSION_HARNESS", Session.live === false)
                check("no offer without a login check", offers.length === 0)
                Session.refresh()
                return 900
            } },
            { name: "status after refresh (disabled by default)", run: function() {
                check("disabled", Session.enabled === false)
                check("count of reopenable windows", Session.count === 3, Session.count)
                check("summary names the apps", Session.summary.indexOf("zathura") >= 0 && Session.summary.indexOf("firefox") < 0, Session.summary)
                check("status text", Session.status().indexOf("off, 3 windows") === 0, Session.status())
                check("list text", Session.listing.indexOf("reopen") >= 0 && Session.listing.indexOf("[skip list]") >= 0, Session.listing)
                Session.loginCheck()
                return 900
            } },
            { name: "new login while disabled: no offer, login marked", run: function() {
                check("no offer", offers.length === 0)
                Session.setEnabled(true)
                return 900
            } },
            { name: "enabled; same login: still no offer", run: function() {
                check("enabled now", Session.enabled === true)
                Session.loginCheck()
                return 900
            } },
            { name: "a second login", run: function() {
                check("no offer on a mere reload", offers.length === 0, JSON.stringify(offers))
                Quickshell.execDetached(["rm", "-f", rt + "/session-login"])
                return 300
            } },
            { name: "offer", run: function() {
                Session.loginCheck()
                return 900
            } },
            { name: "offer arrived", run: function() {
                check("one offer, with count and summary", offers.length === 1 && offers[0].n === 3 && offers[0].sub.length > 0, JSON.stringify(offers))
                Session.loginCheck()
                return 700
            } },
            { name: "no second offer in the same login", run: function() {
                check("still one", offers.length === 1)
                Session.save()
                return 900
            } },
            { name: "save, restore, off", run: function() {
                check("session-save (via the fake hyprctl) rewrote the file: count follows", Session.count === 1 && Session.summary === "Nautilus", Session.count + " " + Session.summary)
                Session.restore()
                check("restore launches session-restore detached", Sys.launched.length === 1 && Sys.launched[0].indexOf("session-restore") > 0 && Sys.launched[0].indexOf("--") < 0, JSON.stringify(Sys.launched))
                Session.setEnabled(false)
                return 900
            } },
            { name: "off", run: function() {
                check("disabled again", Session.enabled === false)
                return 50
            } }
        ]
        Timer {
            interval: 500; running: true
            onTriggered: {
                if (win.at >= win.cases.length) {
                    console.log("SESSIONQML RESULT pass " + win.passed + " fail " + win.failed)
                    quitSoon.start()
                    return
                }
                const c = win.cases[win.at++]
                console.log("SESSIONQML case: " + c.name)
                let wait = 100
                try { wait = c.run() } catch (e) { win.failed++; console.log("SESSIONQML FAIL " + c.name + " threw: " + e) }
                interval = Math.max(20, wait || 100)
                restart()
            }
        }
        Timer { id: quitSoon; interval: 300; onTriggered: Qt.quit() }
    }
}
