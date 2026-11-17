// Settings (Super+comma): one window over the settings that already exist. Every row reads and
// writes the owner's own properties, functions, state files and IPC (the inventory is in the
// pages: Settings<Page>.qml); nothing here keeps a copy. Pages: SettingsAppearance, SettingsBar,
// SettingsNotifications, SettingsQuiet, SettingsSaver, SettingsLecture, SettingsRecording,
// SettingsPet, SettingsLauncher, SettingsPower, SettingsHealth, SettingsSession, SettingsFocus,
// SettingsAbout. Rows: SettingsSwitch / Choice / Stepper / Slider / Text / Chips / Button / Info
// (all SettingsRow), grouped in SettingsCard; files owned by features that may not be loaded go
// through JsonFile.qml.
//   qs ipc call settings toggle | open PAGE | close        (PAGE: appearance, bar, notifications, ...)
// Keys: Up/Down pick a page, Tab goes into it (Tab / Shift+Tab between rows; Space or Enter
// flips or presses, Left/Right steps a choice or number), / searches every page by name
// (Up/Down and Enter in the results), Esc clears the search, else closes.
// Nothing here exists while it is closed (the content is a Loader), so nothing runs.
// Hooks set by shell.qml: island, launcherView (launcher.view), cursorFind, dropPreview.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: settings
    visible: false
    property string page: "appearance"
    property var identify: null             // DisplaysIdentify in shell.qml (Settings > Displays, "Identify")
    property var island: null
    property var launcherView: null
    property var cursorFind: null
    property var dropPreview: null

    readonly property var pages: [
        { id: "appearance", title: "Appearance", glyph: "󰏘" },
        { id: "bar", title: "Bar and island", glyph: "󰕮" },
        { id: "notifications", title: "Notifications", glyph: "󰂚" },
        { id: "quiet", title: "Quiet hours", glyph: "󰖔" },
        { id: "clock", title: "Clocks", glyph: "\uF017" },
        { id: "saver", title: "Screensaver and idle", glyph: "󰍹" },
        { id: "lecture", title: "Lecture tools", glyph: "󰐨" },
        { id: "recording", title: "Recording and camera", glyph: "󰕧" },
        { id: "pet", title: "Pet", glyph: "󰏩" },
        { id: "launcher", title: "Launcher", glyph: "󰑣" },
        { id: "power", title: "Power", glyph: "󰁹" },
        { id: "displays", title: "Displays", glyph: "\uDB80\uDF7A" },
        { id: "input", title: "Input", glyph: "\uDB80\uDF0C" },
        { id: "health", title: "Health", glyph: "󰗶" },
        { id: "session", title: "Session", glyph: "󰦛" },
        { id: "focus", title: "Focus profiles", glyph: "󰗝" },
        { id: "about", title: "About", glyph: "󰋼" }
    ]
    readonly property int pageIndex: Math.max(0, pages.findIndex(p => p.id === page))
    function toggle() { visible = !visible }
    function open(p) {
        const id = String(p || "").toLowerCase()
        const hit = pages.find(x => x.id === id || x.title.toLowerCase().startsWith(id))
        if (id !== "" && hit) page = hit.id
        visible = true
    }
    function close() { visible = false }
    readonly property Item body: loader.item

    screen: {
        const m = Hyprland.focusedMonitor
        return Quickshell.screens.find(s => m && s.name === m.name) || Quickshell.screens[0]
    }
    color: Theme.dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(1, 1, 1, 0.35)
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-settings"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    MouseArea { anchors.fill: parent; onClicked: settings.visible = false }
    Loader {
        id: loader
        active: settings.visible
        anchors.centerIn: parent
        width: Math.min(980, settings.width - 32)
        height: Math.min(Math.max(740, settings.height * 0.6), settings.height - 48)     // taller on a portrait screen
        sourceComponent: SettingsBody { win: settings }
        onLoaded: item.start()
    }
}
