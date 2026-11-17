// Screen-share picker for xdg-desktop-portal-hyprland, used by ~/.local/bin/qs-share-pick
// (xdph runs it as screencopy:custom_picker_binary when an app asks to share the screen).
// qs-share-pick writes the parsed lists as JSON and waits on a fifo:
//   qs ipc call sharepick open LISTFILE FIFO
// This shows SharePickView.qml on the focused screen and writes the [SELECTION] line, or
// "cancel", to the fifo. Thumbnails capture only while it is open.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: pick
    visible: false
    property string outPath: ""

    function open(listPath, out) {
        if (visible) reply("cancel")             // an older request is still open: let it go
        outPath = out
        Hyprland.refreshToplevels()
        file.path = ""
        file.path = listPath
        file.reload()
    }
    function reply(line) {
        if (outPath !== "") Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$1" > "$2"', "sh", line, outPath])
        outPath = ""
        visible = false
    }

    FileView {
        id: file
        printErrors: false
        onLoaded: {
            let lists = null
            try { lists = JSON.parse(text()) } catch (e) {}
            if (!lists) { pick.reply("cancel"); return }
            card.lists = lists
            pick.visible = true
            keys.forceActiveFocus()
        }
        onLoadFailed: pick.reply("cancel")
    }

    screen: {
        const m = Hyprland.focusedMonitor
        return Quickshell.screens.find(s => m && s.name === m.name) || Quickshell.screens[0]
    }
    color: Theme.dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(1, 1, 1, 0.45)
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-sharepick"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    MouseArea { anchors.fill: parent; onClicked: pick.reply("cancel") }
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => { event.accepted = card.handleKey(event.key, event.modifiers) }
        SharePickView {
            id: card
            anchors.centerIn: parent
            width: Math.min(parent.width - 80, implicitWidth)
            height: Math.min(parent.height - 80, implicitHeight)
            live: pick.visible
            toplevels: Hyprland.toplevels.values
            onChosen: line => pick.reply(line)
            onCancelled: pick.reply("cancel")
            MouseArea { anchors.fill: parent; z: -1 }      // clicks on the card do not close it
        }
    }
}
