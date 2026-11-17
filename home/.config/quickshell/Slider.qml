// A plain level bar: drag or scroll to change, right-click for the secondary action.
import QtQuick

Rectangle {
    id: s
    property real value: 0          // 0..1
    property bool off: false        // drawn grey (muted)
    signal moved(real value)
    signal rightClicked()

    implicitHeight: 14
    radius: height / 2
    color: Theme.track
    Rectangle {
        width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, s.value)))
        height: parent.height
        radius: parent.radius
        color: s.off ? Theme.dim : Theme.accentBg
    }
    MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        function at(mouse) { return Math.max(0, Math.min(1, (mouse.x - 6) / s.width)) }
        onPressed: mouse => { if (mouse.button === Qt.RightButton) s.rightClicked(); else s.moved(at(mouse)) }
        onPositionChanged: mouse => { if (pressedButtons & Qt.LeftButton) s.moved(at(mouse)) }
        onWheel: wheel => s.moved(Math.max(0, Math.min(1, s.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
