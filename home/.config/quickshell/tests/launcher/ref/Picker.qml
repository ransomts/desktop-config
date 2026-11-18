// "Pick one line from a list", in the launcher's style: the Quickshell stand-in
// for `fuzzel --dmenu`, used by ~/.local/bin/qs-pick (clipboard, emoji, window
// switcher). qs-pick writes the lines to a file and waits on a fifo; this shows
// them, and writes the chosen line's index (or -1 for cancel) to the fifo.
// A line may carry an icon name after a \x1f character.
import QtQuick
import "fuzzy.js" as Fuzzy
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

PanelWindow {
    id: picker
    visible: false
    property string title: ""
    property string outPath: ""
    property var items: []          // { label, icon, index }
    property bool asking: false     // text-entry mode: no list, Enter returns what was typed
    property bool secret: false     // ...shown as dots
    // Live preview (qs-pick --on-highlight CMD): CMD is run with the highlighted line's
    // index each time the highlight settles on another line.
    property string liveCmd: ""
    property int startIndex: 0      // line highlighted when the list opens (qs-pick --start N)
    // Ranked search (qs-pick --rank): results are ordered by how well they match instead of
    // by their place in the list. A line is "name   keywords" (three spaces); rankWord below
    // lists the levels, and ties are settled as noted at the sort.
    property bool ranked: false
    function rankWord(w, it) {
        // 0 whole word of the name, 1 a whole keyword ("us" for a flag, "poop"), 2 start of a
        // name word, 3 inside a name word, 4 start of a keyword, 5 inside a keyword
        let best = 99
        const stem = x => x.length > 4 ? x.replace(/(ing|ed|es|e|s)$/, "") : x       // smile ~ smiling ~ smiles
        const ws = stem(w)
        for (const t of it.nameToks) {
            if (t === w || (ws.length >= 3 && stem(t) === ws)) return 0
            if (t.startsWith(w)) best = Math.min(best, 2)
            else if (t.indexOf(w) !== -1) best = Math.min(best, 3)
        }
        for (const t of it.keyToks) {
            if (t === w) return 1
            if (t.startsWith(w)) best = Math.min(best, 4)
            else if (t.indexOf(w) !== -1) best = Math.min(best, 5)
        }
        if (best < 99) return best
        return (picker.alias[w] || []).some(a => it.lower.indexOf(a) !== -1) ? 6 : -1
    }
    readonly property int liveIndex: {
        const r = visible && !asking ? results[list.currentIndex] : null
        return r ? r.index : -1
    }
    onLiveIndexChanged: if (liveCmd !== "" && liveIndex >= 0) liveDelay.restart()
    Timer {
        id: liveDelay
        interval: 70
        onTriggered: if (picker.liveCmd !== "" && picker.liveIndex >= 0)
            Quickshell.execDetached(["sh", "-c", picker.liveCmd + ' "$1"', "sh", String(picker.liveIndex)])
    }

    function open(itemsPath, out, what) {
        if (visible) {                       // a second call toggles it shut
            const same = what === title
            finish(-1)
            if (same) { Sys.run("printf '%s\\n' -1 > '" + out + "'"); return }
        }
        asking = false; secret = false; liveCmd = ""; startIndex = 0; ranked = false
        title = what; outPath = out; items = []
        query.text = ""
        file.path = ""
        file.path = itemsPath
        file.reload()
        visible = true
        query.forceActiveFocus()
    }
    function ask(out, what, hide) {
        if (visible) finish(-1)
        asking = true; secret = hide
        title = what; outPath = out; items = []
        query.text = ""
        visible = true
        query.forceActiveFocus()
    }
    function reply(payload) {                // argv, not a shell string: the text may be a password
        if (outPath !== "") Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$1" > "$2"', "sh", payload, outPath])
        outPath = ""
        liveCmd = ""
        liveDelay.stop()
        visible = false
        query.text = ""
    }
    function finish(index) { reply(asking ? "cancel" : String(index)) }

    FileView {
        id: file
        printErrors: false
        onLoaded: {
            const lines = text().split("\n")
            if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop()
            picker.items = lines.map((l, i) => {
                const cut = l.indexOf("\u001f")
                const label = (cut === -1 ? l : l.slice(0, cut)).replace(/\t/g, "  ")
                const lower = label.toLowerCase(), split = lower.indexOf("   ")
                return { label: label, icon: cut === -1 ? "" : l.slice(cut + 1), index: i, lower: lower, plain: split === -1,
                         nameToks: Fuzzy.tokens(split === -1 ? lower : lower.slice(0, split)),
                         keyToks: split === -1 ? [] : Fuzzy.tokens(lower.slice(split)) }
            })
            list.currentIndex = Math.max(0, Math.min(picker.startIndex, picker.items.length - 1))
            list.positionViewAtIndex(list.currentIndex, ListView.Contain)
        }
    }

    readonly property var results: {
        const words = query.text.trim().toLowerCase().split(/\s+/).filter(w => w !== "")
        if (words.length === 0) return items
        if (ranked) {
            const scored = []
            for (const it of items) {
                let total = 0
                for (const w of words) { const s = rankWord(w, it); if (s === -1) { total = -1; break } total += s }
                // a line with no keyword part is a plain symbol (⌣ "smile"), not an emoji: it ranks
                // just after emoji that match equally well, so "smile" leads with the smiling
                // faces while "alpha" still finds the Greek letter before a lion
                if (total !== -1) scored.push({ it: it, d: total + (it.plain ? 0.5 : 0) })
            }
            if (scored.length === 0) {                // nothing as typed: allow slips, names before keywords
                for (const it of items) {
                    let d = Fuzzy.score(words, it.nameToks)
                    if (d === -1) { d = Fuzzy.score(words, it.nameToks.concat(it.keyToks)); if (d !== -1) d += 10 }
                    if (d !== -1) scored.push({ it: it, d: d })
                }
            }
            // equal scores: when every word is a whole word of the name, the shorter name first
            // ("cat" before "grinning cat"); otherwise the list's own order, where recently used
            // and everyday emoji come first
            scored.sort((a, b) => a.d - b.d
                || (a.d === 0 ? a.it.nameToks.length - b.it.nameToks.length : 0) || a.it.index - b.it.index)
            return scored.map(s => s.it)
        }
        // every typed word must appear in the line, as typed or as one of its other names
        const has = (l, w) => l.indexOf(w) !== -1 || (picker.alias[w] || []).some(a => l.indexOf(a) !== -1)
        const hits = items.filter(it => { const l = it.label.toLowerCase(); return words.every(w => has(l, w)) })
        if (hits.length > 0) return hits
        // nothing matched as typed: allow a slip or two per word (fuzzy.js), closest lines first
        const close = []
        for (const it of items) {
            const l = it.label.toLowerCase()
            const d = Fuzzy.score(words, Fuzzy.tokens(l), w => has(l, w))
            if (d !== -1) close.push({ it: it, d: d })
        }
        close.sort((a, b) => a.d - b.d || a.it.index - b.it.index)
        return close.map(c => c.it)
    }
    // Other names people type for the same thing, so the lists (keybindings, layouts, displays,
    // screenshots...) answer to them. Each group is turned into word -> the rest of its group.
    readonly property var alias: {
        const groups = [
            ["workspace", "workspaces", "desktop"], ["monitor", "display", "screen", "output"],
            ["color", "colour"], ["center", "centre", "centered", "centred", "middle"],
            ["logout", "log out", "signout", "sign out", "exit"], ["quit", "kill", "close"],
            ["master", "main"], ["tile", "tiled", "tiling", "arrange", "layout"],
            ["spiral", "bsp", "fibonacci", "dwindle"], ["paper", "niri", "scrolling", "scroll"],
            ["max", "maximise", "maximize", "monocle"], ["screenshot", "capture", "prtsc", "print"],
            ["screencast", "record", "recording", "video"], ["area", "selection", "region"],
            ["duplicate", "clone", "mirror"], ["present", "presenting", "projector", "beamer"],
            ["external", "second screen", "extend"], ["sound", "audio", "volume"], ["mic", "microphone"],
            ["emoji", "emoticon", "smiley", "symbol"], ["copy", "clipboard", "paste"],
            ["apps", "applications", "launcher", "run", "start"], ["settings", "control panel", "preferences"],
            ["theme", "dark", "light", "appearance"], ["background", "wallpaper"], ["lock", "lock screen"],
            ["left", "←"], ["right", "→"], ["up", "↑"], ["down", "↓"], ["arrow", "arrows", "←", "→", "↑", "↓"],
            ["enter", "return"], ["win", "windows", "meta", "super"], ["float", "floating"],
            ["switch", "switcher", "alt-tab", "alt tab"], ["shortcuts", "keybindings", "keys", "hotkeys"],
            ["bigger", "larger", "wider", "taller", "resize"], ["smaller", "narrower", "shorter", "resize"],
            ["group", "tab", "tabs", "tabbed", "stack"], ["suspend", "sleep"], ["poweroff", "shutdown", "shut down", "power off"],
        ]
        const m = {}
        for (const g of groups) for (const w of g) m[w] = (m[w] || []).concat(g.filter(o => o !== w))
        return m
    }

    screen: {
        const m = Hyprland.focusedMonitor
        return Quickshell.screens.find(s => m && s.name === m.name) || Quickshell.screens[0]
    }
    color: "transparent"
    implicitWidth: Math.min(820, screen ? screen.width - 80 : 820)
    implicitHeight: asking ? 62 : 470
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-launcher"     // same blur rule as the launcher
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    HyprlandFocusGrab {
        windows: [picker]
        active: picker.visible
        onCleared: picker.finish(-1)
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
                    Keys.onEscapePressed: picker.finish(-1)
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onTabPressed: list.incrementCurrentIndex()
                    Keys.onBacktabPressed: list.decrementCurrentIndex()
                    function accept() {
                        if (picker.asking) { picker.reply("ok:" + query.text); return }
                        const r = picker.results[list.currentIndex]; picker.finish(r ? r.index : -1)
                    }
                    echoMode: picker.secret ? TextInput.Password : TextInput.Normal
                    Keys.onReturnPressed: accept()
                    Keys.onEnterPressed: accept()
                    Text { visible: query.text === ""; text: picker.title; color: Theme.faint; font: query.font }
                }
                Caption { visible: !picker.asking; text: picker.results.length + (picker.results.length === 1 ? " item" : " items") }
            }
            Rectangle { visible: !picker.asking; Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }

            ListView {
                id: list
                visible: !picker.asking
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: picker.results
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                keyNavigationWraps: true          // Down on the last row goes to the first, Up on the first to the last
                delegate: Rectangle {
                    id: item
                    required property var modelData
                    required property int index
                    readonly property bool sel: ListView.isCurrentItem
                    width: list.width
                    height: 34
                    radius: 8
                    color: sel ? Theme.accentBg : "transparent"
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 10
                        IconImage {
                            visible: item.modelData.icon !== ""
                            implicitSize: 22
                            source: item.modelData.icon === "" ? "" : Quickshell.iconPath(item.modelData.icon, true)
                        }
                        Text {
                            Layout.fillWidth: true
                            text: item.modelData.label
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: item.sel ? Theme.accentInk : Theme.fg
                            font { family: Theme.font; pixelSize: 14 }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: list.currentIndex = item.index
                        onClicked: picker.finish(item.modelData.index)
                    }
                }
            }
        }
    }
}
