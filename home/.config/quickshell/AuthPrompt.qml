// The polkit agent's window and its report to ~/.local/bin/polkit-agent-start (authprompt.qml
// gives it the PolkitAgent; the test harness gives it a stand-in).
//
// - No window at all while idle. While a request is active: one Overlay layer on the screen that
//   had focus when the request came in (namespace qs-auth), exclusive keyboard focus, AuthView.
//   Requests queue in Quickshell (agent.flow is the front one); the next appears when one ends.
// - Writes "registered" to $XDG_RUNTIME_DIR/qs-polkit.state once polkit accepted the agent.
//   If it has not after `registerMs` (another agent holds the session, polkitd unreachable),
//   writes "failed" and exits with code 3, so qs-polkit.service's OnFailure= brings back
//   hyprpolkitagent.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: prompt
    required property var agent
    property int registerMs: 5000
    property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-polkit.state"
    property var capsCmd: null                  // tests: a stand-in for the Caps Lock reader
    readonly property bool active: agent !== null && agent.isActive === true && agent.flow !== null && agent.flow !== undefined
    readonly property var window: loader.item
    property string screenName: ""

    function focusedScreen() {
        const m = Hyprland.focusedMonitor
        const s = Quickshell.screens.find(x => m && x.name === m.name) || Quickshell.screens[0]
        return s ? s.name : ""
    }
    onActiveChanged: if (active) screenName = focusedScreen()

    function report() {
        if (!agent || !agent.isRegistered) return
        giveUp.stop()
        stateView.setText("registered\n")
    }
    Connections {
        target: prompt.agent
        ignoreUnknownSignals: true
        function onIsRegisteredChanged() { prompt.report() }
    }
    Component.onCompleted: report()
    FileView { id: stateView; path: prompt.stateFile; blockWrites: true; blockLoading: false; printErrors: false }
    Timer {
        id: giveUp
        interval: prompt.registerMs
        running: true
        onTriggered: {
            if (prompt.agent && prompt.agent.isRegistered) return
            stateView.setText("failed\n")
            console.warn("authprompt: polkit did not accept this agent within " + prompt.registerMs + " ms; exiting")
            Qt.exit(3)
        }
    }

    LazyLoader {
        id: loader
        active: prompt.active
        PanelWindow {
            id: win
            property alias view: authView
            screen: Quickshell.screens.find(s => s.name === prompt.screenName) || Quickshell.screens[0]
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qs-auth"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"
            AuthView {
                id: authView
                anchors.fill: parent
                flow: prompt.agent ? prompt.agent.flow : null
                capsCmd: prompt.capsCmd || defaultCapsCmd
            }
        }
    }
}
