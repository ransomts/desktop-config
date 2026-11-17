// Settings > Displays: arrange the screens (drag on the map), and each one's resolution, scale
// and rotation; Apply tries it for 15 s (DisplaysConfirm), Save writes it for the next login.
// Everything goes through ~/.local/bin/display-layout (current / validate / apply / keep /
// revert / save); this page only does geometry (displays.js) and never talks to Hyprland.
// Screens that are off or mirroring are listed, never changed. The saved layout
// (~/.config/shell/displays.json, read through JsonFile) gives the primary screen.
// Hooks (optional): win.identify.flash(list) (DisplaysIdentify.qml in shell.qml), else
// win.island.say(...) for Identify.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "displays.js" as Geo

SettingsPage {
    id: pg
    pageId: "displays"
    title: "Displays"
    intro: "Drag the screens to arrange them. Apply tries a layout for 15 seconds and goes back by itself unless you keep it; Save makes it the layout at the next login."

    readonly property string tool: Sys.bin + "display-layout"
    readonly property string editPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/display-layout-edit.json"
    property var live: []                   // every screen display-layout reports
    property var mons: []                   // edited copies of the ones that can be arranged
    property string primary: ""
    property int sel: 0
    property bool loaded: false
    property string loadError: ""
    property bool presenting: false
    property bool pendingTrial: false       // a trial left running from before (the shell restarted)
    property var errors: []
    property var warnings: []
    property string note: ""
    property bool noteBad: false
    property bool keptUnsaved: false
    readonly property bool busy: act.running
    readonly property bool counting: confirm.visible
    readonly property var arrangeable: live.filter(m => !m.disabled && !m.mirrorOf)
    readonly property var others: live.filter(m => m.disabled || m.mirrorOf)
    readonly property var cur: mons[sel] || null
    readonly property var liveCur: cur ? arrangeable.find(m => m.description === cur.description) || null : null

    JsonFile {
        id: saved
        path: Quickshell.env("DISPLAY_LAYOUT_SAVED") || Quickshell.env("HOME") + "/.config/shell/displays.json"
        defaults: ({ monitors: [] })
        watch: pg.shown
    }
    readonly property alias savedFile: saved
    readonly property string savedPrimary: saved.values.primary || ""

    // ---- geometry ----
    function sizeOf(m) {
        const p = /^(\d+)x(\d+)/.exec(m.mode || "") || [0, 0, 0]
        let w = Number(p[1]), h = Number(p[2])
        if ((m.transform || 0) % 2 === 1) { const t = w; w = h; h = t }
        const s = Number(m.scale) || 1
        return { w: Math.round(w / s), h: Math.round(h / s) }
    }
    function rectsOf(list) { return list.map(m => { const z = sizeOf(m); return { x: m.x, y: m.y, w: z.w, h: z.h } }) }
    function sameAs(a, b) { return a && b && a.x === b.x && a.y === b.y && a.mode === b.mode && Math.abs(a.scale - b.scale) < 1e-4 && a.transform === b.transform }
    readonly property int changedCount: mons.filter(m => !sameAs(m, arrangeable.find(l => l.description === m.description))).length
    readonly property bool dirty: changedCount > 0
    readonly property bool savedDiffers: {
        const list = Array.isArray(saved.values.monitors) ? saved.values.monitors : []
        return arrangeable.some(l => !sameAs(l, list.find(s => s.description === l.description))) || (primary !== "" && primary !== savedPrimary)
    }
    readonly property var mapModel: mons.map(m => {
        const z = sizeOf(m), l = arrangeable.find(x => x.description === m.description) || {}
        return { label: m.label, name: m.name, x: m.x, y: m.y, w: z.w, h: z.h, transform: m.transform,
                 focused: l.focused === true, primary: m.description === primary,
                 sub: z.w + " × " + z.h + "  ·  " + m.name }
    })

    // ---- loading ----
    function refresh() { if (!cur_.running) cur_.running = true }
    function resetEdits() {
        const keepDesc = cur ? cur.description : ""
        mons = arrangeable.map(m => ({ description: m.description, name: m.name, label: m.label, output: m.output, mode: m.mode,
                                       modes: m.modes, scales: m.scales, x: m.x, y: m.y, scale: m.scale, transform: m.transform }))
        let i = mons.findIndex(m => m.description === keepDesc)
        if (i < 0) i = Math.max(0, arrangeable.findIndex(m => m.focused))
        sel = Math.min(i, Math.max(0, mons.length - 1))
        if (primary === "" || !live.some(m => m.description === primary))
            primary = savedPrimary !== "" && live.some(m => m.description === savedPrimary) ? savedPrimary
                    : (live.find(m => m.name.startsWith("eDP")) || live[0] || { description: "" }).description
        errors = []; warnings = []
    }
    Process {
        id: cur_
        command: Sys.clean.concat([pg.tool, "current"])
        stdout: StdioCollector {
            onStreamFinished: {
                let o = null
                try { o = JSON.parse(text) } catch (e) { o = null }
                if (o && Array.isArray(o.monitors)) {
                    pg.live = o.monitors; pg.presenting = o.presenting === true; pg.pendingTrial = o.pending === true && !pg.counting
                    pg.loadError = ""; pg.resetEdits()
                } else pg.loadError = o && o.error ? o.error : "display-layout gave nothing (is Hyprland running?)"
                pg.loaded = true
            }
        }
    }
    onShownChanged: if (shown && !counting) { note = ""; refresh() }

    // ---- edits ----
    function edit(i, patch) {
        if (counting || i < 0 || i >= mons.length) return
        let next = mons.map((m, k) => k === i ? Object.assign({}, m, patch) : m)
        if (patch.mode !== undefined || patch.scale !== undefined || patch.transform !== undefined) {
            const fit = Geo.refit(rectsOf(next), i)
            next = next.map((m, k) => (fit[k].x === m.x && fit[k].y === m.y) ? m : Object.assign({}, m, { x: fit[k].x, y: fit[k].y }))
        }
        mons = next
        note = ""
        checkSoon.restart()
    }
    function setMode(i, mode) {
        const m = mons[i], ok = (m.scales || {})[mode] || [1]
        let s = m.scale
        if (ok.indexOf(s) < 0) s = ok.reduce((a, b) => Math.abs(b - m.scale) < Math.abs(a - m.scale) ? b : a, ok[0])
        edit(i, { mode: mode, scale: s })
    }
    function moveTo(i, x, y) { edit(i, { x: Math.round(x), y: Math.round(y) }) }
    function layout() {
        return { primary: primary, monitors: mons.map(m => ({ description: m.description, output: m.output, label: m.label, mode: m.mode,
                                                              x: m.x, y: m.y, scale: m.scale, transform: m.transform })) }
    }
    FileView { id: editFile; path: pg.editPath; blockWrites: true; printErrors: false }
    function writeEdit() { editFile.setText(JSON.stringify(layout(), null, 1) + "\n") }
    Timer { id: checkSoon; interval: 250; onTriggered: { if (!pg.dirty) { pg.errors = []; pg.warnings = []; return } pg.writeEdit(); check.running = true } }
    Process {
        id: check
        command: Sys.clean.concat([pg.tool, "validate", pg.editPath])
        stdout: StdioCollector {
            onStreamFinished: {
                let o = null
                try { o = JSON.parse(text) } catch (e) { o = null }
                pg.errors = o ? (o.errors || (o.error ? [o.error] : [])) : ["display-layout validate gave nothing"]
                pg.warnings = o && o.warnings ? o.warnings : []
            }
        }
    }

    // ---- actions (one at a time) ----
    Process {
        id: act
        property var then: null
        stdout: StdioCollector {
            onStreamFinished: {
                let o = null
                try { o = JSON.parse(text) } catch (e) { o = { ok: false, error: "display-layout said: " + text.trim().slice(0, 200) } }
                const f = act.then; act.then = null
                if (f) f(o || { ok: false, error: "no answer" })
            }
        }
    }
    function run(args, then) {
        if (act.running) return false
        act.then = then
        act.command = Sys.clean.concat([tool].concat(args))
        act.running = true
        return true
    }
    function say(text, bad) { note = text; noteBad = bad === true }
    readonly property bool canApply: dirty && errors.length === 0 && !checkSoon.running && !check.running && !busy && !presenting && !counting && loaded
    function apply() {
        if (!canApply) return
        writeEdit()
        run(["apply", editPath], o => {
            if (!o.ok) { say(o.error || "refused", true); refresh(); return }
            if (!o.sent || o.sent.length === 0) { say("Nothing to change."); refresh(); return }
            pendingTrial = false
            const w = pg.Window.window
            confirm.start(w ? w.contentItem : pg)
            refresh()
        })
    }
    function keep() {
        run(["keep"], o => { keptUnsaved = true; pendingTrial = false; say(o.ok ? "Kept. Save it to have it after the next login, too." : (o.error || "keep failed"), !o.ok); refresh() })
    }
    function revert() {
        if (!run(["revert"], o => { pendingTrial = false; say(o.ok ? "Back to the layout from before." : (o.error || "revert failed"), !o.ok); refresh() }))
            Quickshell.execDetached(Sys.clean.concat([tool, "revert"]))     // busy: never leave a trial running
    }
    readonly property bool canSave: !dirty && !counting && !busy && loaded && mons.length > 0 && (keptUnsaved || savedDiffers)
    function save() {
        if (!canSave) return
        writeEdit()
        run(["save", editPath], o => {
            if (o.ok) { keptUnsaved = false; saved.reload(); say("Saved to ~/.config/hypr/monitors.lua (checked by Hyprland) and displays.json.") }
            else say(o.error || "save failed", true)
        })
    }
    function identify() {
        const list = live.map(m => ({ name: m.name, label: m.label, description: m.description, off: m.disabled }))
        if (win && win.identify) win.identify.flash(list)
        else if (win && win.island) win.island.say({ kind: "displays", glyph: "󰍹", title: "Screens", ms: 6000,
                                                      sub: list.filter(m => !m.off).map(m => m.name + " " + m.label).join("  ·  ") })
        else say("Identify needs the shell (no identify or island hook).", true)
    }
    Component.onDestruction: if (counting) Quickshell.execDetached(Sys.clean.concat([tool, "revert"]))   // window closed mid-trial

    DisplaysConfirm {
        id: confirm
        onKept: pg.keep()
        onReverted: pg.revert()
    }
    readonly property alias confirmDialog: confirm

    // ---- the page ----
    SettingsCard {
        title: "Arrangement"
        note: pg.loaded && pg.loadError === "" ? pg.live.length + (pg.live.length === 1 ? " screen" : " screens") : ""
        SettingsRow {
            id: arrange
            label: pg.mons.length > 1 ? "Drag a screen to move it" : "One screen: nothing to arrange"
            sub: pg.mons.length > 1 ? "Edges snap together; screens never overlap and always touch. Arrow keys nudge the picked one (Shift: 100 px), Space picks the next." : ""
            keywords: "monitor display arrange position layout drag screen"
            below: true
            onActivated: if (pg.mons.length) pg.sel = (pg.sel + 1) % pg.mons.length
            onStepped: d => map.nudge(d * 10, 0)
            Keys.onLeftPressed: event => map.nudge(event.modifiers & Qt.ShiftModifier ? -100 : -10, 0)
            Keys.onRightPressed: event => map.nudge(event.modifiers & Qt.ShiftModifier ? 100 : 10, 0)
            Keys.onUpPressed: event => map.nudge(0, event.modifiers & Qt.ShiftModifier ? -100 : -10)
            Keys.onDownPressed: event => map.nudge(0, event.modifiers & Qt.ShiftModifier ? 100 : 10)
            Column {
                width: arrange.width
                spacing: 8
                DisplaysMap {
                    id: map
                    width: parent.width
                    height: Math.round(Math.max(170, Math.min(mons.length > 1 ? 320 : 240, (width - 2 * pad) * box.h / box.w + 2 * pad + 20)))
                    mons: pg.mapModel
                    sel: pg.sel
                    locked: pg.mons.length < 2 || pg.counting
                    onPicked: i => { pg.sel = i; arrange.forceActiveFocus() }
                    onMoved: (i, x, y) => pg.moveTo(i, x, y)
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    wrapMode: Text.Wrap
                    text: pg.loadError !== "" ? pg.loadError : pg.errors.join("\n")
                    color: Theme.red
                    font { family: Theme.font; pixelSize: 12 }
                }
                Text {
                    width: parent.width
                    visible: text !== "" && pg.errors.length === 0
                    wrapMode: Text.Wrap
                    text: pg.warnings.join("\n")
                    color: Theme.warn
                    font { family: Theme.font; pixelSize: 12 }
                }
                Caption {
                    width: parent.width
                    visible: pg.others.length > 0
                    wrapMode: Text.Wrap
                    font.pixelSize: 11
                    text: pg.others.map(m => m.mirrorOf ? m.label + " (" + m.name + ") mirrors " + m.mirrorOf : m.label + " (" + m.name + ") is off").join("  ·  ")
                          + ": left as it is. Super+P for mirror, projector and laptop-screen modes."
                }
            }
        }
    }

    SettingsCard {
        title: pg.cur ? pg.cur.label : "Screen"
        note: pg.cur ? pg.cur.name + "  ·  " + pg.cur.description : ""
        visible: pg.cur !== null
        DisplaysPicker {
            label: "Resolution"
            valueWidth: 220
            keywords: "monitor display mode resolution refresh hz"
            values: pg.cur ? pg.cur.modes : []
            labels: values.map(s => { const p = /^(\d+)x(\d+)@([0-9.]+)/.exec(s); return p ? p[1] + "×" + p[2] + " @ " + Number(p[3]).toFixed(2) + " Hz" : s })
            value: pg.cur ? pg.cur.mode : ""
            enabled: !pg.counting
            onEdited: v => pg.setMode(pg.sel, v)
        }
        DisplaysPicker {
            label: "Scale"
            valueWidth: 220
            sub: "Only scales that give whole pixels at this resolution"
            keywords: "monitor display scale zoom hidpi size"
            values: pg.cur ? ((pg.cur.scales || {})[pg.cur.mode] || [pg.cur.scale]) : []
            labels: values.map(s => { const z = pg.sizeOf({ mode: pg.cur.mode, scale: s, transform: 0 }); return (Math.round(s * 1000) / 1000) + "×  ·  " + z.w + "×" + z.h })
            value: pg.cur ? pg.cur.scale : 1
            enabled: !pg.counting
            onEdited: v => pg.edit(pg.sel, { scale: v })
        }
        SettingsChoice {
            label: "Rotation"
            keywords: "monitor display rotate portrait transform"
            options: [[0, "Normal"], [1, "90°"], [2, "180°"], [3, "270°"]]
            value: pg.cur ? pg.cur.transform : 0
            enabled: !pg.counting
            onEdited: v => pg.edit(pg.sel, { transform: v })
        }
        SettingsInfo {
            label: "Position"
            keywords: "monitor display position coordinates"
            value: pg.cur ? pg.cur.x + ", " + pg.cur.y + (pg.liveCur && (pg.liveCur.x !== pg.cur.x || pg.liveCur.y !== pg.cur.y) ? "   (now " + pg.liveCur.x + ", " + pg.liveCur.y + ")" : "") : ""
        }
        SettingsSwitch {
            label: "Primary screen"
            sub: "Marked ★ on the map; saved with the layout as DisplayLayout.primary in monitors.lua"
            keywords: "monitor display primary main"
            checked: pg.cur !== null && pg.primary === pg.cur.description
            onEdited: on => { if (on && pg.cur) pg.primary = pg.cur.description }
        }
    }

    SettingsCard {
        title: "Layout"
        SettingsButton {
            label: "Apply"
            sub: pg.presenting ? "Not while presenting (Super+P → Extend ends it)"
                 : pg.errors.length ? "Fix the layout first"
                 : pg.dirty ? pg.changedCount + (pg.changedCount === 1 ? " screen changes" : " screens change") + ". Try it for 15 seconds; it goes back by itself unless you keep it"
                 : "Nothing changed yet"
            keywords: "monitor display apply try test"
            text: "Apply"
            lit: pg.canApply
            enabled: pg.canApply
            onClicked: pg.apply()
        }
        SettingsButton {
            label: "Keep the trial layout"
            sub: "A layout is still on trial from before; it goes back by itself in a few seconds"
            visible: pg.pendingTrial && !pg.counting
            text: "Keep"
            onClicked: pg.keep()
        }
        SettingsButton {
            label: "Undo my changes"
            sub: "Back to the screens as they are now"
            keywords: "monitor display reset undo"
            text: "Reset"
            enabled: (pg.dirty || pg.pendingTrial) && !pg.busy && !pg.counting
            onClicked: { if (pg.pendingTrial) pg.revert(); else { pg.resetEdits(); pg.say("") } }
        }
        SettingsButton {
            label: "Save"
            sub: pg.dirty ? "Apply and keep the layout first: only a layout you have seen working is saved"
                 : pg.canSave ? ((saved.values.monitors || []).length ? "" : "Nothing saved yet. ") + "Writes ~/.config/hypr/monitors.lua, used from the next login"
                 : "The saved layout is the one you see"
            keywords: "monitor display save login permanent"
            text: "Save"
            lit: pg.canSave
            enabled: pg.canSave
            onClicked: pg.save()
        }
        SettingsButton {
            label: "Identify"
            sub: "Shows each screen's name on it for a few seconds"
            keywords: "monitor display identify which name"
            text: "Identify"
            enabled: pg.live.length > 0
            onClicked: pg.identify()
        }
        Text {
            Layout.fillWidth: true
            Layout.topMargin: 4
            visible: pg.note !== ""
            wrapMode: Text.Wrap
            text: pg.note
            color: pg.noteBad ? Theme.red : Theme.ok
            font { family: Theme.font; pixelSize: 12 }
        }
    }
}
