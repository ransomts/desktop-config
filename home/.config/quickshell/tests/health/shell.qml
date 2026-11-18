// Tests for the health pill, popup and singleton (Health.qml, HealthPill.qml, HealthList.qml).
// NOT part of the shell: ~/.local/bin/health-test copies the real files next to this one with
// the stub Sys and runs it offscreen. shell-health's answers are made up here (Health.ingest
// is what the real Process calls), so nothing is run and the machine is never read; one case
// runs the Process path against `printf`. XDG_STATE_HOME is a temp dir (the ignore list).
// Each case logs PASS or FAIL; the last line is "HEALTHTEST RESULT pass N fail M".
// Pictures: $HEALTH_TEST_OUT-dark.png and -light.png.
import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell

ShellRoot {
    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 420; implicitHeight: 900
        color: Theme.solidBg

        property int passed: 0
        property int failed: 0
        function check(what, ok, detail) {
            if (ok) passed++; else failed++
            console.log("HEALTHTEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
        }
        TestEvent { id: ev }
        Component.onCompleted: Health.active = false      // the poll timer stays off; answers come from the cases

        // a fixed clock, so "last worked" is the same every run
        readonly property real t0: Date.parse("2026-11-14T09:00:00-05:00")
        property var fires: []
        Connections { target: Health; function onNewFailure(job) { win.fires = win.fires.concat([job.id]) } }

        function ago(min) { return new Date(t0 - min * 60000).toISOString() }
        function job(id, name, state, why, sinceMin) {
            return { id: id, name: name, state: state, since: sinceMin < 0 ? "" : ago(sinceMin), why: why, unit: id + ".timer",
                     log: "journalctl --user -u " + id + ".service -n 80 --no-pager", run: state === "off" ? "" : "systemctl --user start " + id + ".service" }
        }
        function note(id, name, why, actionable, say, cmd) {
            return { id: id, name: name, state: "notice", kind: "notice", since: "", why: why, unit: "", log: "", run: "", group: "x", count: 1,
                     detail: why, cmd: cmd === undefined ? "sudo apt upgrade" : cmd, actionable: !!actionable, say: !!say }
        }
        property var said: []
        Connections { target: Health; function onNoticeSay(row) { win.said = win.said.concat([row.id]) } }
        function noteRows(item, out) {
            for (let i = 0; i < item.children.length; i++) {
                const c = item.children[i]
                if (c.modelData !== undefined && c.modelData.kind === "notice") out.push(c)
                noteRows(c, out)
            }
            return out
        }
        function answer(list) { return JSON.stringify({ worst: "x", jobs: list }) }
        function feed(list) { return Health.ingest(answer(list)) }
        function allOk() {
            return [job("pull-mail", "Mail sync", "ok", "ran just now", 1), job("davmail", "DavMail", "ok", "running since 3 h", 180),
                    job("matrix-backup", "Matrix and Teams backup", "ok", "backed up 6 days ago", 8000), job("gone", "Gone", "off", "not installed", -1)]
        }
        function mailBad(state) {
            return [job("pull-mail", "Mail sync", state, "3 runs in a row have failed", 40), job("davmail", "DavMail", "ok", "running since 3 h", 180)]
        }
        // the rows the list drew, top to bottom
        function rowsOf(item, out) {
            for (let i = 0; i < item.children.length; i++) {
                const c = item.children[i]
                if (c.modelData !== undefined && c.failed !== undefined) out.push(c)
                rowsOf(c, out)
            }
            return out
        }
        function find(item, label) {
            for (let i = 0; i < item.children.length; i++) {
                const c = item.children[i]
                if (c.label === label && c.visible) return c
                const f = find(c, label)
                if (f) return f
            }
            return null
        }
        function click(item) { ev.mouseClick(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0) }

        ColumnLayout {
            id: stage
            x: 0; y: 0; width: 420
            spacing: 10
            Item {
                Layout.preferredHeight: 34; Layout.preferredWidth: 120
                HealthPill { id: pill; x: 8; y: 0; height: 34 }
            }
            Rectangle {
                Layout.preferredWidth: 396; Layout.leftMargin: 12
                implicitHeight: list.implicitHeight + 32
                radius: 12; color: Theme.panelBg; border.width: 2; border.color: Theme.accentBg
                HealthList { id: list; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 } }
            }
        }

        property var cases: [
            { name: "nothing known yet", run: function() {
                check("hidden before the first answer", !pill.visible && Health.worst === "ok")
                check("status says unknown", Health.summary().indexOf("unknown") === 0, Health.summary())
                return 50
            } },
            { name: "startup: what is already bad shows, old failures do not fire", run: function() {
                Health.clock = function() { return win.t0 }
                feed([job("pull-mail", "Mail sync", "failed", "3 runs in a row have failed", 3000), job("push-roam", "Notes push", "stale", "last worked 2 days ago", 3000),
                      job("davmail", "DavMail", "ok", "running", 100)])
                check("worst is failed", Health.worst === "failed", Health.worst)
                check("two bad in the pill", Health.bad.length === 2 && pill.visible && pill.text === "⚠ 2", pill.text)
                check("nothing fired for old failures", win.fires.length === 0, JSON.stringify(win.fires))
                Health.loaded = false; Health.prev = {}              // a second "startup"
                feed([job("pull-mail", "Mail sync", "failed", "just broke", 3), job("push-roam", "Notes push", "stale", "old", 30), job("x", "No time", "failed", "?", -1)])
                check("at startup only a job that went bad in the last 10 minutes fires", win.fires.join() === "pull-mail", JSON.stringify(win.fires))
                win.fires = []
                return 50
            } },
            { name: "pill states", run: function() {
                feed(allOk())
                check("all ok: hidden, no tip", !pill.visible && pill.text === "" && pill.tip === "")
                check("off jobs left out of worst", Health.worst === "ok")
                feed(mailBad("stale"))
                check("stale: visible with the count", pill.visible && pill.text === "⚠ 1", pill.text)
                check("stale: amber text on the normal fill", Qt.colorEqual(pill.ink, Theme.warn) && Qt.colorEqual(pill.fill, Theme.bg))
                check("stale: tooltip names the job and why", pill.tip.indexOf("Mail sync") >= 0 && pill.tip.indexOf("3 runs in a row") >= 0, pill.tip)
                feed(mailBad("failed"))
                check("failed: red fill, dark ink", Qt.colorEqual(pill.fill, Theme.red) && Qt.colorEqual(pill.ink, Theme.accentInk))
                feed([job("a", "A", "ok", "fine", 1), job("b", "B", "stale", "late", 500)])
                check("worst of stale only is stale", Health.worst === "stale")
                feed(allOk())
                check("recovery hides it again", !pill.visible)
                return 50
            } },
            { name: "newFailure fires once per ok-to-bad", run: function() {
                win.fires = []
                feed(allOk())
                check("steady ok: nothing", win.fires.length === 0)
                feed(mailBad("failed"))
                check("ok to failed: fires once", win.fires.length === 1 && win.fires[0] === "pull-mail", JSON.stringify(win.fires))
                feed(mailBad("failed")); feed(mailBad("failed"))
                check("polls that stay bad: no more", win.fires.length === 1, win.fires.length)
                feed(mailBad("stale"))
                check("failed to stale: no more", win.fires.length === 1)
                feed(allOk()); feed(mailBad("stale"))
                check("after a recovery it fires again", win.fires.length === 2, win.fires.length)
                win.fires = []
                feed([job("a", "A", "ok", "fine", 1)]); feed([job("a", "A", "ok", "fine", 1), job("new", "New one", "failed", "broken", 5)])
                check("a job that appears already bad does not fire", win.fires.length === 0, JSON.stringify(win.fires))
                return 50
            } },
            { name: "ordering", run: function() {
                feed([job("a", "Alpha", "ok", "fine", 1), job("c", "Cee", "stale", "late", 500), job("b", "Bee", "failed", "broken", 30), job("o", "Off", "off", "x", -1)])
                check("jobs: failed, stale, ok, off", Health.jobs.map(j => j.state).join() === "failed,stale,ok,off", Health.jobs.map(j => j.state).join())
                check("bad: failed first", Health.bad[0].id === "b" && Health.bad[1].id === "c")
                return 80
            } },
            { name: "list rows", run: function() {
                const rows = rowsOf(list, []).sort((a, b) => a.mapToItem(list, 0, 0).y - b.mapToItem(list, 0, 0).y)
                check("one row per bad job", rows.length === 2, rows.length)
                check("worst first", rows.length === 2 && rows[0].modelData.id === "b" && rows[1].modelData.id === "c")
                check("buttons: Log, Run now, Ignore on a bad row", !!find(rows[0], "Log") && !!find(rows[0], "Run now") && !!find(rows[0], "Ignore"))
                return 50
            } },
            { name: "no run button when the job has none", run: function() {
                const j = job("nr", "No run", "failed", "broken", 20); j.run = ""
                feed([j])
                const rows = rowsOf(list, [])
                check("Run now hidden", rows.length === 1 && find(rows[0], "Run now") === null && !!find(rows[0], "Log"))
                return 50
            } },
            { name: "buttons", run: function() {
                Sys.ran = []
                feed(mailBad("failed"))
                const row = rowsOf(list, [])[0]
                click(find(row, "Log"))
                check("Log opens the log in a terminal", Sys.ran.length === 1 && Sys.ran[0] === "ghostty -e sh -c 'journalctl --user -u pull-mail.service -n 80 --no-pager; read _'", JSON.stringify(Sys.ran))
                click(find(row, "Run now"))
                check("Run now runs the job's command", Sys.ran.length === 2 && Sys.ran[1] === "systemctl --user start pull-mail.service", JSON.stringify(Sys.ran))
                Health.openLog({ log: "echo it's here" })
                check("quotes in a log command survive", Sys.ran[2] === "ghostty -e sh -c 'echo it'\\''s here; read _'", Sys.ran[2])
                return 50
            } },
            { name: "ignore until it recovers", run: function() {
                win.fires = []
                feed(mailBad("failed"))
                const row = rowsOf(list, [])[0]
                click(find(row, "Ignore"))
                check("ignored: not bad, pill hidden", Health.bad.length === 0 && Health.worst === "ok" && !pill.visible, Health.worst)
                check("still counted as ignored", Health.ignoredBad.length === 1 && Health.summary().indexOf("1 ignored") >= 0, Health.summary())
                feed(mailBad("stale"))
                check("stays ignored on the next poll", Health.worst === "ok")
                feed(allOk())
                check("recovers: forgotten", !Health.ignored["pull-mail"])
                feed(mailBad("failed"))
                check("fails again: shows and fires", Health.worst === "failed" && win.fires.length === 1, win.fires.length)
                Health.ignore("pull-mail"); win.fires = []
                feed(allOk()); feed(mailBad("failed"))
                check("ignored job going ok-bad fires nothing while ignored", win.fires.length === 1)   // it recovered in between, so the ignore went
                Health.unignore("pull-mail"); feed(mailBad("failed"))
                check("unignore brings it back", Health.worst === "failed")
                Health.ignore("pull-mail")
                return 600                                  // the file is written 300 ms later
            } },
            { name: "text for IPC", run: function() {
                feed([job("pull-mail", "Mail sync", "failed", "3 runs in a row have failed", 125), job("davmail", "DavMail", "ok", "running", 100), job("o", "Off", "off", "x", -1)])
                Health.unignore("pull-mail")
                check("status is one line", Health.summary() === "failed: Mail sync (3 runs in a row have failed)", Health.summary())
                const t = Health.table()
                check("list: worst, the bad one first, last worked in plain time, off left out",
                      t.indexOf("worst: failed\nFAILED") === 0 && t.indexOf("last worked 2 h ago") > 0 && t.indexOf("Off") < 0, t)
                feed(allOk())
                check("status ok", Health.summary() === "ok")
                return 50
            } },
            { name: "bad JSON keeps the last answer", run: function() {
                feed(mailBad("failed"))
                check("rejected", Health.ingest("not json") === false)
                check("last answer kept", Health.worst === "failed")
                return 50
            } },
            { name: "notices: plain ones live in the popup only", run: function() {
                feed(allOk().concat([note("apt", "Package updates", "12 package updates; lists from 2 days ago", false), note("flatpak", "Flatpak updates", "3 app or runtime updates", false)]))
                check("two notices kept apart from the jobs", Health.notices.length === 2 && Health.jobs.every(j => j.state !== "notice") && Health.jobs.length === 4, Health.jobs.length)
                check("plain notices: pill stays hidden, no attention", !pill.visible && pill.text === "" && !Health.attention && pill.tip === "", pill.text)
                check("worst, bad and good ignore them", Health.worst === "ok" && Health.bad.length === 0 && Health.good.length === 3)
                check("status line is unchanged", Health.summary() === "ok", Health.summary())
                check("table lists them as NOTICE", Health.table().indexOf("NOTICE  Package updates") > 0, Health.table())
                return 80
            } },
            { name: "notices: the popup section", run: function() {
                const rows = noteRows(list, [])
                check("a Worth knowing row per notice", rows.length === 2, rows.length)
                check("each row has its Open terminal button", rows.every(r => !!find(r, "Open terminal")))
                check("the jobs section says all is well", Health.bad.length === 0)
                Sys.ran = []
                click(find(rows[0], "Open terminal"))
                check("Open terminal runs the cmd in ghostty, like the Log button", Sys.ran.length === 1 && Sys.ran[0] === "ghostty -e sh -c 'sudo apt upgrade; read _'", JSON.stringify(Sys.ran))
                feed(allOk().concat([note("fw", "Firmware", "UEFI dbx", false, false, "")]))
                const r2 = noteRows(list, [])
                check("no cmd: no button", r2.length === 1 && find(r2[0], "Open terminal") === null)
                return 50
            } },
            { name: "notices: the pill's quiet look", run: function() {
                feed(allOk().concat([note("reboot", "Restart needed", "kernel 7.2.16 is installed, 7.2.15 is running", true, true)]))
                check("an actionable notice alone: a visible dot", pill.visible && pill.text === "•" && Health.attention, pill.text)
                check("neutral: faint ink on the normal fill, not amber, not red", Qt.colorEqual(pill.ink, Theme.faint) && Qt.colorEqual(pill.fill, Theme.bg) && !Qt.colorEqual(pill.ink, Theme.warn) && !Qt.colorEqual(pill.fill, Theme.red))
                check("smaller than the warning pill", pill.pad === 8)
                check("no count, no warning sign", pill.text.indexOf("⚠") < 0)
                check("tooltip names what is worth a look", pill.tip.indexOf("Worth a look") >= 0 && pill.tip.indexOf("Restart needed") >= 0 && pill.tip.indexOf("Something is") < 0, pill.tip)
                feed(allOk().concat([note("apt", "Package updates", "4 package updates (1 security)", true), note("disk:/", "Low disk space: /", "9 GB free of 220 GB (4%)", true, true)]))
                check("two actionable ones: still one dot, both in the tip", pill.text === "•" && pill.tip.indexOf("Package updates") >= 0 && pill.tip.indexOf("Low disk") >= 0)
                feed(allOk().concat([note("apt", "Package updates", "12 package updates", false), note("disk:/", "Low disk space: /", "9 GB free", true, true)]))
                check("a plain one next to an actionable: tip lists only the actionable", pill.tip.indexOf("12 package") < 0 && pill.tip.indexOf("Low disk") >= 0)
                feed(mailBad("stale").concat([note("reboot", "Restart needed", "x", true, true)]))
                check("a stale job and a notice: the amber warning with 1, the notice not counted", pill.text === "⚠ 1" && Qt.colorEqual(pill.ink, Theme.warn) && pill.pad === 12 && pill.tip.indexOf("Restart") < 0, pill.text + pill.tip)
                feed(mailBad("failed").concat([note("reboot", "Restart needed", "x", true, true), note("apt", "Package updates", "9 (3 security)", true)]))
                check("a failing job and notices: red, count of jobs only", Qt.colorEqual(pill.fill, Theme.red) && pill.text === "⚠ 1" && Health.worst === "failed")
                feed(allOk().concat([note("reboot", "Restart needed", "x", true, true)]))
                check("notices never make worst or bad", Health.worst === "ok" && Health.bad.length === 0)
                feed(allOk())
                check("notices gone: the pill is hidden again", !pill.visible && !Health.attention && Health.notices.length === 0)
                return 50
            } },
            { name: "notices: the popup shows both sections", run: function() {
                feed(mailBad("failed").concat([note("apt", "Package updates", "9 package updates (3 security)", true)]))
                check("a bad row and a notice row together", rowsOf(list, []).length === 1 && noteRows(list, []).length === 1)
                feed(allOk())
                return 20
            } },
            { name: "notices: the island hears only low disk and restart, once per boot", run: function() {
                Health.bootId = "boot-A"; Health.stateLoaded = true; Health.bootLoaded = true
                Health.said = ({ boot: "", ids: [] }); win.said = []
                const plain = [note("apt", "Package updates", "4 (1 security)", true), note("flatpak", "Flatpak", "3", false), note("firmware", "Firmware", "x", false)]
                feed(allOk().concat(plain))
                check("updates, flatpak, firmware: not said, even the actionable security one", win.said.length === 0, JSON.stringify(win.said))
                const rb = note("reboot", "Restart needed", "kernel", true, true), dk = note("disk:/", "Low disk space: /", "4%", true, true)
                feed(allOk().concat([rb]))
                check("restart needed: said once", win.said.join() === "reboot", JSON.stringify(win.said))
                feed(allOk().concat([rb])); feed(allOk().concat([rb, dk]))
                check("again on later polls: not again; low disk: said once", win.said.join() === "reboot,disk:/", JSON.stringify(win.said))
                feed(allOk()); feed(allOk().concat([rb, dk]))
                check("gone and back in the same boot: still not again", win.said.length === 2, JSON.stringify(win.said))
                feed(allOk().concat([note("disk:/boot/efi", "Low disk space: /boot/efi", "10 MB", true, true)]))
                check("a different disk is its own message", win.said.join() === "reboot,disk:/,disk:/boot/efi", JSON.stringify(win.said))
                Health.bootId = "boot-B"
                feed(allOk().concat([rb, dk]))
                check("after a reboot both are said again", win.said.join() === "reboot,disk:/,disk:/boot/efi,reboot,disk:/", JSON.stringify(win.said))
                check("what was said is remembered with the boot id", Health.said.boot === "boot-B" && Health.said.ids.length === 2, JSON.stringify(Health.said))
                Health.stateLoaded = false
                win.said = []
                Health.said = ({ boot: "boot-C", ids: ["reboot"] }); Health.bootId = "boot-C"
                feed(allOk().concat([rb]))
                check("nothing is said before the remembered state has loaded", win.said.length === 0)
                Health.stateLoaded = true; Health.sayNotices()
                check("a restart already said this boot (read from the file) is not said again", win.said.length === 0, JSON.stringify(win.said))
                feed(allOk())
                return 450
            } },
            { name: "notices: hidden jobs", run: function() {
                const o = JSON.parse(answer(mailBad("failed")))
                o.hidden = [{ id: "calibre", name: "Calibre database backup" }]
                check("hidden list taken from the answer", Health.ingest(JSON.stringify(o)) && Health.hiddenJobs.length === 1 && Health.hiddenJobs[0].id === "calibre")
                check("it is not among the jobs", Health.jobs.every(j => j.id !== "calibre"))
                feed(allOk())
                check("an answer without it clears the list", Health.hiddenJobs.length === 0)
                Health.cmd = ["printf", "%s", "{}"]
                return 20
            } },
            { name: "the Process path", run: function() {
                Health.cmd = ["printf", "%s", answer([job("pp", "Via process", "stale", "late", 400)])]
                Health.refresh()
                return 700
            } },
            { name: "the Process path result", run: function() {
                check("refresh() ran the command and took its answer", Health.jobs.length === 1 && Health.jobs[0].id === "pp" && !Health.busy, JSON.stringify(Health.jobs))
                feed(mailBad("failed"))                    // for the pictures: one red, one amber, healthy ones below
                feed([job("pull-mail", "Mail sync", "failed", "3 runs in a row have failed; DavMail is not running (nothing on port 1143)", 125),
                      job("push-roam", "Notes push to the server", "stale", "last worked 2 days ago, runs every 10 min", 2900),
                      job("calibre", "Calibre database backup", "failed", "nothing", 9000),
                      job("davmail", "DavMail", "ok", "running since 3 h", 180), job("rclone-box", "Box mount", "ok", "mounted, up since 17 h", 1000),
                      job("dejadup", "Backup (Deja Dup)", "ok", "last backup 2 days ago", 3000)])
                Health.ignore("calibre")
                Health.ingest(JSON.stringify({ worst: "failed", jobs: Health.jobs.concat([
                    note("reboot", "Restart needed", "kernel 7.2.16 is installed, 7.2.15 is running", true, true, "sudo reboot"),
                    note("apt", "Package updates", "12 package updates; lists from 2 days ago", false),
                    note("flatpak", "Flatpak updates", "3 app or runtime updates (1 user and 2 system)", false, false, "flatpak update"),
                    note("disk:/boot/efi", "Low disk space: /boot/efi", "15 MB free of 511 MB (3%)", true, true, "df -h /boot/efi")]) }))
                return 600
            } },
            { name: "picture dark", run: function() {
                Theme.dark = true
                return 500
            } },
            { name: "grab dark", run: function() {
                const out = Quickshell.env("HEALTH_TEST_OUT")
                if (out) stage.grabToImage(r => r.saveToFile(out + "-dark.png"))
                return 400
            } },
            { name: "light", run: function() { Theme.dark = false; return 500 } },
            { name: "grab light", run: function() {
                const out = Quickshell.env("HEALTH_TEST_OUT")
                if (out) stage.grabToImage(r => r.saveToFile(out + "-light.png"))
                return 500
            } },
            { name: "picture: only a notice, light", run: function() {
                const l = allOk().concat([note("reboot", "Restart needed", "kernel 7.2.16 is installed, 7.2.15 is running", true, true, "sudo reboot"), note("apt", "Package updates", "12 package updates; lists from 2 days ago", false)])
                Health.cmd = ["printf", "%s", answer(l)]      // a late recheck (the Run now timer) must give the same answer
                feed(l)
                return 500
            } },
            { name: "grab dot light", run: function() {
                const out = Quickshell.env("HEALTH_TEST_OUT")
                if (out) stage.grabToImage(r => r.saveToFile(out + "-dot-light.png"))
                return 500
            } },
            { name: "dot dark", run: function() { Theme.dark = true; return 1200 } },
            { name: "grab dot dark", run: function() {
                const out = Quickshell.env("HEALTH_TEST_OUT")
                if (out) stage.grabToImage(r => r.saveToFile(out + "-dot-dark.png"))
                return 500
            } }
        ]

        property int at: 0
        Timer {
            interval: 500; running: true
            onTriggered: {
                if (win.at >= win.cases.length) {
                    console.log("HEALTHTEST RESULT pass " + win.passed + " fail " + win.failed)
                    quitSoon.start()
                    return
                }
                const c = win.cases[win.at++]
                console.log("HEALTHTEST case: " + c.name)
                let wait = 100
                try { wait = c.run() } catch (e) { win.failed++; console.log("HEALTHTEST FAIL " + c.name + " threw: " + e) }
                interval = Math.max(20, wait || 100)
                restart()
            }
        }
        Timer { id: quitSoon; interval: 400; onTriggered: Qt.quit() }
    }
}
