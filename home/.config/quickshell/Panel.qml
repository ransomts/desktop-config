// Control panel (Super+C, or right-click the clock): clock, what's playing,
// sound, brightness, quick toggles and shortcuts, battery.
// Click outside it or press Escape to close.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower

PanelWindow {
    id: panel
    visible: false
    color: "transparent"
    anchors { top: true; right: true }
    margins { top: 8; right: 8 }
    implicitWidth: 360
    // as tall as its content, up to the space under the bar
    readonly property int room: (screen ? screen.height : 1080) - 42 - 16
    implicitHeight: Math.min(content.implicitHeight + 36, room)
    screen: {
        const m = Hyprland.focusedMonitor
        return Quickshell.screens.find(s => m && s.name === m.name) || Quickshell.screens[0]
    }
    exclusionMode: ExclusionMode.Normal      // sit below the bar, reserve nothing
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-panel"       // blurred by a layer rule in hyprland.lua
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    property bool allNotifs: false          // recent notifications: three, or up to twelve
    function refresh() { Theme.reload(); Sys.refreshNow(); Sys.readBrightness(); Sys.readNight() }
    onVisibleChanged: { Sys.panelOpen = visible; if (visible) { refresh(); flick.contentY = 0; allNotifs = false; Notif.markSeen() } }
    Connections { target: Sys; function onPanelToggle() { panel.visible = !panel.visible } }
    SystemClock { id: clock; precision: SystemClock.Minutes }

    HyprlandFocusGrab {
        windows: [panel]
        active: panel.visible
        onCleared: panel.visible = false
    }

    component Shortcut: Rectangle {
        id: sc
        property string label
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 32
        radius: 8
        color: scTap.containsMouse ? Theme.hover : Theme.track
        Text { anchors.centerIn: parent; text: sc.label; color: Theme.fg; font { family: Theme.font; pixelSize: 12 } }
        MouseArea { id: scTap; anchors.fill: parent; hoverEnabled: true; onClicked: { sc.clicked(); panel.visible = false } }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Theme.panelBg
        border.width: 2
        border.color: Theme.accentBg

        focus: true
        Keys.onEscapePressed: panel.visible = false

        // The sections can outgrow the screen (many audio streams, notifications):
        // the panel stops at the screen's height and scrolls inside.
        Flickable {
            id: flick
            anchors { fill: parent; margins: 18; rightMargin: 12 }
            contentWidth: width
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

        ColumnLayout {
            id: content
            width: flick.width - 6
            spacing: 16

            ColumnLayout {
                spacing: 0
                Text {
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    color: Theme.accent
                    font { family: Theme.font; pixelSize: 44; bold: true }
                }
                Text {
                    text: Qt.formatDateTime(clock.date, "dddd, MMMM d")
                    color: Theme.fg
                    font { family: Theme.font; pixelSize: 14 }
                }
                Caption {
                    Layout.topMargin: 4
                    Layout.maximumWidth: 320
                    visible: Sys.currentEvent !== null || Sys.nextEvent !== null
                    elide: Text.ElideRight
                    text: Sys.currentEvent ? "Now: " + Sys.currentEvent.title + " (until " + Sys.currentEvent.end + ")"
                        : Sys.nextEvent ? "Next: " + Sys.nextEvent.start + "  " + Sys.nextEvent.title : ""
                }
            }

            MediaCard { Layout.fillWidth: true }

            Mixer { Layout.fillWidth: true }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    Caption { text: "Brightness" }
                    Item { Layout.fillWidth: true }
                    Caption { color: Theme.fg; text: Math.round(Sys.brightness * 100) + "%" }
                }
                Slider {
                    Layout.fillWidth: true
                    value: Sys.brightness
                    onMoved: v => Sys.setBrightness(v)
                }
                RowLayout {
                    visible: Sys.night
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Caption { text: "Night light" }
                    Item { Layout.fillWidth: true }
                    Caption { color: Theme.fg; text: Sys.nightK + " K" }
                }
                Slider {            // left = warmer; 2500 K .. 5800 K
                    visible: Sys.night
                    Layout.fillWidth: true
                    value: (Sys.nightK - 2500) / 3300
                    onMoved: v => Sys.setNight(2500 + v * 3300)
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 10
                rowSpacing: 10
                Toggle {
                    caption: "Theme"
                    label: Theme.dark ? "Dark" : "Light"
                    on: Theme.dark
                    onClicked: Sys.run(Sys.bin + "cosmic-theme-toggle")
                }
                Toggle {
                    caption: "Notifications"
                    label: Sys.dnd.cls === "on" ? "Silenced" : "On"
                    on: Sys.dnd.cls === "on"
                    onClicked: { Sys.run(Sys.bin + "dnd-toggle"); Sys.refreshSoon() }
                }
                Toggle {
                    caption: "Keep awake"
                    label: Sys.keepAwake ? "On" : "Off"
                    on: Sys.keepAwake
                    onClicked: Sys.keepAwake = !Sys.keepAwake
                }
                Toggle {
                    caption: "Sounds"
                    label: Sys.sounds ? "On" : "Off"
                    on: Sys.sounds
                    onClicked: Sys.setSounds(!Sys.sounds)
                }
                Toggle {
                    caption: "Wi-Fi"
                    label: Sys.netKind === "wifi" ? Sys.netName : Sys.netKind === "wired" ? "Wired" : "Offline"
                    on: Sys.netKind !== "offline"
                    onClicked: { panel.visible = false; Sys.popupRequest("wifi") }
                }
                Toggle {
                    caption: "Power profile"
                    label: Sys.profile.cls === "" ? "—" : Sys.profile.cls.charAt(0).toUpperCase() + Sys.profile.cls.slice(1)
                    on: Sys.profile.cls === "performance"
                    onClicked: Sys.nextProfile()
                }
                Toggle {            // battery care (Charge.qml): where charging stops; a change asks for the password
                    caption: "Charge limit"
                    label: Charge.loaded ? Charge.label : "—"
                    on: Charge.limited
                    onClicked: Charge.next()
                }
                Toggle {
                    caption: "Night light"
                    label: Sys.night ? Sys.nightK + " K" : "Off"
                    on: Sys.night
                    onClicked: Sys.setNight(Sys.night ? 6000 : Sys.nightWanted)
                }
                Toggle {
                    caption: "Tailscale"
                    label: Sys.tail.cls !== "on" ? "Off" : Sys.tail.text !== "" ? "via " + Sys.tail.text : "Connected"
                    on: Sys.tail.cls === "on"
                    onClicked: Sys.setTailscale(Sys.tail.cls !== "on")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Shortcut { label: "Bluetooth"; onClicked: Sys.popupRequest("bluetooth") }
                Shortcut { label: "Power";     onClicked: Sys.popupRequest("power") }
                Shortcut { label: Pet.enabled ? "Hide pet" : "Show pet"; onClicked: Pet.setEnabled(!Pet.enabled) }
                Shortcut { label: "Settings"; onClicked: Sys.run(Quickshell.env("HOME") + "/.nix-profile/bin/qs ipc call settings toggle") }
            }

            // focus profiles (Profiles.qml): Teaching, Grading, Writing
            FocusRow { Layout.fillWidth: true }

            // lecture tools: draw on the screen, spotlight, key display, zoom, countdown (Lecture.qml, Super+Z)
            LecturePanel { Layout.fillWidth: true; onUsed: panel.visible = false }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: Notif.history.length > 0
                RowLayout {
                    Layout.fillWidth: true
                    Caption { text: "Recent notifications" }
                    Item { Layout.fillWidth: true }
                    Caption {
                        visible: Notif.groups.length > 3
                        text: panel.allNotifs ? "Fewer" : "All " + Math.min(12, Notif.groups.length)
                        color: moreTap.containsMouse ? Theme.accent : Theme.faint
                        Layout.rightMargin: 10
                        MouseArea { id: moreTap; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: panel.allNotifs = !panel.allNotifs }
                    }
                    Caption {
                        text: "Clear"
                        color: clearTap.containsMouse ? Theme.accent : Theme.faint
                        MouseArea { id: clearTap; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: Notif.clear() }
                    }
                }
                NotifGroups { Layout.fillWidth: true; limit: panel.allNotifs ? 12 : 3 }
            }

            Caption {
                readonly property var bat: UPower.displayDevice
                visible: !!bat && bat.isPresent
                text: !bat ? "" : "Battery " + Math.round(bat.percentage * 100) + "%"
                    + (bat.state === UPowerDeviceState.Charging ? ", charging"
                     : bat.state === UPowerDeviceState.FullyCharged ? ", full" : "")
            }
        }
        }
        // scroll position, shown only when there is more than fits
        Rectangle {
            visible: flick.contentHeight > flick.height + 1
            anchors.right: parent.right
            anchors.rightMargin: 5
            y: flick.y + flick.visibleArea.yPosition * flick.height
            width: 3
            height: Math.max(24, flick.visibleArea.heightRatio * flick.height)
            radius: 2
            color: Theme.dim
        }

    }
}
