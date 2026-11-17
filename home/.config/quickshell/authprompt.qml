// Polkit agent: `qs -p ~/.config/quickshell/authprompt.qml`. The password prompt for pkexec,
// mounting, package installs and systemd actions, drawn in the shell's style (AuthPrompt.qml,
// AuthView.qml) instead of by hyprpolkitagent.
//
// A separate Quickshell instance from the main shell (shell.qml), sharing this folder for
// Theme.qml, so a reload or crash of the main shell can never drop a prompt in progress. It
// does not reload when files change. Started by ~/.local/bin/polkit-agent-start (as the user
// unit qs-polkit.service, whose OnFailure= starts hyprpolkitagent if this ever fails), which
// waits for "registered" in $XDG_RUNTIME_DIR/qs-polkit.state and falls back to hyprpolkitagent
// otherwise. Only one polkit agent can be registered per session.
//
// Never test this file against the live session; tests: ~/.local/bin/auth-test (stand-in flow).
import QtQuick
import Quickshell
import Quickshell.Services.Polkit

ShellRoot {
    settings.watchFiles: false
    PolkitAgent { id: agent }
    AuthPrompt { agent: agent }
}
