import QtQuick

Item {
    id: root
    property var flowData: "__FLOW_DATA__"
    property var storyConfig: "__STORY_CONFIG__"
    property var compositionDoc: "__COMPOSITION_DOC__"
    property var captureArtifacts: "__CAPTURE_ARTIFACTS__"
    property bool verbose: "__VERBOSE__"
    property string textValue: ""
    property bool openValue: false
    property var events: []

    function record(origin, name, node, payload) {
        events = events.concat([{ "origin": origin, "name": name, "node": node || "", "payload": payload || {} }])
    }

    function nodeExists(id) {
        if (!id || !compositionDoc)
            return true
        let found = false
        function walk(node) {
            if (!node || found)
                return
            if (node.id === id)
                found = true
            const children = Array.isArray(node.children) ? node.children : []
            for (let i = 0; i < children.length; i++)
                walk(children[i])
        }
        walk(compositionDoc.root)
        return found
    }

    function observable(name) {
        if (name === "text")
            return textValue
        if (name === "open")
            return openValue
        return undefined
    }

    function equal(a, b) {
        return JSON.stringify(a) === JSON.stringify(b)
    }

    function runStep(step, index) {
        const node = step.node || ""
        if (node && !nodeExists(node))
            return { "index": index, "type": step.type, "ok": false, "error": "unknown node '" + node + "'" }
        if (step.type === "reset") {
            textValue = ""
            openValue = false
            events = []
            return { "index": index, "type": step.type, "ok": true }
        }
        if (step.type === "write") {
            textValue = String(step.text || "")
            record("component", "changed", node, { "text": textValue })
            return { "index": index, "type": step.type, "node": node, "ok": true }
        }
        if (step.type === "action") {
            if (step.name === "clear")
                textValue = ""
            else if (step.name === "open")
                openValue = true
            else if (step.name === "close")
                openValue = false
            else if (step.name === "toggle")
                openValue = !openValue
            else
                return { "index": index, "type": step.type, "node": node, "ok": false, "error": "unavailable action '" + step.name + "'" }
            record("injected", step.name, node, {})
            return { "index": index, "type": step.type, "node": node, "ok": true }
        }
        if (step.type === "emit") {
            record("injected", step.event, node, step.payload || {})
            return { "index": index, "type": step.type, "node": node, "ok": true }
        }
        if (step.type === "expect") {
            const actual = observable(step.observable)
            const ok = equal(actual, step.equals)
            return { "index": index, "type": step.type, "node": node, "ok": ok, "expected": step.equals, "actual": actual, "error": ok ? "" : "expected " + step.observable + " to equal " + JSON.stringify(step.equals) }
        }
        if (step.type === "expectEvent") {
            const ok = events.some(function(event) { return event.name === step.event && event.origin === step.origin && (!node || event.node === node) })
            return { "index": index, "type": step.type, "node": node, "ok": ok, "error": ok ? "" : "missing event '" + step.event + "'" }
        }
        // A synchronous fixture has nothing to await, so idle is honestly a
        // no-op. Everything else here is a CAPABILITY this host does not have,
        // and it says so instead of reporting success: a step that reports ok
        // without doing anything is how a document "passes" a flow whose state
        // changes never happened, and how a provider ships a reduced
        // implementation that no check ever notices. Run those steps against a
        // real provider, not this fixture.
        if (step.type === "awaitIdle")
            return { "index": index, "type": step.type, "node": node, "ok": true }
        return { "index": index, "type": step.type, "node": node, "ok": false, "error": "the generic fixture does not implement '" + step.type + "'" }
    }

    Component.onCompleted: {
        const steps = []
        const source = Array.isArray(flowData.steps) ? flowData.steps : []
        let status = "pass"
        let error = ""
        for (let i = 0; i < source.length; i++) {
            const result = runStep(source[i], i)
            steps.push(result)
            if (!result.ok) {
                status = "fail"
                error = result.error || "step failed"
                break
            }
        }
        console.log("QSM_FLOW_RESULT " + JSON.stringify({ "status": status, "key": flowData.key, "error": error, "steps": steps, "events": events, "viewport": { "width": 800, "height": 500 }, "artifacts": {} }))
        Qt.quit()
    }
}
