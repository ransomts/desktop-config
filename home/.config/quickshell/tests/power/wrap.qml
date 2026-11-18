// The singleton wrappers Breaks.qml and Charge.qml load and answer, on their own in a fresh process
// (a singleton shares its files with any second copy, so it cannot sit in the main harness).
import QtQuick
import Quickshell

ShellRoot {
    Timer {
        interval: 700; running: true
        onTriggered: {
            const ok = typeof Breaks.status() === "string" && Breaks.status().indexOf("off") === 0 && Breaks.line === "" && Breaks.enabled === false
            console.log("PWRTEST " + (ok ? "PASS" : "FAIL") + " Breaks singleton: off by default, status and line answer   [" + Breaks.status() + "]")
            Breaks.setKey("workMinutes", "40")
            Breaks.setEnabled(true)
            console.log("PWRTEST " + (Breaks.enabled && Breaks.status().indexOf("nudge at 40") > 0 ? "PASS" : "FAIL") + " Breaks singleton: on and set work   [" + Breaks.status() + "]")
            console.log("PWRTEST " + (Charge.status() !== undefined && Charge.loaded === false ? "PASS" : "FAIL") + " Charge singleton answers before it has read   [" + Charge.status() + "]")
            Qt.quit()
        }
    }
}
