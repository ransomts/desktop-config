// Wallpaper popup (Super+W): pick the scene, flip each effect, try a weather
// overlay, turn the animation on or off. Stays open so several things can be
// changed in one go; click outside it or press Escape to close.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: menu
    visible: false
    color: "transparent"
    implicitWidth: 420
    implicitHeight: content.implicitHeight + 40
    screen: {
        const m = Hyprland.focusedMonitor
        return Quickshell.screens.find(s => m && s.name === m.name) || Quickshell.screens[0]
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-panel"       // same blur rule as the control panel
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    function toggle() { visible = !visible }

    HyprlandFocusGrab {
        windows: [menu]
        active: menu.visible
        onCleared: menu.visible = false
    }

    // One lit-when-on button; `cells` of them share a row evenly.
    component Chip: Rectangle {
        id: chip
        property string label
        property bool on: false
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 34
        radius: 8
        color: on ? Theme.accentBg : (tap.containsMouse ? Theme.hover : Theme.track)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            anchors.centerIn: parent
            text: chip.label
            color: chip.on ? Theme.accentInk : Theme.fg
            font { family: Theme.font; pixelSize: 12; bold: chip.on }
        }
        MouseArea { id: tap; anchors.fill: parent; hoverEnabled: true; onClicked: chip.clicked() }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Theme.panelBg
        border.width: 2
        border.color: Theme.accentBg
        focus: true
        Keys.onEscapePressed: menu.visible = false

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Wallpaper"
                    color: Theme.accent
                    font { family: Theme.font; pixelSize: 18; bold: true }
                }
                // Fills the rest of the row and elides, so a long status can't widen the popup.
                Caption {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    text: WallState.cfg.hidden ? "plain wallpaper" : !WallState.cfg.running ? "still"
                        : WallState.moving ? "moving" + (WallState.cfg.heat && WallState.fanAvg > 0 ? "  fan " + Math.round(WallState.fanAvg) : "")
                        : WallState.hot ? "resting: fan busy" : "still: on battery"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Caption { text: "Scene" }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 3; columnSpacing: 8; rowSpacing: 8
                    Repeater {
                        model: WallState.scenes
                        Chip {
                            required property string modelData
                            label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                            on: WallState.cfg.scene === modelData
                            onClicked: WallState.setScene(modelData)
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Caption { text: "Effects" }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 3; columnSpacing: 8; rowSpacing: 8
                    Repeater {
                        model: [["daylight", "Daylight"], ["music", "Music"], ["pointer", "Pointer"],
                                ["agenda", "Agenda"], ["desks", "Desktops"], ["rest", "Rest if covered"],
                                ["sharp", "No blur moving"], ["heat", "Heat guard"], ["season", "Seasonal"]]
                        Chip {
                            required property var modelData
                            label: modelData[1]
                            on: WallState.cfg[modelData[0]]
                            onClicked: WallState.setEffect(modelData[0], !on)
                        }
                    }
                }
            }

            // Heat guard limit: the wallpaper holds still when the fan averages this speed over two minutes and moves again at 80% of it.
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                opacity: WallState.cfg.heat ? 1 : 0.4
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Caption { Layout.fillWidth: true; elide: Text.ElideRight; text: "Rest when the fan averages" }
                    Caption {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: Theme.faint
                        font.pixelSize: 10
                        text: "moves again below " + WallState.fanResume
                              + (WallState.fanAvg > 0 ? "  ·  now " + Math.round(WallState.fanAvg) : "")
                              + (WallState.cpuTemp > 0 ? "  ·  " + Math.round(WallState.cpuTemp) + "°" : "")
                    }
                }
                Chip {
                    Layout.fillWidth: false; Layout.preferredWidth: 38
                    label: "−"
                    onClicked: WallState.cfg.fanMax = Math.max(1500, WallState.cfg.fanMax - 100)
                }
                Text {
                    Layout.preferredWidth: 52
                    horizontalAlignment: Text.AlignHCenter
                    text: WallState.cfg.fanMax
                    color: Theme.fg
                    font { family: Theme.font; pixelSize: 15; bold: true }
                }
                Chip {
                    Layout.fillWidth: false; Layout.preferredWidth: 38
                    label: "+"
                    onClicked: WallState.cfg.fanMax = Math.min(6000, WallState.cfg.fanMax + 100)
                }
            }

            // Weather is one choice: none, the real conditions, or one forced to try it.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Caption { text: "Weather" }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: [["off", "None"], ["", "Real"], ["rain", "Rain"], ["fog", "Fog"], ["snow", "Snow"]]
                        Chip {
                            required property var modelData
                            readonly property bool off: modelData[0] === "off"
                            label: modelData[1]
                            on: off ? !WallState.cfg.weather : WallState.cfg.weather && WallState.wxDemo === modelData[0]
                            onClicked: {
                                WallState.setEffect("weather", !off)
                                if (!off) WallState.wxDemo = modelData[0]
                            }
                        }
                    }
                }
            }

            // Moving: animated (on mains). Still: this scene, frozen. Plain: the ordinary wallpaper image.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Caption { text: "Mode" }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Chip {
                        label: "Moving"
                        on: !WallState.cfg.hidden && WallState.cfg.running
                        onClicked: { WallState.cfg.hidden = false; WallState.cfg.running = true }
                    }
                    Chip {
                        label: "Still"
                        on: !WallState.cfg.hidden && !WallState.cfg.running
                        onClicked: { WallState.cfg.hidden = false; WallState.cfg.running = false }
                    }
                    Chip {
                        label: "Plain wallpaper"
                        on: WallState.cfg.hidden
                        onClicked: WallState.cfg.hidden = true
                    }
                }
            }

            // Fewer frames a second is less work for the GPU; the scenes move slowly either way.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                opacity: !WallState.cfg.hidden && WallState.cfg.running ? 1 : 0.4
                Caption { text: "Frames a second" }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: [5, 10, 15, 20, 30]
                        Chip {
                            required property int modelData
                            label: modelData
                            on: WallState.cfg.fps === modelData
                            onClicked: WallState.cfg.fps = modelData
                        }
                    }
                }
            }

            // The scene as a screensaver after some idle minutes (Saver.qml)
            SaverRow { Layout.fillWidth: true }
        }
    }
}
