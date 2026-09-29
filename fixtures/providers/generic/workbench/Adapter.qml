import QtQuick

// The synthetic provider's whole contribution: a test double, not a real
// component harness. It hosts no unit file, so its `integration` is declared
// here in full and every flow step has one honest door to reach it. The flow
// state machine itself is the harness's, driven through this adapter.
Rectangle {
    id: root
    property string mode: "story"
    property var story: ({})
    property var composition: null
    property int resetGeneration: 0
    property bool interactive: false
    property int viewportWidth: 800
    property int viewportHeight: 500
    property string storyKey: ""
    property string component: ""
    property string variant: ""
    readonly property string storyStatus: "ready"
    readonly property string storySource: mode === "composition" ? "generic-composition" : "generic-provider"
    readonly property string storyError: ""
    readonly property real contentExtentWidth: viewportWidth
    readonly property real contentExtentHeight: viewportHeight
    property var controls: [{
        "label": "State",
        "options": [
            { "label": "Default", "set": { "variant": "default" } },
            { "label": "Filled", "set": { "variant": "filled" } }
        ]
    }]
    property var actions: [
        { "label": "Clear", "trigger": "clear" },
        { "label": "Accept", "trigger": "accept" },
        { "label": "Open", "trigger": "open" }
    ]

    // The drivability surface the flow host reads: events it may inject,
    // observables and keys it may call, a text driver, and the animation
    // checkpoint it can hold at its declared boundary.
    readonly property var integration: ({
        events: ["changed", "accepted", "opened"],
        observables: {
            text: () => root.textValue,
            open: () => root.openValue,
            variant: () => root.variant
        },
        keys: {
            Enter: () => root.accept(),
            Escape: () => root.clear(),
            Space: () => root.accept()
        },
        textDriver: text => root.setText(String(text ?? "")),
        checkpoints: {
            "rollout.opened": {
                arm: () => { root.paused = true; return true },
                reached: () => root.openValue,
                resume: () => { root.paused = false; return true }
            }
        },
        idle: () => true
    })

    property string textValue: ""
    property bool openValue: false
    property bool paused: false

    signal eventRecorded(var record)
    signal inspectionReady(var inspection)

    width: viewportWidth
    height: viewportHeight
    color: "#20283a"
    border.color: "#6aa9ff"
    border.width: 2

    onResetGenerationChanged: {
        root.textValue = ""
        root.openValue = false
        root.paused = false
    }

    function setText(value) {
        root.textValue = value
        root.eventRecorded({ "origin": "component", "name": "changed", "payload": { "text": value } })
        return true
    }

    function clear() {
        return root.setText("")
    }

    function accept() {
        root.eventRecorded({ "origin": "component", "name": "accepted", "payload": { "text": root.textValue } })
        return true
    }

    function open() {
        root.openValue = true
        root.eventRecorded({ "origin": "component", "name": "opened", "payload": {} })
        return true
    }

    function applyControl(groupIndex, optionIndex) {
        const group = root.controls[groupIndex]
        const option = group ? group.options[optionIndex] : null
        if (!option || !option.set)
            return false
        for (const key in option.set)
            root[key] = option.set[key]
        return true
    }

    function triggerAction(index) {
        const action = root.actions[index]
        if (!action)
            return false
        if (action.trigger === "clear")
            return root.clear()
        if (action.trigger === "accept")
            return root.accept()
        if (action.trigger === "open")
            return root.open()
        return false
    }

    function compositionNodes() {
        const out = []
        function walk(node, depth) {
            if (!node)
                return
            out.push({ "id": String(node.id || "node"), "type": String(node.type || "unknown"), "depth": depth, "props": node.props || {} })
            const children = Array.isArray(node.children) ? node.children : []
            for (let i = 0; i < children.length; i++)
                walk(children[i], depth + 1)
        }
        if (composition && composition.root)
            walk(composition.root, 0)
        return out
    }

    function dumpTree() {
        inspectionReady({ "provider": "generic-provider", "mode": mode, "storyKey": storyKey, "component": component, "variant": variant, "compositionKey": composition ? composition.key : "", "nodes": compositionNodes() })
    }

    Column {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 12

        Text {
            text: root.mode === "composition" ? "Composition: " + ((root.composition && root.composition.key) || "draft") : "Story: " + root.storyKey
            color: "white"
            font.pixelSize: 28
        }

        Rectangle {
            width: parent.width - 24
            height: 72
            radius: 12
            color: "#34415f"
            border.color: "#91c7ff"
            Text {
                anchors.centerIn: parent
                color: "white"
                font.pixelSize: 20
                text: root.textValue || root.variant || "empty"
            }
        }

        Repeater {
            model: root.mode === "composition" ? root.compositionNodes() : []
            delegate: Rectangle {
                width: parent.width - 24 - modelData.depth * 20
                x: modelData.depth * 20
                height: 34
                radius: 6
                color: modelData.type === "text-field" ? "#4a5f89" : "#2d3650"
                border.color: "#6aa9ff"
                Text {
                    anchors.centerIn: parent
                    color: "white"
                    text: modelData.id + "  " + modelData.type
                }
            }
        }
    }
}
