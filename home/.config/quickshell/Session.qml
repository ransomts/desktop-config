pragma Singleton
// (pragma first: the singleton scanner gives up on a long comment header above it)
// Opt-in session restore: which apps were open on which desktop, and an OFFER to reopen them
// at the next login. The work is done by two scripts: ~/.local/bin/session-save (writes
// $XDG_STATE_HOME/session/last.json) and session-restore. Settings in ~/.config/shell/session.json
// (off by default; "enabled", "skip", "allow", "terminalsRestoreCwd", see `session-restore --help`).
//
//   Session.enabled / count / summary / saved   from `session-restore --status` (count = windows that would reopen)
//   Session.save() / restore() / refresh() / setEnabled(bool)
//   Session.offer(count, summary)   once per LOGIN, startDelay (6 s) after the shell starts, when enabled and
//                    something can be reopened. A mere shell reload does not offer: the marker
//                    $XDG_RUNTIME_DIR/session-login exists then (the directory is fresh per login).
//                    shell.qml puts it on the island: click = Session.restore(), 15 s unclicked = no.
//   While enabled it runs `session-save --if-enabled` every saveEvery (10 minutes); nothing runs while off.
//   Logout hook (not here): `session-save --if-enabled; uwsm stop` in ~/.local/bin/logout-confirm (Super+Shift+E, twice) and PowerMenu.qml.
//
//   qs ipc call session status | save | restore | list | on | off
// SESSION_HARNESS=1 (tests): no timers, nothing starts by itself.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: ses
    readonly property bool live: Quickshell.env("SESSION_HARNESS") !== "1"
    property int saveEvery: 600000
    property int startDelay: 6000
    property bool enabled: false
    property int count: 0
    property string summary: ""
    property string saved: ""
    property string listing: "no saved session"
    signal offer(int count, string summary)

    function run(args) { return Sys.clean.concat([Sys.bin + args[0]]).concat(args.slice(1)) }

    function refresh(): void { statusProc.running = false; statusProc.running = true; listProc.running = false; listProc.running = true }
    function save(): void { if (!saveProc.running) saveProc.running = true }
    function restore(): void { Sys.launch(run(["session-restore"])) }
    function loginCheck(): void { loginProc.running = false; loginProc.running = true }
    function setEnabled(on: bool): void { setProc.command = run(["session-restore", "--set-enabled", on ? "true" : "false"]); setProc.running = true }
    function status(): string {
        return (enabled ? "on" : "off") + ", " + count + (count === 1 ? " window" : " windows") + (summary ? " (" + summary + ")" : "") + (saved ? ", saved " + saved : "")
    }
    function ingestStatus(text: string): void {
        let j
        try { j = JSON.parse(text) } catch (e) { return }
        enabled = !!j.enabled; count = j.count || 0; summary = j.summary || ""; saved = j.saved || ""
    }
    // the answer of `session-restore --login-check`
    function ingestLogin(text: string): void {
        let j
        try { j = JSON.parse(text) } catch (e) { return }
        ingestStatus(JSON.stringify({ enabled: j.offer ? true : enabled, count: j.count || count, summary: j.summary || summary, saved: saved }))
        if (j.offer) offer(j.count, j.summary || "")
        refresh()
    }

    Process {
        id: statusProc
        command: ses.run(["session-restore", "--status"])
        stdout: StdioCollector { onStreamFinished: ses.ingestStatus(text) }
    }
    Process {
        id: listProc
        command: ses.run(["session-restore", "--list"])
        stdout: StdioCollector { onStreamFinished: ses.listing = text.trim() }
    }
    Process {
        id: saveProc
        command: ses.run(["session-save", "--if-enabled"])
        onRunningChanged: if (!running) ses.refresh()
    }
    Process {
        id: setProc
        onRunningChanged: if (!running) ses.refresh()
    }
    Process {
        id: loginProc
        command: ses.run(["session-restore", "--login-check"])
        stdout: StdioCollector { onStreamFinished: ses.ingestLogin(text) }
    }

    Timer { interval: ses.saveEvery; repeat: true; running: ses.live && ses.enabled; onTriggered: ses.save() }
    Timer { id: startTimer; interval: ses.startDelay; running: ses.live; onTriggered: ses.loginCheck() }
    Component.onCompleted: refresh()
}
