// Runs one of the waybar-style status scripts (they print {"text","tooltip","class"}
// as JSON) on a timer and keeps the latest answer.
import QtQuick
import Quickshell.Io

Item {
    id: src
    property string exec
    property int interval: 5000
    property bool active: true
    property string text: ""
    property string tooltip: ""
    property string cls: ""
    property var data: ({})             // the whole answer (for scripts that say more than the three)

    function refresh() { if (!proc.running) proc.running = true }

    Process {
        id: proc
        command: Sys.clean.concat(["sh", "-c", src.exec])
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim()
                if (out === "") { src.text = ""; src.tooltip = ""; src.cls = ""; src.data = ({}); return }
                try {
                    // plain JSON first (pretty-printed is fine); then with every newline escaped, for the
                    // scripts that put real newlines inside strings, which strict JSON forbids
                    let o
                    try { o = JSON.parse(out) } catch (e1) { o = JSON.parse(out.replace(/\n/g, "\\n")) }
                    src.text = o.text || ""
                    src.tooltip = o.tooltip || ""
                    src.cls = o.class || ""
                    src.data = o
                } catch (e) {
                    // never put a script's raw output on the bar: keep the last good answer
                    console.warn("ScriptSource: bad JSON from", src.exec, "-", out.slice(0, 200))
                }
            }
        }
    }
    Timer {
        interval: src.interval
        running: src.active
        repeat: true
        triggeredOnStart: true
        onTriggered: src.refresh()
    }
}
