// Stand-in for Quickshell's PanelWindow, which has no backend offscreen. notify-test
// copies NotifPopups.qml with "PanelWindow {" changed to "StubPanel {", so its bindings
// load and can be checked (a copy of tests/lecture/StubPanel.qml).
import QtQuick
import Quickshell

QtObject {
    id: w
    default property list<QtObject> data
    property bool visible: false
    property color color
    property var screen: null
    property real implicitWidth
    property real implicitHeight
    property int exclusionMode
    property var mask: null
    component Edges: QtObject { property bool top; property bool bottom; property bool left; property bool right }
    component Gaps: QtObject { property int top; property int bottom; property int left; property int right }
    property Edges anchors: Edges {}
    property Gaps margins: Gaps {}
}
