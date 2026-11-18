// App launcher (Super+D): apps you start most come first; type to filter, Up/Down or Tab to move, Enter to start,
// Escape or a click outside to close. Apps start through `uwsm app`, like the
// fuzzel launcher this replaces (fuzzel still backs the other menus).
import QtQuick
import "fuzzy.js" as Fuzzy
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

PanelWindow {
    id: launcher
    visible: false
    function toggle() { visible = !visible }

    readonly property var all: DesktopEntries.applications.values.filter(e => !e.noDisplay && e.name !== "")
    // lower is better; -1 = no match
    function score(e, q) {
        const name = e.name.toLowerCase()
        if (name.startsWith(q)) return 0
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 1
        if (name.indexOf(q) !== -1) return 2
        const more = (e.genericName + " " + String(e.keywords) + " " + e.comment).toLowerCase()
        return more.indexOf(q) !== -1 ? 3 : -1
    }
    // How often and how recently each app was started from here, so favourites
    // float to the top: { "<id>": { n: launches, t: last launch (ms) } }
    property var usage: ({})
    FileView {
        id: usageFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/launcher-usage.json"
        printErrors: false
        onLoaded: { try { launcher.usage = JSON.parse(text()) } catch (e) { launcher.usage = {} } }
    }
    function weight(e) {
        const u = usage[e.id]
        if (!u) return 0
        const days = (Date.now() - u.t) / 86400000
        return u.n * (days < 1 ? 4 : days < 7 ? 2 : days < 30 ? 1 : 0.5)
    }
    readonly property var results: {
        const q = query.text.trim().toLowerCase()
        let list = all.map(e => ({ e: e, s: q === "" ? 0 : score(e, q), w: weight(e) })).filter(x => x.s >= 0)
        if (list.length === 0 && q !== "") {
            // nothing matched as typed: allow a slip or two per word (fuzzy.js); the name counts before the description
            const words = q.split(/\s+/)
            for (const e of all) {
                let d = Fuzzy.score(words, Fuzzy.tokens(e.name))
                if (d === -1) {
                    d = Fuzzy.score(words, Fuzzy.tokens(e.name + " " + e.genericName + " " + String(e.keywords) + " " + e.comment))
                    if (d !== -1) d += 10
                }
                if (d !== -1) list.push({ e: e, s: d, w: weight(e) })
            }
        }
        list.sort((a, b) => a.s - b.s || b.w - a.w || a.e.name.localeCompare(b.e.name))
        return list.map(x => x.e)
    }
    function launch(e) {
        if (!e) return
        visible = false
        const u = Object.assign({}, usage)
        u[e.id] = { n: (u[e.id] ? u[e.id].n : 0) + 1, t: Date.now() }
        usage = u
        usageFile.setText(JSON.stringify(u))
        const id = e.id.endsWith(".desktop") ? e.id : e.id + ".desktop"
        Sys.run("uwsm app -- '" + id.replace(/'/g, "") + "'")
    }

    onVisibleChanged: if (visible) { query.text = ""; list.currentIndex = 0; query.forceActiveFocus() }

    screen: {
        const m = Hyprland.focusedMonitor
        return Quickshell.screens.find(s => m && s.name === m.name) || Quickshell.screens[0]
    }
    color: "transparent"
    implicitWidth: 560
    implicitHeight: 470
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-launcher"     // blurred by a layer rule in hyprland.lua
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    HyprlandFocusGrab {
        windows: [launcher]
        active: launcher.visible
        onCleared: launcher.visible = false
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Theme.panelBg
        border.width: 2
        border.color: Theme.accentBg

        ColumnLayout {
            anchors { fill: parent; margins: 14 }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "›"; color: Theme.accent; font { family: Theme.font; pixelSize: 22; bold: true } }
                TextInput {
                    id: query
                    Layout.fillWidth: true
                    color: Theme.fg
                    selectionColor: Theme.accentBg
                    selectedTextColor: Theme.accentInk
                    font { family: Theme.font; pixelSize: 17 }
                    clip: true
                    onTextChanged: list.currentIndex = 0
                    Keys.onEscapePressed: launcher.visible = false
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onTabPressed: list.incrementCurrentIndex()
                    Keys.onBacktabPressed: list.decrementCurrentIndex()
                    Keys.onReturnPressed: launcher.launch(launcher.results[list.currentIndex])
                    Keys.onEnterPressed: launcher.launch(launcher.results[list.currentIndex])
                    Text {
                        visible: query.text === ""
                        text: "Search apps"
                        color: Theme.faint
                        font: query.font
                    }
                }
                Caption { text: launcher.results.length + (launcher.results.length === 1 ? " app" : " apps") }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: launcher.results
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                keyNavigationWraps: true          // Down on the last row goes to the first, Up on the first to the last
                delegate: Rectangle {
                    id: item
                    required property var modelData
                    required property int index
                    readonly property bool sel: ListView.isCurrentItem
                    width: list.width
                    height: 42
                    radius: 8
                    color: sel ? Theme.accentBg : "transparent"
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 12
                        IconImage {
                            implicitSize: 26
                            // "" when the theme has no such icon: an empty slot, not a placeholder
                            source: Quickshell.iconPath(item.modelData.icon, true)
                        }
                        Text {
                            text: item.modelData.name
                            color: item.sel ? Theme.accentInk : Theme.fg
                            font { family: Theme.font; pixelSize: 14 }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: item.modelData.comment || item.modelData.genericName
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignRight
                            color: item.sel ? Theme.accentInk : Theme.faint
                            font { family: Theme.font; pixelSize: 11 }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: list.currentIndex = item.index
                        onClicked: launcher.launch(item.modelData)
                    }
                }
            }
        }
    }
}
