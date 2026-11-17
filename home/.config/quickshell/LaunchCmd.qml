// One command at a time for the launcher's modes (qalc, cliphist, fd, hyprctl): run()
// stops the previous run first, so a slow answer to an old query never lands after a new
// one; a run that takes longer than `timeout` ms is stopped. finished(out, ok) gives the
// whole stdout. Nothing runs until run() is called, and stop() ends it.
// Tests set `fake` to function(argv) -> stdout string (or null for a failed run); then no
// process is started at all.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: cmd
    property var fake: null
    property int timeout: 2000
    property bool busy: false
    signal finished(string out, bool ok)

    property int gen: 0
    property var proc: null
    function run(argv) {
        stop()
        const g = gen
        busy = true
        if (fake) {
            const f = fake
            Qt.callLater(() => {
                if (g !== cmd.gen) return
                const r = f(argv)
                cmd.busy = false
                cmd.finished(r === null || r === undefined ? "" : String(r), r !== null && r !== undefined)
            })
            return
        }
        proc = procC.createObject(cmd, { command: Sys.clean.concat(argv), gen: g })
        proc.running = true
        if (timeout > 0) killer.restart()
    }
    function stop() {
        gen++
        busy = false
        killer.stop()
        if (proc) {
            const p = proc
            proc = null
            p.running = false           // kills it; its late signals are ignored (old gen)
            p.destroy(2000)
        }
    }
    function settle(p) {
        if (!p.outDone || !p.ended) return
        if (p.gen !== gen) return
        killer.stop()
        busy = false
        proc = null
        const out = p.out, ok = p.code === 0
        p.destroy(100)
        finished(out, ok)
    }

    property Timer killer: Timer { interval: cmd.timeout; onTriggered: cmd.stop() }
    property Component procC: Component {
        Process {
            id: p
            property int gen: 0
            property string out: ""
            property bool outDone: false
            property bool ended: false
            property int code: -1
            stdout: StdioCollector { onStreamFinished: { p.out = text; p.outDone = true; cmd.settle(p) } }
            onExited: (exitCode, exitStatus) => { p.code = exitCode; p.ended = true; cmd.settle(p) }
        }
    }
}
