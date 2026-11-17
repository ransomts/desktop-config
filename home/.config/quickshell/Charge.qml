pragma Singleton
// Battery charge limit (System76 charge thresholds), through ~/.local/bin/charge-profile.
//   Charge.profile   "full_charge" | "balanced" | "max_lifespan" | "custom" | "" (not read yet)
//   Charge.label     plain name: "Full charge", "Balanced (stops at 90%)", "Longest life (stops at 60%)"
//   Charge.limited   a limit is active (anything but full charge)
//   Charge.tip       "Charging stops at 90%" while limited, else ""
//   Charge.set(name) full_charge | balanced | max_lifespan;  Charge.next() cycles;  Charge.refresh() reads again
// Read once when the shell starts, when the control panel opens (Sys.panelOpen) and after every
// change; never polled. A change asks polkit for authorisation (auth_admin), so the desktop's
// password prompt appears and `busy` stays true until it is answered. The percentages come from
// `system76-power charge-thresholds --list-profiles` (through `charge-profile list`), not from here.
// Hooks (coordinator): Panel.qml Toggle and the Bar.qml battery tooltip, see the report.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: charge

    property string profile: ""
    property int start: 0
    property int end: 100
    property var profiles: ({})             // id -> { title, start, end }, from `charge-profile list`
    property bool loaded: false
    property bool busy: false
    property string error: ""               // last failure, "" when the last call worked
    property int changes: 0                 // how many changes completed (tests, and a signal for the settings page)

    function ends(p) {
        if (p === profile) return end
        const q = profiles[p]
        return q ? q.end : (p === "balanced" ? 90 : p === "max_lifespan" ? 60 : 100)
    }
    function nameOf(p) {
        if (p === "full_charge") return "Full charge"
        if (p === "balanced") return "Balanced (stops at " + ends(p) + "%)"
        if (p === "max_lifespan") return "Longest life (stops at " + ends(p) + "%)"
        return p === "" ? "" : "Custom (stops at " + ends(p) + "%)"
    }
    readonly property string label: nameOf(profile)
    readonly property bool limited: loaded && profile !== "full_charge" && end < 100
    readonly property string tip: limited ? "Charging stops at " + end + "%" : ""

    function refresh() { if (!reader.running) reader.running = true }
    function set(name) { if (!busy && /^(full_charge|balanced|max_lifespan)$/.test(name)) { busy = true; error = ""; setter.command = Sys.clean.concat([Sys.bin + "charge-profile", "set", name]); setter.running = true } }
    function next() { if (!busy) { busy = true; error = ""; error = ""; setter.command = Sys.clean.concat([Sys.bin + "charge-profile", "next"]); setter.running = true } }
    function status() { return loaded ? label + " (" + profile + ", " + start + "-" + end + ")" + (busy ? ", waiting" : "") : "unknown" }

    // two lines: the status object, then the profile list
    Process {
        id: reader
        command: Sys.clean.concat(["sh", "-c", Sys.bin + "charge-profile status && " + Sys.bin + "charge-profile list"])
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                try {
                    const s = JSON.parse(lines[0])
                    charge.profile = String(s.profile); charge.start = s.start; charge.end = s.end
                    if (lines.length > 1) charge.profiles = JSON.parse(lines[1])
                    charge.loaded = true
                } catch (e) { charge.error = "unreadable" }
            }
        }
    }
    Process {
        id: setter
        onExited: (code) => {
            charge.busy = false
            charge.error = code === 0 ? "" : "not changed"
            charge.changes++
            charge.refresh()
        }
    }
    Component.onCompleted: refresh()
    Connections { target: Sys; function onPanelOpenChanged() { if (Sys.panelOpen) charge.refresh() } }
}
