// Screenshot editor (Print; `qs ipc call shot edit`, run by `screenshot edit`).
// Freezes every screen: one overlay per screen showing a still frame of that screen
// (ScreencopyView, live: false), shown only once the frame has arrived, so the overlay is
// never in its own picture. Drag a box on any screen (ShotEditor.qml), annotate it, then
//   Enter / Save    the box at the screen's own resolution to ~/Pictures/Screenshots and the
//                   clipboard (`screenshot done FILE`: copy, shutter sound, notification)
//   Ctrl+C          clipboard only (`screenshot done --copy FILE`, the file is removed)
//   Esc             cancel
// The windows exist only while a shot is in progress.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "shot.js" as S

Scope {
    id: shot
    property bool active: false
    property string owner: ""           // the screen holding the box
    property var editors: ({})          // screen name -> ShotEditor
    property bool saving: false

    function edit() {
        if (active) return
        Hyprland.refreshToplevels()
        owner = ""; editors = ({}); saving = false
        active = true
    }
    function cancel() { active = false }

    function claim(name) {
        if (owner === name) return
        owner = name
        for (const n in editors) if (n !== name && editors[n]) editors[n].reset()
    }
    // the editor that keys act on: the box's screen, else the one under the pointer, else the focused one
    function target(from) {
        if (owner !== "" && editors[owner]) return editors[owner]
        for (const n in editors) if (editors[n] && editors[n].box.hovered) return editors[n]
        return from
    }
    function key(event, from) {
        const ed = target(from)
        event.accepted = ed ? ed.handleKey(event.key, event.modifiers) : false
    }

    function finish(how, ed) {
        if (saving) return
        if (how === "cancel") { active = false; return }
        saving = true
        const stamp = S.stamp(new Date())
        const runDir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
        const file = runDir + "/qs-shot-" + stamp + ".png"
        ed.exportTo(file, ok => {
            active = false
            saving = false
            // the script moves it into ~/Pictures/Screenshots (same name), copies, plays the shutter and
            // notifies; with no file there (ok false) it sends the usual "Screenshot failed"
            Sys.launch(how === "copy" ? [Sys.bin + "screenshot", "done", "--copy", file] : [Sys.bin + "screenshot", "done", file])
        })
    }

    Variants {
        model: shot.active ? Quickshell.screens : []

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property bool ready: cap.hasContent
            readonly property bool focusedMon: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name === modelData.name : modelData === Quickshell.screens[0]
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qs-shot"
            // the keyboard goes to the box's screen (it may need to type a label), else the focused one
            WlrLayershell.keyboardFocus: (shot.owner === "" ? focusedMon : shot.owner === modelData.name)
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: ready ? null : empty           // see-through and click-through until the frame is in
            Region { id: empty }

            Item {      // keys reach here from the editor and its label entry
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => shot.key(event, ed)
                ShotEditor {
                    id: ed
                    anchors.fill: parent
                    ready: win.ready      // the frame is always drawn (so it captures); the rest waits for it
                    frameScale: cap.sourceSize.width > 0
                        ? Math.max(cap.sourceSize.width, cap.sourceSize.height) / Math.max(win.width, win.height) : 1
                    windows: S.windowRects(Hyprland.toplevels.values, win.modelData.name, win.modelData.x, win.modelData.y)
                    onClaimed: shot.claim(win.modelData.name)
                    onRequestFinish: how => shot.finish(how, ed)
                    Component.onCompleted: { const e = shot.editors; e[win.modelData.name] = ed; shot.editors = e }

                    ScreencopyView {
                        id: cap
                        anchors.fill: parent
                        captureSource: win.modelData
                        live: false
                        paintCursor: false
                    }
                }
            }
            onReadyChanged: if (ready) ed.keyFocus()
        }
    }
}
