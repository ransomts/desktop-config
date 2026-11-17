// Two quiet lines in a corner of the lock screen: what is playing (the media keys work while
// locked), and how much is unread. LockView.qml loads this through a Loader by its file name
// (as LockPet.qml), so a mistake in here leaves the corner empty, never a broken lock.
//
//   playing   the MPRIS player the bar would show (a music player before a browser tab, playing
//             before paused): artist and title, with a pause mark when it is paused
//   unread    mail in all inboxes (~/.local/bin/dashboard-data feeds, read when locking and
//             every five minutes of LockView's clock) and notifications not yet looked at
//             (the main shell's ~/.local/state/notif-history.json, followed as it changes)
// Counts only: no senders, subjects or notification text, because anyone can read a lock screen.
// Nothing is written, and the main shell's singletons are not used (see LockPet.qml for why).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Column {
    id: info
    property date now: new Date()           // LockView binds its minute clock here
    spacing: 6
    readonly property string font: "FiraCode Nerd Font"
    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")

    // ---- what is playing (the choice is Sys.player's, without its pin) ----
    readonly property var player: {
        const ps = Mpris.players.values.filter(p => !/playerctld/i.test(p.dbusName || p.identity || ""))
        const browser = p => /firefox|chrom|brave|vivaldi|zen/i.test((p.identity || "") + (p.desktopEntry || ""))
        return ps.find(p => p.isPlaying && !browser(p)) || ps.find(p => p.isPlaying)
            || ps.find(p => !browser(p) && (p.trackTitle || "") !== "") || null
    }
    readonly property string track: !player || !(player.trackTitle || "") ? ""
        : ((player.trackArtist || "") !== "" ? player.trackArtist + " - " : "") + player.trackTitle

    // ---- unread ----
    property int mail: 0
    property int notes: 0
    Process {
        id: feeds
        command: ["env", "-u", "LD_LIBRARY_PATH", "-u", "LIBGL_DRIVERS_PATH", "-u", "LIBVA_DRIVERS_PATH",
                  Quickshell.env("HOME") + "/.local/bin/dashboard-data", "feeds"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { info.mail = ((JSON.parse(text).mail || {}).boxes || []).reduce((n, b) => n + (parseInt(b.unread) || 0), 0) } catch (e) { }
            }
        }
    }
    FileView {
        path: info.stateDir + "/notif-history.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const h = JSON.parse(text()); info.notes = Array.isArray(h) ? h.filter(e => e && e.seen === false).length : 0 } catch (e) { } }
        onLoadFailed: info.notes = 0
    }
    Component.onCompleted: feeds.running = true
    onNowChanged: if (now.getMinutes() % 5 === 0 && !feeds.running) feeds.running = true

    component Line: Text {
        color: "#8a8580"
        style: Text.Outline; styleColor: "#16161a"
        font { family: info.font; pixelSize: 13 }
        elide: Text.ElideRight
        width: Math.min(implicitWidth, 460)
    }
    Line {
        visible: info.track !== ""
        text: (info.player && info.player.isPlaying ? "" : "󰏤") + "  " + info.track
    }
    Line {
        visible: info.mail > 0 || info.notes > 0
        text: (info.mail > 0 ? "  " + info.mail : "") + (info.mail > 0 && info.notes > 0 ? "      " : "") + (info.notes > 0 ? "󰂚  " + info.notes : "")
    }
}
