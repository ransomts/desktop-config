// Low-battery warnings: one notification at 15%, a critical one at 5%, once per discharge.
// Reads the battery from UPower (was the battery-watch script, which polled every minute).
import QtQuick
import Quickshell.Services.UPower

QtObject {
    id: warn
    readonly property var bat: UPower.displayDevice
    readonly property int pct: bat && bat.ready && bat.isLaptopBattery && bat.percentage > 0 ? Math.round(bat.percentage * 100) : -1
    readonly property bool discharging: UPower.onBattery
    property int warned: 100                // lowest level already warned about
    function check() {
        if (pct < 0) return
        if (!discharging) { warned = 100; return }      // charging or full: re-arm both warnings
        if (pct <= 5 && warned > 5) {
            warned = 5
            Sys.run("notify-send -u critical -a Battery -i battery-caution 'Battery at " + pct + "%' 'Plug in now: the laptop will shut down soon.'")
        } else if (pct <= 15 && warned > 15) {
            warned = 15
            Sys.run("notify-send -a Battery -i battery-low 'Battery at " + pct + "%' 'Plug in soon. (Power pill → Battery profile stretches it.)'")
        }
    }
    onPctChanged: check()
    onDischargingChanged: check()
}
