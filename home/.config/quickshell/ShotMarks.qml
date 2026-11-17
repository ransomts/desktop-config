// The annotations of the screenshot editor, in the frame's coordinates, bottom to top:
//   pixelate boxes (the frozen frame sampled at low resolution, so nothing below is legible),
//   Ink.qml strokes (pen, marker, line, arrow, box, ellipse; owned by the lecture-draw feature),
//   numbered step badges, text labels.
// One undo history covers all four, in the order things were added.
import QtQuick
import "shot.js" as S

Item {
    id: marks
    property Item frame: null           // what pixelate boxes sample (the frozen frame)
    property string tool: "arrow"       // pen marker line arrow box ellipse | text step pixel | crop (none here)
    property color ink: Theme.accentBg
    property real weight: 4
    property bool active: true          // false: shown, ignores the mouse

    readonly property var inkTools: ["pen", "marker", "line", "arrow", "box", "ellipse"]
    readonly property bool inkTool: inkTools.indexOf(tool) !== -1

    property var pixels: []             // [{x, y, w, h}]
    property var steps: []              // [{x, y, n, ink, size}]
    property var texts: []              // [{x, y, text, ink, size}]
    property var history: []            // "ink" | "pixel" | "step" | "text", oldest first
    readonly property int count: history.length
    readonly property bool editing: entry.visible
    property int inkSeen: 0
    signal changed()

    readonly property alias ink2: inkLayer      // the Ink item (tests look at its strokes)

    function textSize() { return Math.round(14 + weight * 2) }
    function badgeSize() { return Math.round(18 + weight * 2.5) }
    function nextStep() { return steps.length + 1 }

    function push(kind) { history = history.concat([kind]); changed() }
    function addPixel(r) { if (r.w < 4 || r.h < 4) return; pixels = pixels.concat([r]); push("pixel") }
    function addStep(x, y) { steps = steps.concat([{ x: x, y: y, n: nextStep(), ink: String(ink), size: badgeSize() }]); push("step") }
    function addText(x, y, text) {
        if (text.trim() === "") return
        texts = texts.concat([{ x: x, y: y, text: text, ink: String(ink), size: textSize() }]); push("text")
    }
    function undo() {
        commitText()
        if (history.length === 0) return false
        const kind = history[history.length - 1]
        history = history.slice(0, -1)
        if (kind === "ink") { inkLayer.undo(); inkSeen = inkLayer.count }
        else if (kind === "pixel") pixels = pixels.slice(0, -1)
        else if (kind === "step") steps = steps.slice(0, -1)
        else if (kind === "text") texts = texts.slice(0, -1)
        changed()
        return true
    }
    function clearAll() {
        entry.visible = false
        pixels = []; steps = []; texts = []; history = []
        inkLayer.strokes = []; inkSeen = 0
    }

    // a label being typed: click starts it, Enter (or another click, or a tool change) ends it
    function startText(x, y) {
        commitText()
        entry.x = x; entry.y = y - textSize() / 2
        entry.text = ""
        entry.visible = true
        entry.forceActiveFocus()
    }
    function commitText() {
        if (!entry.visible) return
        entry.visible = false
        addText(entry.x, entry.y, entry.text)
        entry.text = ""
        focusBack()
    }
    signal focusBack()                  // the editor takes the keyboard back
    onToolChanged: commitText()

    // ---- pixelate ----
    // The frame is halved four times (each step a smooth 2x2 average), then drawn back at full
    // size without smoothing: 16 px blocks, each the mean of what was under it.
    Repeater {
        model: marks.pixels
        Item {
            id: pix
            required property var modelData
            x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
            function tex(div) { return Qt.size(Math.max(1, Math.round(width / div)), Math.max(1, Math.round(height / div))) }
            ShaderEffectSource {
                id: p1
                anchors.fill: parent
                sourceItem: marks.frame
                sourceRect: Qt.rect(pix.modelData.x, pix.modelData.y, pix.modelData.w, pix.modelData.h)
                textureSize: pix.tex(1)
                hideSource: false
            }
            ShaderEffectSource { id: p2; anchors.fill: parent; sourceItem: p1; hideSource: true; textureSize: pix.tex(2) }
            ShaderEffectSource { id: p3; anchors.fill: parent; sourceItem: p2; hideSource: true; textureSize: pix.tex(4) }
            ShaderEffectSource { id: p4; anchors.fill: parent; sourceItem: p3; hideSource: true; textureSize: pix.tex(8) }
            ShaderEffectSource { anchors.fill: parent; sourceItem: p4; hideSource: true; textureSize: pix.tex(16); smooth: false }
        }
    }
    Rectangle {
        id: pixGhost
        visible: false
        color: "transparent"
        border.width: 1
        border.color: Theme.accentBg
    }

    // ---- strokes ----
    Ink {
        id: inkLayer
        anchors.fill: parent
        tool: marks.inkTool ? marks.tool : "pen"
        ink: marks.ink
        weight: marks.weight
        interactive: marks.active && marks.inkTool
        onEdited: {
            if (inkLayer.count > marks.inkSeen) marks.push("ink")
            marks.inkSeen = inkLayer.count
        }
    }

    // ---- step badges ----
    Repeater {
        model: marks.steps
        Rectangle {
            required property var modelData
            readonly property color fill: modelData.ink
            x: modelData.x - width / 2; y: modelData.y - height / 2
            width: modelData.size; height: modelData.size; radius: width / 2
            color: fill
            border.width: 2
            border.color: S.lum(fill) > 0.55 ? Theme.accentInk : Theme.altInk
            Text {
                anchors.centerIn: parent
                text: parent.modelData.n
                color: S.lum(parent.fill) > 0.55 ? Theme.accentInk : Theme.altInk
                font { family: Theme.font; pixelSize: parent.height * 0.55; bold: true }
            }
        }
    }

    // ---- text labels ----
    Repeater {
        model: marks.texts
        Text {
            required property var modelData
            x: modelData.x; y: modelData.y
            text: modelData.text
            textFormat: Text.PlainText
            color: modelData.ink
            style: Text.Outline
            styleColor: S.lum(Qt.color(modelData.ink)) > 0.55 ? Theme.accentInk : Theme.altInk
            font { family: Theme.font; pixelSize: modelData.size; bold: true }
        }
    }
    TextInput {
        id: entry
        visible: false
        color: marks.ink
        font { family: Theme.font; pixelSize: marks.textSize(); bold: true }
        cursorVisible: visible
        selectByMouse: false
        Keys.onReturnPressed: event => { marks.commitText(); event.accepted = true }
        Keys.onEnterPressed: event => { marks.commitText(); event.accepted = true }
        Rectangle {     // where the label goes, while it is typed
            anchors { fill: parent; margins: -4 }
            z: -1
            color: "transparent"
            radius: 4
            border.width: 1
            border.color: marks.ink
        }
    }

    // ---- the mouse for text, step and pixelate (Ink takes it for its own tools) ----
    MouseArea {
        anchors.fill: parent
        enabled: marks.active && (marks.tool === "text" || marks.tool === "step" || marks.tool === "pixel")
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        cursorShape: marks.tool === "text" ? Qt.IBeamCursor : Qt.CrossCursor
        property real x0: 0
        property real y0: 0
        onPressed: mouse => {
            x0 = mouse.x; y0 = mouse.y
            if (marks.tool === "pixel") { pixGhost.x = x0; pixGhost.y = y0; pixGhost.width = 0; pixGhost.height = 0; pixGhost.visible = true }
        }
        onPositionChanged: mouse => {
            if (!pressed || marks.tool !== "pixel") return
            const r = S.spanRect(x0, y0, mouse.x, mouse.y, marks.width, marks.height)
            pixGhost.x = r.x; pixGhost.y = r.y; pixGhost.width = r.w; pixGhost.height = r.h
        }
        onReleased: mouse => {
            if (marks.tool === "pixel") {
                pixGhost.visible = false
                marks.addPixel(S.spanRect(x0, y0, mouse.x, mouse.y, marks.width, marks.height))
            } else if (marks.tool === "step") marks.addStep(mouse.x, mouse.y)
            else if (marks.tool === "text") marks.startText(mouse.x, mouse.y)
        }
    }
}
