// One rounded pill on the bar. Hidden when it has no text (and no custom content).
import QtQuick
import Quickshell

Rectangle {
    id: pill
    property string text: ""
    property string tip: ""
    property color ink: Theme.fg
    property color fill: Theme.bg
    property color hoverFill: fill
    property color hoverInk: ink
    property color edge: Theme.line
    property bool bold: false
    property int pad: 12
    property int textSize: 13
    property int maxText: 240           // widest the label may get; longer text is cut with an ellipsis
    default property alias content: holder.data
    readonly property bool hovered: area.containsMouse

    signal clicked()
    signal rightClicked()
    signal middleClicked()
    signal scrolled(int direction)      // +1 up, -1 down

    visible: text !== "" || holder.children.length > 0
    height: parent ? parent.height : 34
    implicitWidth: (holder.children.length > 0 ? holder.childrenRect.width : Math.min(label.implicitWidth, maxText)) + 2 * pad
    width: implicitWidth
    radius: 10
    color: hovered ? hoverFill : fill
    border.width: 1
    border.color: edge

    Text {
        id: label
        visible: holder.children.length === 0
        anchors.centerIn: parent
        width: Math.min(implicitWidth, pill.maxText)
        elide: Text.ElideRight
        text: pill.text
        color: pill.hovered ? pill.hoverInk : pill.ink
        font { family: Theme.font; pixelSize: pill.textSize; bold: pill.bold }
    }
    // above the pill's own MouseArea, so buttons inside (desktop numbers, tray icons) get their clicks
    Item { id: holder; z: 1; anchors.fill: parent; anchors.leftMargin: pill.pad; anchors.rightMargin: pill.pad }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => {
            Sys.tipTarget = null
            if (mouse.button === Qt.RightButton) pill.rightClicked()
            else if (mouse.button === Qt.MiddleButton) pill.middleClicked()
            else pill.clicked()
        }
        // One step per wheel notch (120 units). A touchpad sends dozens of small events for one
        // swipe, and a sideways swipe or the event that ends a scroll has no vertical part at
        // all: counting each as a step made the volume jump and the desktops skip.
        property int wheelAcc: 0
        onWheel: wheel => {
            const d = wheel.angleDelta.y
            if (d === 0) return
            if (Math.sign(d) !== Math.sign(wheelAcc)) wheelAcc = 0
            wheelAcc += d
            while (Math.abs(wheelAcc) >= 120) { const s = Math.sign(wheelAcc); wheelAcc -= 120 * s; pill.scrolled(s) }
        }
        onEntered: if (pill.tip !== "") tipDelay.restart()
        onExited: { tipDelay.stop(); if (Sys.tipTarget === pill) Sys.tipTarget = null }
    }
    Timer {
        id: tipDelay
        interval: 600
        onTriggered: {
            Sys.tipText = pill.tip
            Sys.tipWindow = pill.QsWindow.window
            Sys.tipTarget = pill
        }
    }
    onTipChanged: if (Sys.tipTarget === pill) Sys.tipText = tip
}
