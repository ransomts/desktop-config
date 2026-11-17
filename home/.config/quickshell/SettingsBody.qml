// The settings window's content (Settings.qml loads it while open): the page list and the
// search on the left, the page (or the search results) on the right.
import QtQuick
import QtQuick.Layouts

FocusScope {
    id: body
    property var win: null
    readonly property var pages: win ? win.pages : []
    property alias query: search.text
    property int hit: 0                         // highlighted search result
    readonly property alias stack: stack
    readonly property alias searchField: search
    readonly property alias pageList: nav

    function start() { nav.forceActiveFocus() }
    function pageItem(id) { for (let i = 0; i < stack.children.length; i++) if (stack.children[i].pageId === id) return stack.children[i]; return null }
    readonly property var currentPage: pageItem(win ? win.page : "")

    // ---- every row, for the search ----
    function rowsOf(item, acc) {
        if (!item) return acc
        if (item.settingRow === true && item.label !== "") acc.push(item)
        const kids = item.children || []
        for (let i = 0; i < kids.length; i++) rowsOf(kids[i], acc)
        if (item.contentItem && item.contentItem !== item && kids.indexOf(item.contentItem) < 0) rowsOf(item.contentItem, acc)
        return acc
    }
    function collect() {
        const out = []
        for (const p of pages) {
            const pi = pageItem(p.id)
            for (const r of rowsOf(pi ? pi.contentItem : null, [])) out.push({ pageId: p.id, pageTitle: p.title, label: r.label, sub: r.sub, item: r })
        }
        return out
    }
    function matches(q) {
        const words = String(q).toLowerCase().split(/\s+/).filter(w => w !== "")
        if (words.length === 0) return []
        return collect().filter(r => {
            const hay = (r.label + " " + r.sub + " " + (r.item.keywords || "") + " " + r.pageTitle).toLowerCase()
            return words.every(w => hay.indexOf(w) >= 0)
        }).sort((a, b) => {
            const al = a.label.toLowerCase().indexOf(words[0]) >= 0 ? 0 : 1, bl = b.label.toLowerCase().indexOf(words[0]) >= 0 ? 0 : 1
            return al - bl
        })
    }
    readonly property var results: query.trim() === "" ? [] : matches(query)
    onResultsChanged: hit = 0
    function counts() { const c = {}; for (const r of results) c[r.pageId] = (c[r.pageId] || 0) + 1; return c }
    readonly property var resultCount: counts()

    function go(r) {
        if (!r) return
        win.page = r.pageId
        query = ""
        Qt.callLater(() => { const p = pageItem(r.pageId); if (p) p.reveal(r.item); if (r.item.activeFocusOnTab) r.item.forceActiveFocus(); else nav.forceActiveFocus(); r.item.flash() })
    }
    function firstRow() {
        const p = currentPage
        return p ? rowsOf(p.contentItem, []).find(r => r.activeFocusOnTab) || null : null
    }
    function step(d) { const i = Math.max(0, Math.min(pages.length - 1, win.pageIndex + d)); win.page = pages[i].id; if (currentPage) currentPage.contentY = 0 }

    Keys.onPressed: event => {
        if (event.text === "/" ) { search.forceActiveFocus(); event.accepted = true }
        else if (event.key === Qt.Key_Escape) {
            if (query !== "") { query = ""; nav.forceActiveFocus() } else win.visible = false
            event.accepted = true
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: Theme.tint(Theme.solidBg, 0.95)      // a page of small text: nearly solid, readable with or without the blur behind it
        border.width: 1
        border.color: Theme.line
        MouseArea { anchors.fill: parent }     // a click on the window is not a click on the backdrop
    }

    RowLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 16

        // ---------- left: title, search, pages ----------
        ColumnLayout {
            Layout.preferredWidth: 214
            Layout.maximumWidth: 214
            Layout.fillHeight: true
            spacing: 10
            Text {
                Layout.leftMargin: 6
                text: "Settings"
                color: Theme.accent
                font { family: Theme.font; pixelSize: 18; bold: true }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 32
                radius: 8
                color: Theme.track
                border.width: search.activeFocus ? 2 : 1
                border.color: search.activeFocus ? Theme.accentBg : Theme.line
                Text {
                    id: lens
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "/"
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 13; bold: true }
                }
                TextInput {
                    id: search
                    anchors { left: lens.right; right: parent.right; leftMargin: 8; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    clip: true
                    color: Theme.fg
                    selectionColor: Theme.hover
                    font { family: Theme.font; pixelSize: 13 }
                    activeFocusOnTab: true
                    Keys.onUpPressed: body.hit = Math.max(0, body.hit - 1)
                    Keys.onDownPressed: body.hit = Math.min(body.results.length - 1, body.hit + 1)
                    onAccepted: body.go(body.results[body.hit])
                    Keys.onEscapePressed: event => { if (text !== "") text = ""; else body.win.visible = false; nav.forceActiveFocus(); event.accepted = true }
                }
                Text {
                    anchors { left: lens.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    visible: search.text === "" && !search.activeFocus
                    text: "Search settings"
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 12; italic: true }
                }
                MouseArea { anchors.fill: parent; visible: !search.activeFocus; onClicked: search.forceActiveFocus() }
            }
            FocusScope {
                id: nav
                Layout.fillWidth: true
                Layout.fillHeight: true
                activeFocusOnTab: true
                Keys.onUpPressed: body.step(-1)
                Keys.onDownPressed: body.step(1)
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Home) { body.step(-99); event.accepted = true }
                    else if (event.key === Qt.Key_End) { body.step(99); event.accepted = true }
                    else if (event.key === Qt.Key_Right || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { const r = body.firstRow(); if (r) r.forceActiveFocus(); event.accepted = true }
                }
                Keys.onTabPressed: event => { const r = body.firstRow(); if (r) { r.forceActiveFocus(); event.accepted = true } else event.accepted = false }
                Flickable {
                    anchors.fill: parent
                    contentHeight: navCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: navCol
                        width: parent.width
                        spacing: 2
                        Repeater {
                            model: body.pages
                            Rectangle {
                                id: entry
                                required property var modelData
                                required property int index
                                readonly property bool current: body.win && body.win.page === modelData.id
                                readonly property int found: body.resultCount[modelData.id] || 0
                                width: navCol.width
                                height: 34
                                radius: 8
                                color: current ? (nav.activeFocus ? Theme.accentBg : Theme.tint(Theme.accentBg, 0.35)) : (tap.containsMouse ? Theme.hover : "transparent")
                                opacity: body.query.trim() !== "" && found === 0 ? 0.4 : 1
                                Text {
                                    id: g
                                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                    width: 22
                                    text: entry.modelData.glyph
                                    color: entry.current && nav.activeFocus ? Theme.accentInk : Theme.accent
                                    font { family: Theme.font; pixelSize: 15 }
                                }
                                Text {
                                    anchors { left: g.right; leftMargin: 6; right: badge.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                    text: entry.modelData.title
                                    elide: Text.ElideRight
                                    color: entry.current && nav.activeFocus ? Theme.accentInk : Theme.fg
                                    font { family: Theme.font; pixelSize: 13; bold: entry.current }
                                }
                                Text {
                                    id: badge
                                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                    text: entry.found > 0 ? entry.found : ""
                                    color: entry.current && nav.activeFocus ? Theme.accentInk : Theme.faint
                                    font { family: Theme.font; pixelSize: 11 }
                                }
                                MouseArea { id: tap; anchors.fill: parent; hoverEnabled: true; onClicked: { body.query = ""; body.win.page = entry.modelData.id; nav.forceActiveFocus() } }
                            }
                        }
                    }
                }
            }
            Caption {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                text: "↑↓ pages   Tab into   / search"
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }

        Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.line }

        // ---------- right: the page, or the search results ----------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            StackLayout {
                id: stack
                anchors.fill: parent
                visible: body.query.trim() === ""
                currentIndex: body.win ? body.win.pageIndex : 0
                SettingsAppearance { win: body.win }
                SettingsBar { win: body.win }
                SettingsNotifications { win: body.win }
                SettingsQuiet { win: body.win }
                SettingsClock { win: body.win }
                SettingsSaver { win: body.win }
                SettingsLecture { win: body.win }
                SettingsRecording { win: body.win }
                SettingsPet { win: body.win }
                SettingsLauncher { win: body.win }
                SettingsPower { win: body.win }
                SettingsDisplays { win: body.win }
                SettingsInput { win: body.win }
                SettingsHealth { win: body.win }
                SettingsSession { win: body.win }
                SettingsFocus { win: body.win }
                SettingsAbout { win: body.win }
            }
            ColumnLayout {
                anchors.fill: parent
                visible: body.query.trim() !== ""
                spacing: 6
                Text {
                    text: body.results.length === 0 ? "Nothing called “" + body.query.trim() + "”" : body.results.length + (body.results.length === 1 ? " setting" : " settings")
                    color: Theme.fg
                    font { family: Theme.font; pixelSize: 20; bold: true }
                }
                Caption { text: "↑↓ choose, Enter goes there"; visible: body.results.length > 0 }
                ListView {
                    id: resultList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: body.results
                    currentIndex: body.hit
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: res
                        required property var modelData
                        required property int index
                        width: resultList.width
                        height: 46
                        radius: 8
                        color: index === body.hit ? Theme.hover : rtap.containsMouse ? Theme.track : "transparent"
                        Column {
                            anchors { left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Text { width: parent.width; elide: Text.ElideRight; text: res.modelData.label; color: Theme.fg; font { family: Theme.font; pixelSize: 13; bold: res.index === body.hit } }
                            Text { width: parent.width; elide: Text.ElideRight; text: res.modelData.pageTitle + (res.modelData.sub ? "  ·  " + res.modelData.sub : ""); color: Theme.faint; font { family: Theme.font; pixelSize: 11 } }
                        }
                        MouseArea { id: rtap; anchors.fill: parent; hoverEnabled: true; onClicked: body.go(res.modelData) }
                    }
                }
            }
        }
    }
}
