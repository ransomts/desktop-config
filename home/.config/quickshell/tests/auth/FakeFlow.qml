// Stand-in for Quickshell.Services.Polkit's AuthFlow (0.3.2): the same properties, signals and
// methods, and the same order of events as flow.cpp (see the auth agent's polkit-api.org).
// PAM is played by timers: a prompt `askMs` after each session starts, a verdict `pamMs` after
// each answer. What submit() receives is kept in `answers` for the tests to compare; it is never
// printed.
import QtQuick

Item {
    id: f
    // ---- the AuthFlow API ----
    property string message: ""
    property string iconName: ""
    property string actionId: ""
    property string cookie: "cookie-1"
    property var identities: []
    property var selectedIdentity: null
    property bool isResponseRequired: false
    property string inputPrompt: ""
    property bool responseVisible: false
    property string supplementaryMessage: ""
    property bool supplementaryIsError: false
    property bool isCompleted: false
    property bool isSuccessful: false
    property bool isCancelled: false
    property bool failed: false
    signal authenticationSucceeded()
    signal authenticationFailed()
    signal authenticationRequestCancelled()

    function submit(value) {
        if (isCompleted || !isResponseRequired) return
        answers.push(value)
        pending = value
        isResponseRequired = false; inputPrompt = ""; responseVisible = false
        pam.restart()
    }
    function cancelAuthenticationRequest() {
        if (isCompleted) return
        askTimer.stop(); pam.stop(); pending = ""
        isCancelled = true
        isResponseRequired = false
        isSuccessful = false
        isCompleted = true                      // the agent drops the flow here
    }
    // the polkit daemon's cancel (PolkitAgentImpl::cancelAuthentication -> cancelFromAgent)
    function cancelFromAgent() {
        if (isCompleted) return
        askTimer.stop(); pam.stop(); pending = ""
        isCancelled = true
        isResponseRequired = false
        isCompleted = true
        authenticationRequestCancelled()
    }
    function showInfo(msg) { supplementaryMessage = msg; supplementaryIsError = false }
    function showError(msg) { supplementaryMessage = msg; supplementaryIsError = true }

    // ---- the play ----
    property var prompts: [{ text: "Password: ", echo: false, want: "" }]     // conversation turns
    property int askMs: 80
    property int pamMs: 200
    property var answers: []
    property int sessions: 0
    property int turn: 0
    property string pending: ""
    property bool started: false

    // FakeAgent sets `identities` after creating the flow (so they stay the same JS objects, as
    // the real ones are the same QObjects) and then calls start()
    function start() {
        if (identities.length > 0) selectedIdentity = identities[0]
        started = true
        setupSession()
    }
    // as AuthFlow::setSelectedIdentity: cancelling the old session reports completed(false)
    // synchronously while isCancelled is false, i.e. a failure, which starts a session; then
    // setSelectedIdentity starts another.
    onSelectedIdentityChanged: {
        if (!started) return
        failed = true
        authenticationFailed()
        setupSession()
        setupSession()
    }
    function setupSession() {
        sessions += 1
        turn = 0
        isResponseRequired = false
        askTimer.restart()
    }
    function ask() {
        if (isCompleted) return
        const p = prompts[turn]
        inputPrompt = p.text; responseVisible = p.echo === true; isResponseRequired = true
    }
    function decide() {
        if (isCompleted) return
        const ok = pending === prompts[turn].want
        pending = ""
        if (!ok) {
            failed = true
            authenticationFailed()
            setupSession()
        } else if (turn + 1 < prompts.length) {
            turn += 1
            askTimer.restart()
        } else {
            isSuccessful = true
            isCompleted = true
            authenticationSucceeded()
        }
    }
    Timer { id: askTimer; interval: f.askMs; onTriggered: f.ask() }
    Timer { id: pam; interval: f.pamMs; onTriggered: f.decide() }
}
