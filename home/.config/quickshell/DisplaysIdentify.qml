// Identify for Settings > Displays: each screen's name, large, in its top-left corner for a few
// seconds. flash(list) with list = [{ name, label, description }] from display-layout current
// (screens not in the list show nothing). The windows exist only while shown and never take
// input or focus. shell.qml: DisplaysIdentify { id: displaysIdentify } and Settings's
// `identify: displaysIdentify`.
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: ident
    property var byName: ({})
    property bool on: false
    property int ms: 4000
    function flash(list) {
        const o = {}
        let i = 1
        for (const m of list || []) if (m && m.name && !m.off) o[m.name] = { n: i++, label: m.label || m.name, description: m.description || "" }
        byName = o
        on = Object.keys(o).length > 0
        hide.restart()
    }
    Timer { id: hide; interval: ident.ms; onTriggered: ident.on = false }

    LazyLoader {
        active: ident.on
        Variants {
            model: Quickshell.screens
            PanelWindow {
                id: w
                required property var modelData
                readonly property var info: ident.byName[modelData.name] || null
                screen: modelData
                visible: info !== null
                color: "transparent"
                anchors { top: true; left: true }
                margins { top: 60; left: 40 }
                implicitWidth: tag.width
                implicitHeight: tag.height
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "qs-display-identify"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region {}
                Rectangle {
                    id: tag
                    width: col.implicitWidth + 48
                    height: col.implicitHeight + 32
                    radius: 18
                    color: Theme.solidBg
                    border.width: 3
                    border.color: Theme.accentBg
                    Column {
                        id: col
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            text: w.info ? w.info.label : ""
                            color: Theme.fg
                            font { family: Theme.font; pixelSize: 44; bold: true }
                        }
                        Text {
                            text: w.info ? w.modelData.name + "  ·  " + w.info.description : ""
                            color: Theme.faint
                            font { family: Theme.font; pixelSize: 15 }
                        }
                    }
                }
            }
        }
    }
}
