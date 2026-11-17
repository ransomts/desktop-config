// A tiny sign the bar pet (Pet.qml) carries: one thing you choose, readable at a glance
// without opening anything. Drawn by PetSprite.qml at the pet's top left, the side away
// from its bubble, and only by the pet itself (not its friend), never while it sleeps or hides.
// Choices (menu Settings > Sign: each click steps to the next):
//   none       nothing (the default)
//   mail       unread mail in the Clemson inbox, from ~/.local/bin/dashboard-data feeds,
//              asked every 5 minutes and only while this sign is chosen and the pet is shown;
//              hidden while Do Not Disturb is on (a shared screen, a class)
//   battery    the battery's percentage (UPower); red on battery under 20%
//   event      minutes to the next event today (Sys.nextEvent); accent within 10 minutes
//   temp       CPU package temperature, read every 30 s only while chosen; warn from 85°C, red from 95°C
//   qs ipc call pet sign NAME       none | mail | battery | event | temp; prints the choice now in force
// Kept in ~/.local/state/pet-sign.json.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Singleton {
    id: sign

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/pet-sign.json"
        blockLoading: true
        blockWrites: true           // a change made while an unfinished write was in flight used to be undone when it landed
        printErrors: false
        onAdapterUpdated: saveSoon.restart()
        JsonAdapter {
            id: store
            property string sign: "none"
        }
    }
    Timer { id: saveSoon; interval: 300; onTriggered: file.writeAdapter() }

    readonly property var choices: ["none", "mail", "battery", "event", "temp"]
    readonly property var labels: ({ none: "none", mail: "mail", battery: "battery", event: "next event", temp: "CPU temp" })
    readonly property string choice: choices.indexOf(store.sign) >= 0 ? store.sign : "none"
    readonly property string label: labels[choice]
    function setSign(name) { if (choices.indexOf(name) >= 0) store.sign = name; return choice }
    function nextSign() { return setSign(choices[(choices.indexOf(choice) + 1) % choices.length]) }

    // only ask for data while it would be shown
    readonly property bool wanted: Pet.enabled && choice !== "none"

    // ---- stand-ins a test can set (-1: use the real source) ----
    property int mailDemo: -1
    property int batteryDemo: -1
    property int tempDemo: -1

    // ---- mail: the Clemson inbox's unread count ----
    property int mailCount: -1              // -1: not known yet
    Process {
        id: feedsRun
        command: Sys.clean.concat([Sys.bin + "dashboard-data", "feeds"])
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const boxes = (JSON.parse(text).mail || {}).boxes || []
                    const b = boxes.find(x => x.name === "Clemson")
                    sign.mailCount = b ? b.unread : -1
                } catch (e) {}
            }
        }
    }
    Timer {
        interval: 300000; repeat: true; triggeredOnStart: true
        running: sign.wanted && sign.choice === "mail" && sign.mailDemo < 0
        onTriggered: if (!feedsRun.running) feedsRun.running = true
    }
    readonly property int mail: mailDemo >= 0 ? mailDemo : mailCount

    // ---- battery ----
    readonly property var bat: UPower.displayDevice
    readonly property int battery: batteryDemo >= 0 ? batteryDemo : (bat && bat.isLaptopBattery ? Math.round(bat.percentage * 100) : -1)

    // ---- CPU temperature (the x86_pkg_temp thermal zone) ----
    property int tempRead: -1
    Process {
        id: tempRun
        command: ["sh", "-c", "for z in /sys/class/thermal/thermal_zone*; do [ \"$(cat $z/type)\" = x86_pkg_temp ] && cat $z/temp && exit; done"]
        stdout: StdioCollector { onStreamFinished: { const t = Number(text.trim()) / 1000; if (t > 0) sign.tempRead = Math.round(t) } }
    }
    Timer {
        interval: 30000; repeat: true; triggeredOnStart: true
        running: sign.wanted && sign.choice === "temp" && sign.tempDemo < 0
        onTriggered: if (!tempRun.running) tempRun.running = true
    }
    readonly property int temp: tempDemo >= 0 ? tempDemo : tempRead

    // ---- what the sign says ("" draws nothing) and its colour ----
    readonly property string text: {
        if (!wanted) return ""
        if (choice === "mail") return Notif.dnd || mail < 0 ? "" : Icons.envelope + " " + mail
        if (choice === "battery") return battery < 0 ? "" : battery + "%"
        if (choice === "event") {
            const m = Pet.toNext
            if (!Sys.nextEvent || m < 0 || m >= 999) return ""
            return Icons.clock + " " + (m < 60 ? m + "m" : Math.floor(m / 60) + "h" + (m % 60 >= 10 ? m % 60 : m % 60 > 0 ? "0" + m % 60 : ""))
        }
        if (choice === "temp") return temp < 0 ? "" : temp + "°"
        return ""
    }
    readonly property string level: choice === "battery" && battery >= 0 && battery < 20 && (batteryDemo >= 0 || UPower.onBattery) ? "bad"
                                  : choice === "temp" && temp >= 95 ? "bad"
                                  : choice === "temp" && temp >= 85 ? "warn"
                                  : choice === "event" && Sys.nextEvent && Pet.toNext >= 0 && Pet.toNext <= 10 ? "soon"
                                  : ""
    readonly property color color: level === "bad" ? Theme.red : level === "warn" ? Theme.warn : level === "soon" ? Theme.accent : Theme.faint
}
