// One page of the settings window: a scrolling column of SettingsCards. `win` is the window
// (Settings.qml), for its hooks (island, launcherView, cursorFind, dropPreview). `shown` is true
// while this page is the one on screen: anything that runs a command waits for it.
import QtQuick
import QtQuick.Layouts

Flickable {
    id: page
    property var win: null
    property string pageId: ""
    property string title: ""
    property string glyph: ""
    property string intro: ""
    readonly property bool shown: visible && (!win || win.visible)
    default property alias content: col.data
    contentWidth: width
    contentHeight: col.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    // bring a row into view (the search, and keyboard focus moving down the page)
    function reveal(item) {
        const p = item.mapToItem(col, 0, 0)
        if (p.y < contentY + 8) contentY = Math.max(0, p.y - 16)
        else if (p.y + item.height > contentY + height - 8) contentY = Math.min(Math.max(0, contentHeight - height), p.y + item.height - height + 16)
    }
    ColumnLayout {
        id: col
        width: page.width - 14
        spacing: 14
        Text {
            Layout.fillWidth: true
            text: page.title
            color: Theme.fg
            font { family: Theme.font; pixelSize: 20; bold: true }
        }
        Text {
            Layout.fillWidth: true
            Layout.topMargin: -8
            visible: page.intro !== ""
            text: page.intro
            wrapMode: Text.Wrap
            color: Theme.faint
            font { family: Theme.font; pixelSize: 12 }
        }
    }
    Rectangle {                                 // where you are in a long page
        visible: page.contentHeight > page.height
        x: page.width - 5; width: 4; radius: 2
        y: page.contentY + page.height * (page.contentY / page.contentHeight)
        height: page.height * page.height / page.contentHeight
        color: Theme.line
    }
}
