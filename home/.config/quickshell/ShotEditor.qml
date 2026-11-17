// The screenshot editor on one screen's frozen frame (Shot.qml puts one on every screen).
//   phase "select":   drag a box (handles adjust it); double-click or Enter with no box = the
//                     whole screen; w = the window under the pointer. A box goes to "annotate".
//   phase "annotate": draw inside the box with the toolbar's tools (ShotMarks.qml + Ink.qml),
//                     crop tool = move/resize the box. Enter or Save: requestFinish("save");
//                     Ctrl+C: requestFinish("copy"); Esc: requestFinish("cancel");
//                     right-click: back to "select".
// The frame is whatever Item is declared inside (a ScreencopyView in Shot, an Image in the tests);
// exportTo() renders the box at the frame's own resolution (frameScale device px per px).
import QtQuick
import QtQuick.Layouts
import "shot.js" as S

Item {
    id: ed
    default property alias frameData: frameHolder.data
    property real frameScale: 1             // device pixels of the frame per item pixel
    property var windows: []                // [{x, y, w, h, title, floating}] in this item's coordinates (w snaps)
    property string phase: "select"
    property string tool: "arrow"
    property color ink: Theme.accentBg
    property real weight: 4
    property bool rendering: false
    property bool ready: true               // false: only the frame is drawn (Shot waits for the capture)
    property string tipNow: ""              // the toolbar button under the pointer
    readonly property alias box: select
    readonly property alias marks: marks
    readonly property alias toolbar: bar
    readonly property int outWidth: Math.max(1, Math.round(select.sw * frameScale))
    readonly property int outHeight: Math.max(1, Math.round(select.sh * frameScale))
    signal requestFinish(string how)        // save | copy | cancel
    signal claimed()                        // a box was begun here (Shot clears the other screens)

    function annotate() { if (select.has) { phase = "annotate"; keyFocus() } }
    function selectAll() { select.set(0, 0, width, height) }
    function backToSelect() { marks.commitText(); phase = "select"; select.clear(); keyFocus() }
    function reset() { marks.clearAll(); phase = "select"; select.clear() }
    function snapWindow(px, py) {
        const w = S.windowAt(windows, px, py)
        if (!w) return false
        claimed()
        select.set(w.x, w.y, w.w, w.h)
        annotate()
        return true
    }
    function undo() { return marks.undo() }
    function keyFocus() { keys.forceActiveFocus() }

    // keys, as Shot.qml routes them; true when used
    function handleKey(key, mods) {
        const ctrl = (mods & Qt.ControlModifier) !== 0
        if (key === Qt.Key_Escape) { requestFinish("cancel"); return true }
        if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            if (phase === "select") { if (!select.has) { claimed(); selectAll() } annotate() }
            else { marks.commitText(); requestFinish("save") }
            return true
        }
        if (ctrl && key === Qt.Key_C) {
            if (!select.has) { claimed(); selectAll() }
            marks.commitText(); requestFinish("copy"); return true
        }
        if (ctrl && key === Qt.Key_Z) { if (phase === "annotate") undo(); return true }
        if (ctrl) return false
        if (phase === "select") {
            if (key === Qt.Key_W) { snapWindow(select.pointerX, select.pointerY); return true }
            return false
        }
        const t = { [Qt.Key_P]: "pen", [Qt.Key_M]: "marker", [Qt.Key_L]: "line", [Qt.Key_A]: "arrow", [Qt.Key_B]: "box",
                    [Qt.Key_E]: "ellipse", [Qt.Key_T]: "text", [Qt.Key_N]: "step", [Qt.Key_X]: "pixel", [Qt.Key_C]: "crop" }[key]
        if (t) { tool = t; return true }
        return false
    }

    // Render the box to a PNG at the frame's resolution; done(ok) afterwards.
    function exportTo(path, done) {
        marks.commitText()
        if (!select.has) { done(false); return }
        rendering = true
        renderPending.path = path
        renderPending.done = done
        renderPending.restart()         // the layer below gets one frame to fill before the grab
    }
    Timer {
        id: renderPending
        interval: 60
        property string path: ""
        property var done: null
        onTriggered: {
            const p = path, d = done
            const ok = renderBox.grabToImage(r => {
                const saved = r.saveToFile(p)
                ed.rendering = false
                if (d) d(saved)
            }, Qt.size(ed.outWidth, ed.outHeight))
            if (!ok) { ed.rendering = false; if (d) d(false) }
        }
    }

    // ---- what gets saved: the frame and the marks ----
    Item {
        id: content
        anchors.fill: parent
        Item { id: frameHolder; anchors.fill: parent }
        Item {          // the marks only show (and take the mouse) inside the box
            x: select.sx; y: select.sy; width: select.sw; height: select.sh
            clip: true
            visible: select.has && ed.ready
            ShotMarks {
                id: marks
                x: -select.sx; y: -select.sy
                width: ed.width; height: ed.height
                frame: frameHolder
                tool: ed.tool
                ink: ed.ink
                weight: ed.weight
                active: ed.phase === "annotate" && ed.tool !== "crop"
                onFocusBack: ed.keyFocus()
            }
        }
    }

    // ---- the box ----
    ShotSelect {
        id: select
        anchors.fill: parent
        visible: ed.ready
        drawing: ed.phase === "select"
        adjustable: true
        movable: ed.phase === "annotate" && ed.tool === "crop"
        unit: ed.frameScale
        readout: ed.phase === "select" || select.busy
        onStarted: ed.claimed()
        onCommitted: ed.annotate()
        onDoubleClicked: if (ed.phase === "select") { if (!select.has) { ed.claimed(); ed.selectAll() } ed.annotate() }
    }

    // ---- keyboard (Shot.qml forwards; tests call handleKey) ----
    Item { id: keys; focus: true }

    // ---- toolbar beside the box ----
    Rectangle {
        id: bar
        visible: ed.ready && ed.phase === "annotate" && select.has && !ed.rendering
        readonly property real room: 10
        width: col.implicitWidth + 16
        height: col.implicitHeight + 12
        x: Math.max(room, Math.min(ed.width - width - room, select.sx + select.sw - width))
        y: select.sy + select.sh + room + height <= ed.height ? select.sy + select.sh + room
         : select.sy - room - height >= 0 ? select.sy - room - height
         : select.sy + select.sh - height - room
        radius: 12
        color: Theme.solidBg
        border.width: 1
        border.color: Theme.line

        ColumnLayout {
            id: col
            anchors.centerIn: parent
            spacing: 4
            Row {
                spacing: 3
                Repeater {
                    model: [ ["pen", "Pen  P"], ["marker", "Marker  M"], ["line", "Line  L"], ["arrow", "Arrow  A"], ["box", "Box  B"],
                             ["ellipse", "Ellipse  E"], ["text", "Text  T"], ["step", "Numbered steps  N"], ["pixel", "Pixelate  X"], ["crop", "Adjust the box  C"] ]
                    ShotButton {
                        host: ed
                        required property var modelData
                        glyph: S.glyph(S.G[modelData[0]])
                        tip: modelData[1]
                        on: ed.tool === modelData[0]
                        onClicked: { ed.tool = modelData[0]; ed.keyFocus() }
                    }
                }
                Rectangle { width: 1; height: 26; anchors.verticalCenter: parent.verticalCenter; color: Theme.line }
                Repeater {
                    model: [Theme.accentBg, Theme.red, Theme.warn, Theme.ok, Theme.alt, Theme.altInk, Theme.accentInk]
                    Rectangle {
                        required property color modelData
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20; radius: 10
                        color: modelData
                        border.width: Qt.colorEqual(ed.ink, modelData) ? 3 : 1
                        border.color: Qt.colorEqual(ed.ink, modelData) ? Theme.fg : Theme.line
                        MouseArea { anchors.fill: parent; onClicked: { ed.ink = parent.modelData; ed.keyFocus() } }
                    }
                }
                Rectangle { width: 1; height: 26; anchors.verticalCenter: parent.verticalCenter; color: Theme.line }
                Repeater {
                    model: [2, 4, 8]
                    Rectangle {
                        required property int modelData
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 24; radius: 6
                        color: ed.weight === modelData ? Theme.hover : "transparent"
                        Rectangle { anchors.centerIn: parent; width: parent.modelData + 4; height: width; radius: width / 2; color: Theme.fg }
                        MouseArea { anchors.fill: parent; onClicked: { ed.weight = parent.modelData; ed.keyFocus() } }
                    }
                }
                Rectangle { width: 1; height: 26; anchors.verticalCenter: parent.verticalCenter; color: Theme.line }
                ShotButton { host: ed; glyph: S.glyph(S.G.undo); tip: "Undo  Ctrl+Z"; dim: marks.count === 0; onClicked: { ed.undo(); ed.keyFocus() } }
                ShotButton { host: ed; glyph: S.glyph(S.G.copy); tip: "Copy only  Ctrl+C"; onClicked: { marks.commitText(); ed.requestFinish("copy") } }
                ShotButton { host: ed; glyph: S.glyph(S.G.save); tip: "Save and copy  Enter"; on: true; onClicked: { marks.commitText(); ed.requestFinish("save") } }
                ShotButton { host: ed; glyph: S.glyph(S.G.close); tip: "Cancel  Esc"; onClicked: ed.requestFinish("cancel") }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: ed.tipNow !== "" ? ed.tipNow
                    : ed.outWidth + " × " + ed.outHeight + "   Enter save · Ctrl+C copy · Esc cancel · right-click reselect"
                color: Theme.faint
                font { family: Theme.font; pixelSize: 11 }
            }
        }
    }

    // ---- right-click anywhere: choose again (left clicks fall through) ----
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: if (ed.phase === "annotate") ed.backToSelect()
    }

    // ---- off to the side, only while saving: the box at full resolution ----
    Item {
        id: renderBox
        x: -width - 64; y: 0
        width: select.sw; height: select.sh
        visible: ed.rendering
        ShaderEffectSource {
            anchors.fill: parent
            sourceItem: ed.rendering ? content : null
            sourceRect: Qt.rect(select.sx, select.sy, select.sw, select.sh)
            textureSize: Qt.size(ed.outWidth, ed.outHeight)
            hideSource: false
            live: true
            smooth: true
        }
    }
}
