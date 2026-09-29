import QtQuick

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
    property string storyStatus: "ready"
    property string storySource: mode === "composition" ? "generic-composition" : "generic-provider"
    property string storyError: ""
    property string textValue: mode === "composition" ? "" : "Generic text input"
    property bool checkedValue: false
    property bool openValue: false
    readonly property real contentExtentWidth: viewportWidth
    readonly property real contentExtentHeight: viewportHeight
    property var controls: [{ "label": "State", "options": [{ "label": "Default" }, { "label": "Filled" }] }]
    property var actions: [{ "label": "Clear" }, { "label": "Accept" }]

    signal eventRecorded(var record)
    signal inspectionReady(var inspection)

    width: viewportWidth
    height: viewportHeight
    color: "#20283a"
    border.color: "#6aa9ff"
    border.width: 2

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

    function applyControl(groupIndex, optionIndex) {
        textValue = optionIndex === 1 ? "Filled from control" : ""
        eventRecorded({ "origin": "control", "name": "changed", "group": groupIndex, "option": optionIndex, "payload": { "text": textValue } })
    }

    function triggerAction(index) {
        if (index === 0) {
            textValue = ""
            eventRecorded({ "origin": "action", "name": "clear" })
        } else {
            eventRecorded({ "origin": "component", "name": "accepted", "payload": { "text": textValue } })
        }
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
