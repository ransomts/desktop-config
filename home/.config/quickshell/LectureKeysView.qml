// What the key display shows (LectureKeys.qml): the last few keys and chords as pills
// along the bottom, each fading 2.5 s after it was last pressed. Plain typing gathers
// into one pill of characters; a chord pressed again counts up ("Ctrl + Z  ×3").
// push() takes lines from ~/.local/bin/lecture-keys ("mods<TAB>key"). Nothing is kept
// beyond the pills on screen.
import QtQuick

Item {
    id: view
    readonly property int life: 2500        // ms a pill stays after its last key
    readonly property int maxPills: 5
    readonly property int maxTyped: 24      // characters kept in a typing pill (the newest)
    property alias pills: pills
    property string problem: ""             // shown instead of pills, e.g. no keyboard access

    ListModel { id: pills }                 // { text, typing, count, born }

    function push(line) {
        if (line === "#nokbd") {
            problem = "Key display: no keyboard can be read (see lecture-keys --list)"
            return
        }
        const k = Lecture.parseKeyLine(line)
        if (!k) return
        const now = Lecture.now()
        const last = pills.count ? pills.get(pills.count - 1) : null
        const fresh = last && now - last.born < life
        const ch = k.mods.length ? "" : k.key.length === 1 ? k.key : k.key === "Space" ? " " : k.key === "Backspace" ? "⌫" : ""
        if (ch !== "") {
            if (fresh && last.typing) {
                const t = (last.text + ch)
                pills.setProperty(pills.count - 1, "text", t.length > maxTyped ? "…" + t.slice(t.length - maxTyped + 1) : t)
                pills.setProperty(pills.count - 1, "born", now)
            } else add(ch, true, now)
            return
        }
        const text = k.mods.concat([k.key]).join(" + ")
        if (fresh && !last.typing && last.text === text) {
            pills.setProperty(pills.count - 1, "count", last.count + 1)
            pills.setProperty(pills.count - 1, "born", now)
        } else add(text, false, now)
    }
    function add(text, typing, now) {
        pills.append({ text: text, typing: typing, count: 1, born: now })
        while (pills.count > maxPills) pills.remove(0)
    }
    function expire() {                     // drop pills past their time
        const now = Lecture.now()
        for (let i = pills.count - 1; i >= 0; i--)
            if (now - pills.get(i).born >= life) pills.remove(i)
    }
    function reset() { pills.clear(); problem = "" }
    // the pills' texts as one string (tests)
    function shown() { const a = []; for (let i = 0; i < pills.count; i++) { const p = pills.get(i); a.push(p.text + (p.count > 1 ? " ×" + p.count : "")) } return a.join(" | ") }

    Timer {                                 // only while something is on screen
        interval: 250; repeat: true
        running: pills.count > 0
        onTriggered: view.expire()
    }

    Row {
        id: row
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 70 }
        spacing: 10
        Repeater {
            model: view.problem === "" ? pills : 0
            Rectangle {
                id: pill
                required property string text
                required property bool typing
                required property int count
                implicitWidth: label.implicitWidth + 32
                implicitHeight: 52
                radius: 14
                color: Theme.panelBg
                border.width: 2
                border.color: typing ? Theme.line : Theme.accentBg
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: pill.text + (pill.count > 1 ? "  ×" + pill.count : "")
                    textFormat: Text.PlainText
                    color: Theme.fg
                    font { family: Theme.font; pixelSize: 26; bold: !pill.typing }
                }
            }
        }
        Rectangle {
            visible: view.problem !== ""
            implicitWidth: problemText.implicitWidth + 32
            implicitHeight: 44
            radius: 12
            color: Theme.panelBg
            border.width: 2
            border.color: Theme.warn
            Text {
                id: problemText
                anchors.centerIn: parent
                text: view.problem
                color: Theme.fg
                font { family: Theme.font; pixelSize: 16 }
            }
        }
    }
}
