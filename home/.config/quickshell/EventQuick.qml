pragma Singleton
// "event Lunch with Sam tomorrow 12-1 at Esso Club" in the launcher: one row that adds it to
// the Outlook calendar. The line is read by `quick-event parse` (bin/quick-event), debounced,
// one process at a time (LaunchCmd.qml); the answer is cached in `parsed`.
//   EventQuick.rows(q, view)   the provider: [row] for a query starting "event " or "ev ", else []
//   EventQuick.parsed          the last answer (line, subject, start, end, location, human, problems)
// Providers must return at once, so a line that has no answer yet gets a "reading" row, and the
// answer makes `parsed` change: the provider read it while LaunchView.results was being
// evaluated, so the list re-evaluates by itself (no poke needed). Enter on a good row starts
// `quick-event add LINE` (which parses again and refuses on its own) and closes the launcher;
// a row with a problem shows it in the second line and Enter does nothing.
// shell.qml: launcher.view.providers = [..., q => EventQuick.rows(q, launcher.view)]
// Nothing runs until a query starts with "event " or "ev ".
import QtQuick
import Quickshell

Singleton {
    id: eq
    property var parsed: null           // the last answer, or null
    property string asked: ""           // the line the debounce is working for
    property string running: ""         // the line the process was started for
    property alias fake: cmd.fake       // tests: function(argv) -> stdout
    property int debounceMs: 150
    readonly property string glyph: "󰃭"
    readonly property string glyphWarn: "󰀦"

    // called from the provider, i.e. while a binding is being evaluated: change state later
    function want(line) {
        if (line === asked) return
        asked = line
        debounce.restart()
    }
    function row(line, view) {
        const p = parsed && parsed.line === line ? parsed : null
        if (!p) return { label: "Add event", sub: "reading...", glyph: glyph, icon: "", two: true, run: () => {} }
        const bad = p.problems && p.problems.length > 0
        const label = p.subject ? "Add event: " + p.subject : "Add event"
        if (bad) return { label: label, sub: p.problems[0], warn: true, glyph: glyphWarn, icon: "", two: true, run: () => {} }
        return { label: label, sub: p.human, warn: false, glyph: glyph, icon: "", two: true,
                 run: () => { Sys.launch([Sys.bin + "quick-event", "add", line]); if (view && view.close) view.close() } }
    }
    function rows(q, view) {
        q = String(q || "").trim()
        if (/^event$/i.test(q))
            return [{ label: "Add event", sub: "type what and when: Lunch with Sam tomorrow 12-1 at Esso Club", glyph: glyph, icon: "", two: true, run: () => {} }]
        const m = /^(?:event|ev)\s+(\S.*)$/i.exec(q)
        if (!m) return []
        const line = m[1].trim()
        if (!(parsed && parsed.line === line) && asked !== line) Qt.callLater(() => eq.want(line))
        return [row(line, view)]
    }

    Timer { id: debounce; interval: eq.debounceMs; onTriggered: { eq.running = eq.asked; cmd.run([Sys.bin + "quick-event", "parse", eq.asked]) } }
    LaunchCmd {
        id: cmd
        timeout: 5000
        onFinished: (out, ok) => {
            let r = null
            try { r = ok ? JSON.parse(out) : null } catch (e) { r = null }
            if (!r || typeof r !== "object") r = { subject: "", human: "", problems: ["Could not read that"] }
            r.line = eq.running
            eq.parsed = r
        }
    }
}
