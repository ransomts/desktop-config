// Stand-in for Quickshell.Services.Polkit's PolkitAgent (0.3.2), with its queue as in
// agentimpl.cpp: requests wait in arrival order, only the front one has a flow, and when that
// flow's isCompleted turns true the flow goes away (flow -> null) and the next one starts in the
// same call. Never touches polkit or D-Bus.
import QtQuick

Item {
    id: agent
    property bool isRegistered: false
    property var flow: null
    readonly property bool isActive: flow !== null
    signal authenticationRequestStarted()

    property var queue: []
    property int started: 0
    Component { id: flowComp; FakeFlow {} }

    // spec: FakeFlow properties (message, actionId, identities, prompts, ...)
    function request(spec) {
        queue.push(spec)
        if (flow === null) activate()
    }
    function activate() {
        if (queue.length === 0) return
        const spec = queue.shift(), ids = spec.identities || []
        delete spec.identities
        const fl = flowComp.createObject(agent, spec)
        fl.identities = ids
        fl.start()
        fl.isCompletedChanged.connect(() => agent.finish(fl))
        flow = fl
        started += 1
        authenticationRequestStarted()
    }
    // what each finished flow came to (the flow itself is destroyed, as the real one is)
    property var done: []
    function last() { return done[done.length - 1] }
    function finish(fl) {
        if (flow !== fl || !fl.isCompleted) return
        done.push({ message: fl.message, isSuccessful: fl.isSuccessful, isCancelled: fl.isCancelled,
                    isCompleted: true, answers: fl.answers.slice(), sessions: fl.sessions,
                    selectedIdentity: fl.selectedIdentity })
        flow = null
        Qt.callLater(() => fl.destroy())
        activate()
    }
    function daemonCancel() { if (flow) flow.cancelFromAgent() }
}
