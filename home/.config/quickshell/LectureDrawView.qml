// What the draw overlay shows (LectureDraw.qml puts it in a window): an optional
// board, the ink, and a small toolbar at the bottom centre. Keys (with keyboard focus):
//   1 pen  2 marker  3 arrow  4 box  5 ellipse  6 line     c colour    [ ] weight
//   u / Ctrl+Z undo   Ctrl+Shift+Z redo   x clear   b board (none / solid / the other theme's)
//   Tab hold (ink stays, clicks and keys go to the windows below until Super+Z then D)
//   Esc leave (the ink is cleared; u after coming back brings it back)
import QtQuick

Item {
    id: view
    property alias ink: ink
    readonly property var toolNames: ["pen", "marker", "arrow", "box", "ellipse", "line"]

    function handleKey(e) {
        const ctrl = (e.modifiers & Qt.ControlModifier) !== 0, shift = (e.modifiers & Qt.ShiftModifier) !== 0
        const k = e.key
        if (k === Qt.Key_Escape) Lecture.leaveDraw()
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) Lecture.hold = true
        else if (ctrl && k === Qt.Key_Z) { if (shift) ink.redo(); else ink.undo() }
        else if (ctrl && k === Qt.Key_Y) ink.redo()
        else if (ctrl || (e.modifiers & (Qt.AltModifier | Qt.MetaModifier))) return false
        else if (k >= Qt.Key_1 && k <= Qt.Key_6) Lecture.tool = toolNames[k - Qt.Key_1]
        else if (k === Qt.Key_C) Lecture.cycleColor()
        else if (k === Qt.Key_BracketLeft || k === Qt.Key_BraceLeft) Lecture.stepWeight(-1)
        else if (k === Qt.Key_BracketRight || k === Qt.Key_BraceRight) Lecture.stepWeight(1)
        else if (k === Qt.Key_U) ink.undo()
        else if (k === Qt.Key_X) ink.clear()
        else if (k === Qt.Key_B) Lecture.cycleBoard()
        else return false
        return true
    }
    function focusKeys() { keys.forceActiveFocus() }

    Connections {
        target: Lecture
        function onDrawOnChanged() { if (!Lecture.drawOn) ink.clear() }      // leaving clears (undoable next time)
        function onInkCommand(what) { if (what === "undo") ink.undo(); else if (what === "redo") ink.redo(); else if (what === "clear") ink.clear() }
    }

    Rectangle {                             // the board
        anchors.fill: parent
        visible: Lecture.board !== 0
        color: Lecture.boardColor
    }
    Ink {
        id: ink
        tool: Lecture.tool
        ink: Lecture.ink
        weight: Lecture.weight
        interactive: !Lecture.hold
    }
    Item {
        id: keys
        focus: true
        Keys.onPressed: e => { e.accepted = view.handleKey(e) }
    }

    // ---- toolbar ----
    component Chip: Rectangle {
        id: chip
        property string text
        property bool on: false
        signal clicked()
        implicitWidth: label.implicitWidth + 16
        implicitHeight: 26
        radius: 7
        color: on ? Theme.accentBg : chipTap.containsMouse ? Theme.hover : "transparent"
        Text {
            id: label
            anchors.centerIn: parent
            text: chip.text
            color: chip.on ? Theme.accentInk : Theme.fg
            font { family: Theme.font; pixelSize: 12; bold: chip.on }
        }
        MouseArea { id: chipTap; anchors.fill: parent; hoverEnabled: true; onClicked: chip.clicked() }
    }

    Rectangle {
        id: bar
        objectName: "toolbar"
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
        visible: !Lecture.hold
        width: col.implicitWidth + 16
        height: col.implicitHeight + 12
        radius: 12
        color: Theme.panelBg
        border.width: 1
        border.color: Theme.line
        opacity: barTap.containsMouse || ink.count === 0 ? 1 : 0.8
        MouseArea { id: barTap; anchors.fill: parent; hoverEnabled: true }      // the toolbar is not a drawing surface
        Column {
            id: col
            anchors.centerIn: parent
            spacing: 2
            Row {
                spacing: 2
                anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: view.toolNames
                    Chip {
                        required property string modelData
                        required property int index
                        text: (index + 1) + " " + modelData
                        on: Lecture.tool === modelData
                        onClicked: Lecture.tool = modelData
                    }
                }
                Rectangle { width: 1; height: 26; color: Theme.line }
                Rectangle {                 // colour: click for the next one
                    objectName: "swatch"
                    width: 26; height: 26; radius: 13
                    color: Lecture.ink
                    border.width: 2
                    border.color: Theme.line
                    MouseArea { anchors.fill: parent; onClicked: Lecture.cycleColor() }
                }
                Chip { text: "["; onClicked: Lecture.stepWeight(-1) }
                Item {                      // weight: a dot that size
                    width: 30; height: 26
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(26, Lecture.weight + 2); height: width; radius: width / 2
                        color: Theme.fg
                    }
                }
                Chip { text: "]"; onClicked: Lecture.stepWeight(1) }
                Rectangle { width: 1; height: 26; color: Theme.line }
                Chip { text: "b " + ["no board", "board", "board 2"][Lecture.board]; on: Lecture.board !== 0; onClicked: Lecture.cycleBoard() }
                Chip { text: "u undo"; opacity: ink.canUndo ? 1 : 0.4; onClicked: ink.undo() }
                Chip { text: "x clear"; onClicked: ink.clear() }
                Chip { text: "Tab hold"; onClicked: Lecture.hold = true }
                Chip { text: "Esc"; onClicked: Lecture.leaveDraw() }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "c colour · [ ] weight · Shift straight / square · Ctrl+Shift+Z redo · " + ink.count + (ink.count === 1 ? " stroke" : " strokes")
                color: Theme.faint
                font { family: Theme.font; pixelSize: 11 }
            }
        }
    }

    Rectangle {                             // while held: a small reminder that ink is on screen
        objectName: "holdBadge"
        visible: Lecture.hold
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
        width: holdText.implicitWidth + 20; height: 24; radius: 12
        color: Theme.panelBg
        opacity: 0.75
        Text {
            id: holdText
            anchors.centerIn: parent
            text: "ink held · Super+Z then D to draw · Super+Z then Z menu"
            color: Theme.faint
            font { family: Theme.font; pixelSize: 11 }
        }
    }
}
