// Tests for the polkit prompt (AuthPrompt.qml + AuthView.qml). NOT part of the shell:
// ~/.local/bin/auth-test copies the real AuthPrompt (its layer window turned into a plain
// floating window), AuthView and Theme next to this file with the stand-ins FakeAgent and
// FakeFlow (the PolkitAgent/AuthFlow API, no polkit, no D-Bus), and runs it offscreen with a
// made-up HOME (its is_dark file is how the test switches to light).
//
// Each case logs PASS or FAIL; the last line is "AUTHTEST RESULT pass N fail M". Pictures:
// $AUTH_TEST_OUT-{dark,light}-{idle,typing,error}.png and -dark-picker.png.
// The test passwords below must never appear in any output: the runner greps for them.
// Checks compare them in place and never print them.
//
// AUTH_NOREG=1: the agent never registers; AuthPrompt must write "failed" and exit with code 3.
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    readonly property bool noreg: Quickshell.env("AUTH_NOREG") === "1"
    readonly property string out: Quickshell.env("AUTH_TEST_OUT") || ""
    readonly property string right: "Hunter2-zq9"
    readonly property string wrongPw: "Wr0ng-pw-x7"
    readonly property var me: ({ id: 1000, string: Quickshell.env("USER"), displayName: "Test User", isGroup: false })
    readonly property string pkexecMsg: "Authentication is needed to run `/usr/bin/true' as the super user"

    FakeAgent { id: agent }
    Timer { interval: 100; running: !root.noreg; onTriggered: agent.isRegistered = true }
    AuthPrompt {
        id: prompt
        agent: agent
        registerMs: root.noreg ? 800 : 600000
        stateFile: Quickshell.env("AUTH_STATE")
        capsCmd: ["sh", "-c", "echo 0"]
    }
    FileView { id: stateRead; path: Quickshell.env("AUTH_STATE"); printErrors: false; blockLoading: true }
    FileView {
        id: modeFile
        path: Quickshell.env("HOME") + "/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark"
        blockWrites: true
    }

    property int passed: 0
    property int failed: 0
    function check(what, ok, detail) {
        if (ok) passed++; else failed++
        console.log("AUTHTEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
    }
    TestEvent { id: ev }

    function v() { return prompt.window ? prompt.window.view : null }
    function type(s) { for (const ch of s) ev.keyClickChar(ch, Qt.NoModifier, -1) }
    function key(k, mods) { ev.keyClick(k, mods || Qt.NoModifier, -1) }
    function find(item, name) {
        if (!item) return null
        if (item.objectName === name) return item
        for (let i = 0; i < item.children.length; i++) { const r = find(item.children[i], name); if (r) return r }
        return null
    }
    function all(item, name, acc) {
        acc = acc || []
        if (!item) return acc
        if (item.objectName === name) acc.push(item)
        for (let i = 0; i < item.children.length; i++) all(item.children[i], name, acc)
        return acc
    }
    function texts(item, acc) {
        acc = acc || []
        if (!item) return acc
        if (typeof item.text === "string" && item.visible) acc.push(item.text)
        for (let i = 0; i < item.children.length; i++) texts(item.children[i], acc)
        return acc
    }
    // does any visible text show (part of) a test password? (the answer only, never the text)
    function shows(secret) { return texts(v()).some(t => t.indexOf(secret.slice(0, 5)) >= 0) }
    function dots() { const d = find(v(), "dots"); return d && d.visible ? d.children.length - 1 : 0 }   // minus the Repeater
    function grab(name) { const w = v(); if (root.out && w) w.grabToImage(r => r.saveToFile(root.out + "-" + name + ".png")) }
    function req(extra) {
        const spec = { message: root.pkexecMsg, actionId: "org.freedesktop.policykit.exec", identities: [root.me],
                       prompts: [{ text: "Password: ", echo: false, want: root.right }] }
        for (const k in extra || {}) spec[k] = extra[k]
        agent.request(spec)
        return agent.flow
    }
    property var fl: null
    function f() { return root.fl ? root.fl : agent.last() }     // the flow, or what it came to once gone
    property var held: null
    // the length of the view's `typed` at its last change: the view may be gone right after an
    // exit (the window is destroyed with the request), so the check is that it was emptied first
    property int lastLen: -1
    function hold() {
        const w = v()
        root.held = w
        root.lastLen = w.typed.length
        w.typedChanged.connect(() => root.lastLen = w.typed.length)
    }
    function emptied() { return root.lastLen === 0 && (!root.held || root.held.typed === "") }

    // pictures: idle (empty field), typing, error; dark at the start, light at the end
    function picturesCases(mode) {
        return [
            { name: mode + ": request", run: function() { root.fl = req(); return 250 } },
            { name: mode + ": idle picture", run: function() { check(mode + " prompt up", v() !== null); grab(mode + "-idle"); return 300 } },
            { name: mode + ": typing picture", run: function() { type(root.wrongPw); grab(mode + "-typing"); return 300 } },
            { name: mode + ": submit wrong", run: function() { key(Qt.Key_Return); return 350 } },
            { name: mode + ": error picture", run: function() { check(mode + " wrong shown", v() && v().wrong); grab(mode + "-error"); return 300 } },
            { name: mode + ": done", run: function() { key(Qt.Key_Escape); return 200 } }
        ]
    }

    property var cases: [
        { name: "idle", run: function() {
            stateRead.reload()
            check("state file says registered", stateRead.text().trim() === "registered", stateRead.text())
            check("no window while idle", prompt.window === null)
            return 50
        } },
        { name: "a request arrives", run: function() {
            root.fl = req()
            check("window up while a request is active", prompt.window !== null && v() !== null)
            check("view has the flow", v() && v().flow === agent.flow)
            return 200
        } },
        { name: "what it shows", run: function() {
            const w = v()
            check("message shown", find(w, "message").text === root.pkexecMsg)
            check("action id shown", find(w, "actionId").text === "org.freedesktop.policykit.exec")
            check("identity shown", find(w, "identity").visible && find(w, "identity").text.indexOf("Test User") === 0, find(w, "identity").text)
            check("placeholder is PAM's prompt", find(w, "placeholder").text === "Password", find(w, "placeholder").text)
            check("keyboard focus on the view", w.activeFocus)
            check("caps notice off", !w.caps)
            return 50
        } },
        { name: "typing: dots only", run: function() {
            type(root.wrongPw)
            check("typed holds what was typed", v().typed === root.wrongPw)
            check("one dot per character", dots() === root.wrongPw.length, dots())
            check("no visible text shows the password", !shows(root.wrongPw))
            key(Qt.Key_A, Qt.ControlModifier)
            check("Ctrl+A adds nothing", v().typed.length === root.wrongPw.length)
            key(Qt.Key_Backspace)
            check("Backspace removes one", v().typed.length === root.wrongPw.length - 1)
            type(root.wrongPw.slice(-1))
            return 50
        } },
        { name: "submit a wrong password", run: function() {
            key(Qt.Key_Return)
            check("field cleared at once on submit", v().typed === "")
            check("Authenticating… shown", v().checking && find(v(), "placeholder").text === "Authenticating…")
            check("flow received exactly what was typed", f().answers.length === 1 && f().answers[0] === root.wrongPw)
            type("x")
            check("typing ignored while checking", v().typed === "")
            return 350
        } },
        { name: "wrong: error, refocused, retry", run: function() {
            check("wrong shown", v().wrong && find(v(), "status").text.indexOf("didn't match") >= 0, find(v(), "status").text)
            check("field empty after a failure", v().typed === "")
            check("focus back on the field", v().activeFocus)
            check("PAM asks again (new session)", f().isResponseRequired && f().sessions === 2, f().sessions)
            type(root.right)
            check("typing clears the error", !v().wrong)
            hold()
            key(Qt.Key_Enter)
            check("field cleared on submit", emptied())
            return 350
        } },
        { name: "right password: done", run: function() {
            check("flow succeeded", f().isCompleted && f().isSuccessful)
            check("flow received the right password", f().answers[1] === root.right)
            check("no flow, no window", agent.flow === null && prompt.window === null)
            return 100
        } },

        { name: "Esc cancels", run: function() {
            root.fl = req()
            return 200
        } },
        { name: "Esc cancels: check", run: function() {
            type("abc")
            hold()
            key(Qt.Key_Escape)
            check("password empty after Esc", emptied())
            check("flow cancelled", f().isCancelled && f().isCompleted && !f().isSuccessful)
            check("nothing submitted", f().answers.length === 0)
            return 150
        } },
        { name: "Cancel button", run: function() {
            check("window gone after Esc", prompt.window === null)
            root.fl = req()
            return 200
        } },
        { name: "Cancel button: check", run: function() {
            type("abc")
            hold()
            const b = find(v(), "cancel")
            ev.mouseClick(b, b.width / 2, b.height / 2, Qt.LeftButton, Qt.NoModifier, -1)
            check("password empty after Cancel click", emptied())
            check("flow cancelled by the click", f().isCancelled)
            return 150
        } },
        { name: "polkit cancels", run: function() {
            root.fl = req()
            return 200
        } },
        { name: "polkit cancels: check", run: function() {
            type("abcd")
            hold()
            agent.daemonCancel()
            check("password empty after a daemon cancel", emptied())
            check("flow cancelled from the agent", f().isCancelled)
            return 150
        } },
        { name: "two requests queue", run: function() {
            check("window gone after a daemon cancel", prompt.window === null)
            root.fl = req({ message: "first" })
            req({ message: "second", actionId: "org.freedesktop.udisks2.filesystem-mount" })
            return 200
        } },
        { name: "queue: first shown", run: function() {
            check("the first request is active", agent.flow === root.fl && agent.queue.length === 1)
            check("its message shown", find(v(), "message").text === "first")
            type(root.right); key(Qt.Key_Return)
            return 350
        } },
        { name: "queue: second follows", run: function() {
            check("first done", f().isSuccessful)
            check("second now active", agent.flow && agent.flow.message === "second" && agent.started >= 6, agent.started)
            check("prompt shows the second", v() && find(v(), "message").text === "second")
            check("password empty for the second", v() && v().typed === "" && !v().wrong)
            root.fl = agent.flow
            return 150
        } },
        { name: "queue: second answered", run: function() {
            type(root.right); key(Qt.Key_Return)
            return 350
        } },
        { name: "identity picker", run: function() {
            check("second done, idle again", f().isSuccessful && prompt.window === null)
            root.fl = req({ identities: [{ id: 0, string: "root", displayName: "root", isGroup: false },
                                         { id: 1001, string: "alice", displayName: "Alice Example", isGroup: false },
                                         root.me] })
            return 250
        } },
        { name: "identity picker: check", run: function() {
            check("starts with the user at the keyboard", f().selectedIdentity.string === "tester", f().selectedIdentity.string)
            check("the switch's spurious failure is not shown", !v().wrong)
            check("three choices", all(v(), "chip").length === 3, all(v(), "chip").length)
            check("single identity line hidden", !find(v(), "identity").visible)
            grab("dark-picker")
            type("ab")
            key(Qt.Key_Tab)
            check("Tab: next identity (wraps)", f().selectedIdentity.string === "root", f().selectedIdentity.string)
            check("password cleared on switch", v().typed === "")
            check("still no error", !v().wrong)
            const chips = all(v(), "chip")
            const alice = chips.find(c => c.modelData.string === "alice")
            ev.mouseClick(alice, 5, 5, Qt.LeftButton, Qt.NoModifier, -1)
            check("click picks alice", f().selectedIdentity.string === "alice")
            key(Qt.Key_Tab, Qt.ShiftModifier)
            check("Shift+Tab goes back", f().selectedIdentity.string === "root", f().selectedIdentity.string)
            key(Qt.Key_Backtab, Qt.ShiftModifier)
            check("Backtab goes back (wraps)", f().selectedIdentity.string === "tester", f().selectedIdentity.string)
            return 250
        } },
        { name: "identity picker: answer", run: function() {
            type(root.right); key(Qt.Key_Return)
            return 350
        } },
        { name: "info and error messages", run: function() {
            check("picker request done", f().isSuccessful)
            root.fl = req()
            f().showInfo("Place your finger on the fingerprint reader")
            return 200
        } },
        { name: "info and error: check", run: function() {
            const s = find(v(), "status")
            check("info shown", s.text === "Place your finger on the fingerprint reader")
            check("info not red", !Qt.colorEqual(s.color, Theme.red))
            f().showError("Fingerprint not recognised")
            check("error shown in red", s.text === "Fingerprint not recognised" && Qt.colorEqual(s.color, Theme.red))
            key(Qt.Key_Escape)
            return 150
        } },
        { name: "Enter before PAM asks", run: function() {
            root.fl = req({ askMs: 500 })
            return 60
        } },
        { name: "Enter before PAM asks: typed", run: function() {
            check("not asked yet", !f().isResponseRequired && find(v(), "placeholder").text === "Waiting…")
            type(root.right); key(Qt.Key_Return)
            check("held until asked", f().answers.length === 0 && v().wantSubmit)
            return 800
        } },
        { name: "Enter before PAM asks: sent", run: function() {
            check("sent once asked, and it worked", f().answers.length === 1 && f().isSuccessful)
            return 50
        } },
        { name: "second factor with a visible answer", run: function() {
            root.fl = req({ prompts: [{ text: "Password: ", echo: false, want: root.right },
                                      { text: "Verification code: ", echo: true, want: "123456" }] })
            return 200
        } },
        { name: "second factor: password", run: function() {
            type(root.right); key(Qt.Key_Return)
            return 350
        } },
        { name: "second factor: code", run: function() {
            check("asked for the code", f().isResponseRequired && find(v(), "placeholder").text === "Verification code")
            type("123456")
            check("a visible answer is shown as text", texts(v()).indexOf("123456") >= 0)
            check("not as dots", dots() === 0)
            key(Qt.Key_Return)
            return 350
        } },
        { name: "second factor: done", run: function() {
            check("both turns answered", f().isSuccessful && f().answers.length === 2)
            root.fl = req()
            return 200
        } },
        { name: "Caps Lock", run: function() {
            v().caps = true
            check("caps notice", find(v(), "status").text === "Caps Lock is on")
            type("q"); key(Qt.Key_U, Qt.ControlModifier)
            check("Ctrl+U clears", v().typed === "")
            key(Qt.Key_Escape)
            return 150
        } }
    ]
    property var allCases: picturesCases("dark").concat(cases).concat([
        { name: "switch to light", run: function() { modeFile.setText("false\n"); Theme.reload(); return 300 } },
        { name: "light: check", run: function() { check("Theme follows is_dark (light)", !Theme.dark); return 50 } }
    ]).concat(picturesCases("light"))

    property int at: 0
    Timer {
        interval: 400; running: !root.noreg
        onTriggered: {
            if (root.at >= root.allCases.length) {
                check("idle at the end", agent.flow === null && prompt.window === null)
                console.log("AUTHTEST RESULT pass " + root.passed + " fail " + root.failed)
                quitSoon.start()
                return
            }
            const c = root.allCases[root.at++]
            console.log("AUTHTEST case: " + c.name)
            let wait = 100
            try { wait = c.run() } catch (e) { root.failed++; console.log("AUTHTEST FAIL " + c.name + " threw: " + e) }
            interval = Math.max(20, wait || 100)
            restart()
        }
    }
    Timer { id: quitSoon; interval: 400; onTriggered: Qt.quit() }
}
