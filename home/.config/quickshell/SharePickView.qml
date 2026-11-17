// The share picker's card (SharePick.qml puts it on the focused screen): tabs Screens /
// Windows / Region, live thumbnails, an "Allow restoring this share" checkbox, Share / Cancel.
// Arrow keys move, Tab or 1-3 switch tabs, Enter shares, Esc cancels. Region: pick a screen,
// then drag a box on its picture (ShotSelect.qml).
// `lists` is what ~/.local/bin/qs-share-pick parsed from xdph's environment:
//   { allowToken, outputs: [{name, x, y, w, h}], windows: [{id, cls, title, address}], workspaces }
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "shot.js" as S

Rectangle {
    id: view
    property var lists: ({ allowToken: false, outputs: [], windows: [], workspaces: [] })
    property bool live: false                   // thumbnails capture only while true
    property var screens: Quickshell.screens    // ShellScreens, matched to outputs by name
    property var toplevels: []                  // HyprlandToplevels, matched to windows by address
    property int tab: 0                         // 0 screens, 1 windows, 2 region
    property int sel: 0                         // highlighted card in tab 0 / 1 / region step 1
    property int regionOut: -1                  // region step 2: the output being boxed
    property bool allow: false
    property string tipNow: ""
    signal chosen(string line)                  // a full [SELECTION] line
    signal cancelled()

    readonly property var outs: lists.outputs || []
    readonly property var wins: lists.windows || []
    readonly property int cardCount: tab === 1 ? wins.length : regionOut >= 0 ? 0 : outs.length
    readonly property int cols: tab === 1 ? 4 : Math.max(1, Math.min(3, outs.length))

    function reset() { tab = (lists.outputs || []).length > 0 ? 0 : 1; sel = 0; regionOut = -1; allow = !!lists.allowToken; box.clear() }   // (outs may not have caught up yet)
    onListsChanged: reset()

    function screenFor(name) { return screens.find(s => s.name === name) || null }
    function toplevelFor(w) {
        const bare = (w.address || "").replace(/^0x/, "")
        return bare === "" ? null : toplevels.find(t => t.address.replace(/^0x/, "") === bare) || null
    }
    function setTab(t) { if (t === tab) return; tab = t; sel = 0; regionOut = -1; box.clear() }

    // what Enter would share now ("" = nothing yet)
    function selection() {
        if (tab === 0 && outs[sel]) return { type: "screen", output: outs[sel].name }
        if (tab === 1 && wins[sel]) return { type: "window", id: wins[sel].id }
        if (tab === 2 && regionOut >= 0 && box.has) {
            const o = outs[regionOut], k = shotArea.width / o.w
            return { type: "region", output: o.name, x: box.sx / k, y: box.sy / k, w: box.sw / k, h: box.sh / k }
        }
        return null
    }
    readonly property string pending: S.replyFor(selection(), allow)
    function share() {
        if (tab === 2 && regionOut < 0) { if (outs[sel]) regionOut = sel; return }
        const line = S.replyFor(selection(), allow)
        if (line !== "") chosen(line)
    }
    function handleKey(key, mods) {
        if (key === Qt.Key_Escape) { cancelled(); return true }
        if (key === Qt.Key_Return || key === Qt.Key_Enter) { share(); return true }
        if (key === Qt.Key_Tab || key === Qt.Key_Backtab) { setTab((tab + (key === Qt.Key_Backtab ? 2 : 1)) % 3); return true }
        if (key >= Qt.Key_1 && key <= Qt.Key_3) { setTab(key - Qt.Key_1); return true }
        if (key === Qt.Key_Space) { allow = !allow; return true }
        if (key === Qt.Key_Backspace && regionOut >= 0) { regionOut = -1; box.clear(); return true }
        const n = cardCount
        if (n === 0) return false
        const step = { [Qt.Key_Left]: -1, [Qt.Key_Right]: 1, [Qt.Key_Up]: -cols, [Qt.Key_Down]: cols }[key]
        if (step === undefined) return false
        sel = Math.max(0, Math.min(n - 1, sel + step))
        return true
    }

    implicitWidth: 960
    implicitHeight: 620
    radius: 16
    color: Theme.panelBg
    border.width: 1
    border.color: Theme.line

    ColumnLayout {
        anchors { fill: parent; margins: 18 }
        spacing: 12

        RowLayout {
            spacing: 8
            Text {
                text: "Share your screen"
                color: Theme.fg
                font { family: Theme.font; pixelSize: 17; bold: true }
                Layout.rightMargin: 12
            }
            Repeater {
                model: [ [S.G.monitor, "Screens"], [S.G.window, "Windows"], [S.G.region, "Region"] ]
                Rectangle {
                    id: tabBtn
                    required property var modelData
                    required property int index
                    implicitWidth: tabRow.implicitWidth + 22; implicitHeight: 32; radius: 9
                    color: view.tab === index ? Theme.accentBg : tabTap.containsMouse ? Theme.hover : Theme.track
                    RowLayout {
                        id: tabRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: S.glyph(tabBtn.modelData[0]); color: view.tab === tabBtn.index ? Theme.accentInk : Theme.fg; font { family: Theme.font; pixelSize: 16 } }
                        Text { text: tabBtn.modelData[1]; color: view.tab === tabBtn.index ? Theme.accentInk : Theme.fg; font { family: Theme.font; pixelSize: 13; bold: view.tab === tabBtn.index } }
                    }
                    MouseArea { id: tabTap; anchors.fill: parent; hoverEnabled: true; onClicked: view.setTab(tabBtn.index) }
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: view.tab === 2 && view.regionOut >= 0 ? "Drag a box · Backspace: another screen" : "← → ↑ ↓ move · Tab switches · Enter shares · Esc cancels"
                color: Theme.faint
                font { family: Theme.font; pixelSize: 11 }
            }
        }

        // ---- cards: screens (tab 0, region step 1) or windows (tab 1) ----
        Flickable {
            id: flick
            visible: !(view.tab === 2 && view.regionOut >= 0)
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: grid.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentY: {
                const c = cards.itemAt(view.sel)
                if (!c || grid.implicitHeight <= height) return 0
                return Math.max(0, Math.min(grid.implicitHeight - height, c.y + c.height / 2 - height / 2))
            }
            Text {
                visible: view.cardCount === 0
                anchors.centerIn: parent
                text: view.tab === 1 ? "No windows can be shared" : "No screens can be shared"
                color: Theme.faint
                font { family: Theme.font; pixelSize: 14 }
            }
            GridLayout {
                id: grid
                width: flick.width
                columns: view.cols
                columnSpacing: 12
                rowSpacing: 12
                Repeater {
                    id: cards
                    model: view.tab === 1 ? view.wins : view.outs
                    Rectangle {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property bool isWin: view.tab === 1
                        readonly property bool picked: index === view.sel
                        readonly property var src: isWin ? view.toplevelFor(modelData) : view.screenFor(modelData.name)
                        Layout.fillWidth: true
                        Layout.preferredHeight: (isWin ? 150 : 210) + 52
                        radius: 12
                        color: picked ? Theme.hover : cardTap.containsMouse ? Theme.track : "transparent"
                        border.width: 2
                        border.color: picked ? Theme.accentBg : "transparent"
                        MouseArea {
                            id: cardTap
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: view.sel = card.index
                            onDoubleClicked: { view.sel = card.index; view.share() }
                        }
                        Rectangle {
                            id: frame
                            x: 8; y: 8
                            width: parent.width - 16; height: parent.height - 60
                            radius: 6
                            color: Theme.track
                            clip: true
                            ScreencopyView {
                                id: thumb
                                anchors.centerIn: parent
                                readonly property real ar: sourceSize.height > 0 ? sourceSize.width / sourceSize.height
                                    : card.isWin ? frame.width / frame.height : card.modelData.w / card.modelData.h
                                width: Math.min(frame.width, frame.height * ar)
                                height: Math.min(frame.height, frame.width / ar)
                                captureSource: view.live && card.src ? (card.isWin ? card.src.wayland : card.src) : null
                                live: true
                            }
                            IconImage {
                                visible: !thumb.hasContent && card.isWin
                                anchors.centerIn: parent
                                implicitSize: 56
                                source: winIcon.source
                            }
                            Text {
                                visible: !thumb.hasContent && !card.isWin
                                anchors.centerIn: parent
                                text: S.glyph(S.G.monitor)
                                color: Theme.faint
                                font { family: Theme.font; pixelSize: 48 }
                            }
                        }
                        RowLayout {
                            x: 10; y: parent.height - 46
                            width: parent.width - 20
                            spacing: 8
                            IconImage {
                                id: winIcon
                                visible: card.isWin
                                implicitSize: 22
                                source: {
                                    if (!card.isWin) return ""
                                    const e = DesktopEntries.heuristicLookup(card.modelData.cls)
                                    return Quickshell.iconPath(e && e.icon ? e.icon : String(card.modelData.cls).toLowerCase(), true)
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: card.isWin ? (card.modelData.title || card.modelData.cls) : card.modelData.name
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    color: card.picked ? Theme.accent : Theme.fg
                                    font { family: Theme.font; pixelSize: 12; bold: card.picked }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: card.isWin ? card.modelData.cls : card.modelData.w + " × " + card.modelData.h
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: Theme.faint
                                    font { family: Theme.font; pixelSize: 10 }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- region step 2: the chosen screen, with a box to drag ----
        Item {
            id: regionPane
            visible: view.tab === 2 && view.regionOut >= 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            readonly property var out: view.regionOut >= 0 ? view.outs[view.regionOut] : null
            Item {
                id: shotArea
                anchors.centerIn: parent
                readonly property real ar: regionPane.out ? regionPane.out.w / regionPane.out.h : 16 / 9
                width: Math.min(parent.width, parent.height * ar)
                height: Math.min(parent.height, parent.width / ar)
                Rectangle { anchors.fill: parent; color: Theme.track; radius: 4 }
                ScreencopyView {
                    anchors.fill: parent
                    captureSource: view.live && regionPane.visible && regionPane.out ? view.screenFor(regionPane.out.name) : null
                    live: false
                }
                ShotSelect {
                    id: box
                    anchors.fill: parent
                    unit: regionPane.out ? regionPane.out.w / shotArea.width : 1
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                implicitWidth: allowRow.implicitWidth + 16; implicitHeight: 32; radius: 8
                color: allowTap.containsMouse ? Theme.hover : "transparent"
                RowLayout {
                    id: allowRow
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: S.glyph(view.allow ? S.G.checked : S.G.unchecked); color: view.allow ? Theme.accent : Theme.fg; font { family: Theme.font; pixelSize: 18 } }
                    Text { text: "Allow restoring this share"; color: Theme.fg; font { family: Theme.font; pixelSize: 13 } }
                }
                MouseArea { id: allowTap; anchors.fill: parent; hoverEnabled: true; onClicked: view.allow = !view.allow }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                implicitWidth: 96; implicitHeight: 34; radius: 9
                color: cancelTap.containsMouse ? Theme.hover : Theme.track
                Text { anchors.centerIn: parent; text: "Cancel"; color: Theme.fg; font { family: Theme.font; pixelSize: 13 } }
                MouseArea { id: cancelTap; anchors.fill: parent; hoverEnabled: true; onClicked: view.cancelled() }
            }
            Rectangle {
                readonly property bool ready: view.pending !== "" || (view.tab === 2 && view.regionOut < 0 && view.outs.length > 0)
                implicitWidth: 110; implicitHeight: 34; radius: 9
                color: ready ? Theme.accentBg : Theme.track
                opacity: ready ? 1 : 0.6
                Text {
                    anchors.centerIn: parent
                    text: view.tab === 2 && view.regionOut < 0 ? "Next" : "Share"
                    color: parent.ready ? Theme.accentInk : Theme.dim
                    font { family: Theme.font; pixelSize: 13; bold: true }
                }
                MouseArea { anchors.fill: parent; enabled: parent.ready; onClicked: view.share() }
            }
        }
    }
}
