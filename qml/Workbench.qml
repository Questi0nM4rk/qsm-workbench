import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ApplicationWindow {
    id: root
    visible: true
    width: 1280
    height: 820
    minimumWidth: 960
    minimumHeight: 620
    title: "QSM Workbench"
    color: "#0c0a0f"

    readonly property url providerRoot: Quickshell.env("QSM_WORKBENCH_PROVIDER_ROOT") || ""
    readonly property string providerDir: Quickshell.env("QSM_WORKBENCH_PROVIDER_DIR") || ""
    readonly property string providerId: Quickshell.env("QSM_WORKBENCH_PROVIDER_ID") || ""
    readonly property string providerTitle: Quickshell.env("QSM_WORKBENCH_PROVIDER_TITLE") || root.providerId
    readonly property url providerAdapter: Quickshell.env("QSM_WORKBENCH_PROVIDER_ADAPTER") || ""
    readonly property string workRoot: Quickshell.env("QSM_WORKBENCH_ROOT") || ""
    readonly property string initialKey: Quickshell.env("QSM_WORKBENCH_INITIAL_STORY") || ""
    readonly property string registryPath: Quickshell.env("QSM_WORKBENCH_REGISTRY_PATH") || ""
    readonly property string metadataPath: Quickshell.env("QSM_WORKBENCH_METADATA_PATH") || ""
    readonly property string launchFlowPath: Quickshell.env("QSM_WORKBENCH_FLOW_PATH") || ""
    readonly property bool explicitStory: Quickshell.env("QSM_WORKBENCH_EXPLICIT_STORY") === "1"
    readonly property string launcherPath: Quickshell.env("QSM_WORKBENCH_LAUNCHER") || ""
    // Bead mr9.6: mutable in-process catalog. Env snapshot is the startup
    // authority; bounded watchers merge later registry/metadata changes here.
    property var registry: JSON.parse(Quickshell.env("QSM_WORKBENCH_REGISTRY") || "{}")
    property string selectedKey: root.initialKey
    property string filterText: ""
    property real zoom: 1.0
    property string zoomMode: "fit"
    // Bead mr9.6: persisted shell geometry and panel state.
    property real navigatorWidth: 264
    property real inspectorWidth: 264
    property bool navigatorCollapsed: false
    property bool inspectorCollapsed: false
    property string stateDiagnostic: ""
    property string catalogError: ""
    property bool stateReady: false
    property bool reloadRestored: false
    property string appliedKey: ""
    // Bead mr9.4: workbench-owned observability state. All bounded and local.
    property int resetGeneration: 0
    property int eventCap: 200
    property var eventLog: []
    property var lastInspection: null
    property string inspectionText: ""
    property string inspectorTab: "Story"
    // Bead mr9.5: one named task runner. Exactly one Process below runs fixed
    // supervisor argv; starting a second operation while one runs is disabled.
    property string taskStatus: "idle"
    property string taskLabel: ""
    property var taskArgv: []
    property int taskExitCode: -1
    property bool taskCancelRequested: false
    property string taskCapturePath: ""
    property int taskOutBase: 0
    property int taskErrBase: 0

    // Bead 05v.4: additive Compose mode. Story selection and persistence
    // below stay untouched; the draft is mutable in-memory only (no draft
    // persistence in this bead). Descriptor/starters arrive as launcher
    // environment JSON; QML never reads their files.
    property string navMode: "stories"
    property var composeTypes: ({})
    property var composeStarters: []
    property var composeDoc: null
    property string selectedNodeId: ""
    property string composeError: ""
    property string addType: "text-field"
    // Bead 05v.5: descriptor-driven property editing, all-node controls,
    // and named links. Draft link choices stay uncommitted until Add; an
    // invalid draft reads as empty without touching the other choices.
    property string composePropError: ""
    property string composeLinkFrom: ""
    property string composeLinkFromEvent: ""
    property string composeLinkTo: ""
    property string composeLinkToAction: ""
    property string composeLinkError: ""
    property var composeExpanded: ({})
    // Bead 05v.6: one atomic versioned draft plus a reviewable project
    // save. Story/window persistence above stays untouched.
    property string composeSaveStatus: ""
    property string projectSavePath: ""
    property string compositionFilePath: ""
    property bool draftReady: false
    property bool explicitCompose: false
    property bool composeInitDone: false
    property string draftPendingText: ""
    property bool draftPendingLoaded: false
    property string draftPendingError: ""
    // True while the draft restore assigns document/selection so the
    // restore itself never schedules a rewrite.
    property bool suppressDraftSave: false

    function isComposeMode() {
        return root.navMode === "compose"
    }

    function story(key) {
        return root.registry[key] ?? ({})
    }

    function detectedTag(value) {
        return String(value ?? "").trim().toLowerCase()
            .replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
    }

    function storyTags(item) {
        if (Array.isArray(item.tags))
            return item.tags
        const tags = []
        for (const value of [root.detectedTag(item.component), root.detectedTag(item.variant)])
            if (value !== "" && tags.indexOf(value) < 0)
                tags.push(value)
        return tags
    }

    function groupOf(item) {
        const tags = root.storyTags(item)
        return tags.length > 0 ? tags[0] : "other"
    }

    function viewportWidth() {
        if (root.isComposeMode() && root.composeDoc) {
            const vp = root.composeDoc.viewport
            return (Array.isArray(vp) && vp[0] > 0) ? vp[0] : 0
        }
        const selected = root.story(root.selectedKey)
        return (selected.viewport && selected.viewport[0] > 0) ? selected.viewport[0] : 0
    }

    function viewportHeight() {
        if (root.isComposeMode() && root.composeDoc) {
            const vp = root.composeDoc.viewport
            return (Array.isArray(vp) && vp[1] > 0) ? vp[1] : 0
        }
        const selected = root.story(root.selectedKey)
        return (selected.viewport && selected.viewport[1] > 0) ? selected.viewport[1] : 0
    }

    function canvasContentWidth() {
        const preview = previewLoader.item
        const extent = preview && preview.contentExtentWidth !== undefined
            ? Number(preview.contentExtentWidth) : 0
        return Math.max(root.viewportWidth(), Number.isFinite(extent) ? extent : 0)
    }

    function canvasContentHeight() {
        const preview = previewLoader.item
        const extent = preview && preview.contentExtentHeight !== undefined
            ? Number(preview.contentExtentHeight) : 0
        return Math.max(root.viewportHeight(), Number.isFinite(extent) ? extent : 0)
    }

    function canvasKey() {
        if (root.isComposeMode() && root.composeDoc)
            return String(root.composeDoc.key || "compose")
        return root.selectedKey
    }

    function matches(item, key, needle) {
        if (!needle)
            return true
        const tags = root.storyTags(item).join(" ")
        const text = [key, item.title, item.component, item.variant, tags].join(" ").toLowerCase()
        return text.includes(needle)
    }

    function filteredItems() {
        const needle = root.filterText.trim().toLowerCase()
        const items = Object.keys(root.registry).filter(key => root.matches(root.registry[key], key, needle)).map(key => ({
            "key": key,
            "group": root.groupOf(root.registry[key])
        }))
        items.sort((a, b) => (a.group < b.group ? -1 : a.group > b.group ? 1 : a.key < b.key ? -1 : a.key > b.key ? 1 : 0))
        return items
    }

    function filteredIndex(key) {
        return root.filteredItems().findIndex(entry => entry.key === key)
    }

    function selectKey(key) {
        if (!root.story(key).viewport)
            return
        root.selectedKey = key
        root.applyCanvas()
        const index = root.filteredIndex(key)
        if (index >= 0)
            storyList.positionViewAtIndex(index, ListView.Contain)
    }

    function moveSelection(delta) {
        const items = root.filteredItems()
        if (items.length === 0)
            return
        let index = items.findIndex(entry => entry.key === root.selectedKey)
        if (index < 0)
            index = delta >= 0 ? -1 : 0
        index = Math.min(items.length - 1, Math.max(0, index + delta))
        root.selectKey(items[index].key)
    }

    function clampZoom(value) {
        return Math.min(4, Math.max(0.1, value))
    }

    function zoomIn() {
        root.zoom = root.clampZoom(root.effZoom * 1.25)
        root.zoomMode = "manual"
    }

    function zoomOut() {
        root.zoom = root.clampZoom(root.effZoom * 0.8)
        root.zoomMode = "manual"
    }

    // Presentation-only scale. The Loader below always keeps the declared
    // viewport size; this transform never touches preview inputs.
    property real fitScale: {
        const vw = root.viewportWidth()
        const vh = root.viewportHeight()
        if (vw <= 0 || vh <= 0 || stageFlick.width <= 0 || stageFlick.height <= 0)
            return 1
        return Math.min(4, Math.max(0.05, Math.min(stageFlick.width / vw, stageFlick.height / vh)))
    }
    property real effZoom: root.zoomMode === "fit" ? root.fitScale : root.zoom
    property string zoomText: Math.round(root.effZoom * 100) + "%"

    function previewUrl() {
        return root.providerAdapter
    }

    function loaderStatusText(status) {
        if (status === Loader.Ready)
            return "ready"
        if (status === Loader.Loading)
            return "loading"
        if (status === Loader.Error)
            return "failed"
        return "empty"
    }

    function controlsOf(item) {
        return (item && Array.isArray(item.controls)) ? item.controls : []
    }

    function actionsOf(item) {
        return (item && item.actions) ? item.actions : []
    }

    function nestedStatusOf(item) {
        return (item && item.storyStatus !== undefined) ? String(item.storyStatus) : ""
    }

    function nestedSourceOf(item) {
        return (item && item.storySource !== undefined) ? String(item.storySource) : ""
    }

    function nestedErrorOf(item) {
        return (item && item.storyError !== undefined) ? String(item.storyError) : ""
    }

    function isNestedFailed() {
        return previewLoader.status === Loader.Ready && root.nestedStatusOf(previewLoader.item) === "failed"
    }

    function isNestedLoading() {
        return previewLoader.status === Loader.Ready && root.nestedStatusOf(previewLoader.item) === "loading"
    }

    function appendEvent(record) {
        let next = root.eventLog.concat([record])
        if (next.length > root.eventCap)
            next = next.slice(next.length - root.eventCap)
        root.eventLog = next
    }

    function payloadText(record) {
        try {
            return JSON.stringify(record.payload !== undefined ? record.payload : {})
        } catch (e) {
            return String(record.payload)
        }
    }

    function activateControl(groupIndex, optionIndex) {
        const peer = previewLoader.item
        if (peer && typeof peer.applyControl === "function")
            peer.applyControl(groupIndex, optionIndex)
    }

    function activateAction(index) {
        const peer = previewLoader.item
        if (peer && typeof peer.triggerAction === "function")
            peer.triggerAction(index)
    }

    function refreshInspection() {
        const peer = previewLoader.item
        if (peer && typeof peer.dumpTree === "function")
            peer.dumpTree()
    }

    function resetStory() {
        // True reset: reconstruct the story via generation, drop local
        // evidence, keep selection. No full Preview reconstruction here.
        root.eventLog = []
        root.lastInspection = null
        root.inspectionText = ""
        root.resetGeneration++
        const peer = previewLoader.item
        if (peer)
            peer.resetGeneration = root.resetGeneration
    }

    // Bead 05v.4: composition tree model and explicit structural edits.
    // Every edit clones the last valid document, gates the candidate on
    // child policy/depth/node-limit, and only then swaps it in and rebuilds
    // the canvas. Invalid edits keep the last valid canvas and set an
    // inline nonfatal diagnostic instead.
    function composeClone(doc) {
        return JSON.parse(JSON.stringify(doc))
    }

    function composeTypeNames() {
        const types = root.composeTypes && root.composeTypes.types
        if (types && typeof types === "object" && Object.keys(types).length > 0) {
            const names = Object.keys(types)
            names.sort()
            return names
        }
        return ["checkbox", "column", "menu", "radio", "row", "segmented", "shell-border-rollout", "slider", "spin-box", "stack", "switch", "text-field"]
    }

    function composeTypeOptions() {
        return root.composeTypeNames().map(name => ({
            "value": name,
            "label": root.composeTypeLabel(name)
        }))
    }

    function composeTypeSpec(type) {
        const types = root.composeTypes && root.composeTypes.types
        return (types && types[type]) || null
    }

    function composeTypeLabel(type) {
        const spec = root.composeTypeSpec(type)
        return (spec && spec.label) || type
    }

    function composeCanHaveChildren(type) {
        const spec = root.composeTypeSpec(type)
        if (spec)
            return spec.children === "many"
        return ["column", "row", "stack", "menu", "shell-border-rollout"].includes(type)
    }

    function composeDefaultProps(type) {
        const out = {}
        const spec = root.composeTypeSpec(type)
        const declared = (spec && spec.props) || {}
        for (const field of Object.keys(declared)) {
            if (declared[field] && declared[field].default !== undefined)
                out[field] = declared[field].default
        }
        return out
    }

    // Flattened depth-indented tree in document order. Each entry carries
    // the stable id, type, depth (root 0), and ancestor path string.
    function composeNodeList() {
        const out = []
        if (!root.composeDoc || !root.composeDoc.root)
            return out
        const walk = (node, depth, ancestors) => {
            const id = String(node.id || "?")
            const trail = ancestors.concat([id])
            out.push({ "id": id, "type": String(node.type || "?"), "depth": depth, "path": trail.join(" / ") })
            const kids = Array.isArray(node.children) ? node.children : []
            for (const child of kids)
                walk(child, depth + 1, trail)
        }
        walk(root.composeDoc.root, 0, [])
        return out
    }

    function composeFindNodeIn(docRoot, nodeId) {
        if (!docRoot || typeof docRoot !== "object")
            return null
        if (String(docRoot.id) === String(nodeId))
            return docRoot
        const kids = Array.isArray(docRoot.children) ? docRoot.children : []
        for (const child of kids) {
            const found = root.composeFindNodeIn(child, nodeId)
            if (found)
                return found
        }
        return null
    }

    // { node, parent, index }; parent is null and index -1 for the root.
    function composeLocateIn(docRoot, nodeId) {
        if (!docRoot || typeof docRoot !== "object")
            return null
        if (String(docRoot.id) === String(nodeId))
            return { "node": docRoot, "parent": null, "index": -1 }
        const walk = (current) => {
            const kids = Array.isArray(current.children) ? current.children : []
            for (let i = 0; i < kids.length; i++) {
                if (String(kids[i].id) === String(nodeId))
                    return { "node": kids[i], "parent": current, "index": i }
                const deeper = walk(kids[i])
                if (deeper)
                    return deeper
            }
            return null
        }
        return walk(docRoot)
    }

    function composeLocate(nodeId) {
        if (!root.composeDoc || !root.composeDoc.root)
            return null
        return root.composeLocateIn(root.composeDoc.root, nodeId)
    }

    function composeSelectedPath() {
        const entry = root.composeNodeList().find(row => row.id === root.selectedNodeId)
        return entry ? entry.path : ""
    }

    function composeSelectedIndex() {
        return root.composeNodeList().findIndex(row => row.id === root.selectedNodeId)
    }

    function composeEnsureSelection() {
        if (!root.composeDoc || !root.composeDoc.root) {
            root.selectedNodeId = ""
            return
        }
        if (!root.selectedNodeId || !root.composeFindNodeIn(root.composeDoc.root, root.selectedNodeId))
            root.selectedNodeId = String(root.composeDoc.root.id)
    }

    function composeIsRootSelected() {
        return !!root.composeDoc && !!root.composeDoc.root && root.selectedNodeId === String(root.composeDoc.root.id)
    }

    function composeCanEditSelected() {
        return !!root.composeLocate(root.selectedNodeId) && !root.composeIsRootSelected()
    }

    function composeMoveSelection(delta) {
        const items = root.composeNodeList()
        if (items.length === 0)
            return
        let index = items.findIndex(row => row.id === root.selectedNodeId)
        if (index < 0)
            index = delta >= 0 ? -1 : 0
        index = Math.min(items.length - 1, Math.max(0, index + delta))
        root.selectedNodeId = items[index].id
    }

    function composeCollectIdsIn(docRoot) {
        const ids = {}
        const walk = (node) => {
            ids[String(node.id)] = true
            for (const child of (Array.isArray(node.children) ? node.children : []))
                walk(child)
        }
        if (docRoot)
            walk(docRoot)
        return ids
    }

    function composeKebab(value) {
        let slug = String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
        if (slug === "" || !/^[a-z0-9]/.test(slug))
            slug = "node"
        return slug.slice(0, 48)
    }

    function composeUniqueIn(base, taken) {
        const slug = root.composeKebab(base)
        if (!taken[slug])
            return slug
        let n = 2
        while (taken[slug + "-" + n])
            n++
        return slug + "-" + n
    }

    function composeUniqueId(base) {
        const taken = root.composeDoc && root.composeDoc.root ? root.composeCollectIdsIn(root.composeDoc.root) : {}
        return root.composeUniqueIn(base, taken)
    }

    // Bead 05v.6: full version 1 document validator. Mirrors
    // scripts/composition.mjs validateDocument: strict top/node/link
    // allowlists, key/viewport bounds, 64 nodes, depth 8, stable kebab
    // ids, descriptor-typed props, child policy, executable rejection,
    // and declared link endpoints. "" means the document is valid.
    function composeValidateDocument(doc) {
        if (!doc || typeof doc !== "object" || Array.isArray(doc))
            return "composition document must be a JSON object"
        const topAllowed = ["version", "key", "viewport", "root", "links"]
        const execField = /^(source|sourceurl|qml|url|path|file|script|javascript|js|expression|binding|command|exec|shell|eval|args|arguments|code|payload|handler|callback|component|loader|import|require)$/i
        for (const field of Object.keys(doc)) {
            if (!topAllowed.includes(field)) {
                if (execField.test(field))
                    return field + " is executable content and is not allowed in composition documents"
                return field + " is not a known field"
            }
        }
        if (doc.version !== 1)
            return "version must be exactly 1"
        if (typeof doc.key !== "string" || !/^[a-z0-9][a-z0-9-]{0,63}$/.test(doc.key))
            return "key must be stable kebab-case (lowercase alphanumerics and dashes, max 64 chars)"
        const keyProblem = root.composeExecutableTextProblem(doc.key)
        if (keyProblem !== "")
            return "key " + keyProblem
        const vp = doc.viewport
        if (!Array.isArray(vp) || vp.length !== 2)
            return "viewport must be a two-number array [width, height]"
        if (!Number.isInteger(vp[0]) || vp[0] < 320 || vp[0] > 3840)
            return "viewport width must be an integer 320..3840"
        if (!Number.isInteger(vp[1]) || vp[1] < 240 || vp[1] > 2160)
            return "viewport height must be an integer 240..2160"
        const types = (root.composeTypes && root.composeTypes.types) || {}
        const tokens = (root.composeTypes && root.composeTypes.tokens) || ["none", "xs", "sm", "md", "lg"]
        const nodeAllowed = ["id", "type", "props", "children"]
        const linkAllowed = ["from", "to"]
        const seen = {}
        const nodeTypes = {}
        let count = 0
        const checkProp = (spec, value, path) => {
            if (typeof value === "string") {
                if (value.includes("\0"))
                    return path + " contains a null byte"
                const hit = root.composeExecutableTextProblem(value)
                if (hit !== "")
                    return path + " " + hit
            }
            if (spec.type === "boolean") {
                if (typeof value !== "boolean")
                    return path + " must be a boolean"
            } else if (spec.type === "string") {
                if (typeof value !== "string")
                    return path + " must be a string"
                if (spec.maxLength !== undefined && value.length > spec.maxLength)
                    return path + " exceeds max length " + spec.maxLength
            } else if (spec.type === "number") {
                if (typeof value !== "number" || !Number.isFinite(value))
                    return path + " must be a finite number"
                if (spec.integer && !Number.isInteger(value))
                    return path + " must be an integer"
                if (spec.min !== undefined && value < spec.min)
                    return path + " is below minimum " + spec.min
                if (spec.max !== undefined && value > spec.max)
                    return path + " is above maximum " + spec.max
            } else if (spec.type === "enum") {
                if (typeof value !== "string" || !(spec.values || []).includes(value))
                    return path + " must be one of: " + (spec.values || []).join(", ")
            } else if (spec.type === "spacing") {
                if (typeof value !== "string" || !tokens.includes(value))
                    return path + " must be one of: " + tokens.join(", ")
            } else {
                return path + " has an unknown descriptor type '" + spec.type + "'"
            }
            return ""
        }
        const walk = (node, path, depth) => {
            count++
            if (count > 64)
                return "composition exceeds 64 nodes"
            if (depth > 8)
                return "composition exceeds depth 8"
            if (!node || typeof node !== "object" || Array.isArray(node))
                return path + ": node must be an object"
            for (const field of Object.keys(node)) {
                if (!nodeAllowed.includes(field)) {
                    if (execField.test(field))
                        return path + "." + field + " is executable content and is not allowed in composition documents"
                    return path + "." + field + " is not a known field"
                }
            }
            const at = (field) => (path ? path + "." + field : field)
            if (typeof node.id !== "string" || !/^[a-z0-9][a-z0-9-]{0,63}$/.test(node.id))
                return "node id at '" + path + "' must be stable kebab-case"
            const idProblem = root.composeExecutableTextProblem(node.id)
            if (idProblem !== "")
                return at("id") + " " + idProblem
            if (seen[node.id])
                return "duplicate node id '" + node.id + "' (first seen at " + seen[node.id] + ")"
            seen[node.id] = path || "root"
            const spec = types[node.type]
            if (typeof node.type !== "string" || !spec)
                return at("type") + ": unknown node type '" + node.type + "'"
            nodeTypes[node.id] = node.type
            const props = (node.props === undefined || node.props === null) ? {} : node.props
            if (typeof props !== "object" || Array.isArray(props))
                return at("props") + ": props must be an object"
            const declared = (spec.props && typeof spec.props === "object") ? spec.props : {}
            for (const field of Object.keys(props)) {
                const fieldPath = at("props") + "." + field
                if (Object.keys(declared).indexOf(field) < 0) {
                    if (execField.test(field))
                        return fieldPath + " is executable content and is not allowed in composition documents"
                    return fieldPath + " is not a declared property of type '" + node.type + "'"
                }
                const problem = checkProp(declared[field], props[field], fieldPath)
                if (problem !== "")
                    return problem
            }
            if (node.children === undefined || node.children === null)
                return ""
            if (!Array.isArray(node.children))
                return at("children") + ": children must be an array"
            if (node.children.length > 0 && spec.children !== "many")
                return at("children") + ": type '" + node.type + "' does not accept children"
            for (let i = 0; i < node.children.length; i++) {
                const problem = walk(node.children[i], at("children") + "[" + i + "]", depth + 1)
                if (problem !== "")
                    return problem
            }
            return ""
        }
        if (!doc.root || typeof doc.root !== "object" || Array.isArray(doc.root))
            return "root must be a node object"
        const rootProblem = walk(doc.root, "root", 1)
        if (rootProblem !== "")
            return rootProblem
        const links = (doc.links === undefined || doc.links === null) ? [] : doc.links
        if (!Array.isArray(links))
            return "links must be an array"
        for (let i = 0; i < links.length; i++) {
            const linkPath = "links[" + i + "]"
            const link = links[i]
            if (!link || typeof link !== "object" || Array.isArray(link))
                return linkPath + ": link must be an object"
            for (const field of Object.keys(link)) {
                if (!linkAllowed.includes(field)) {
                    if (execField.test(field))
                        return linkPath + "." + field + " is executable content and is not allowed in composition documents"
                    return linkPath + "." + field + " is not a known field"
                }
            }
            const ends = [["from", "event", "events"], ["to", "action", "actions"]]
            for (const end of ends) {
                const endName = end[0]
                const nameField = end[1]
                const ep = link[endName]
                const epPath = linkPath + "." + endName
                if (!ep || typeof ep !== "object" || Array.isArray(ep))
                    return epPath + ": link " + endName + " must be an object"
                const epAllowed = endName === "from" ? ["node", "event"] : ["node", "action"]
                for (const field of Object.keys(ep)) {
                    if (!epAllowed.includes(field)) {
                        if (execField.test(field))
                            return epPath + "." + field + " is executable content and is not allowed in composition documents"
                        return epPath + "." + field + " is not a known field"
                    }
                }
                if (typeof ep.node !== "string" || !seen[ep.node])
                    return epPath + ".node: link " + endName + " references unknown node '" + ((ep && ep.node !== undefined) ? ep.node : "?") + "'"
                const nodeProblem = root.composeExecutableTextProblem(ep.node)
                if (nodeProblem !== "")
                    return epPath + ".node " + nodeProblem
                const nodeType = nodeTypes[ep.node]
                const typeSpec = types[nodeType] || {}
                const declared = typeSpec[end[2]] || []
                const name = ep[nameField]
                if (typeof name !== "string" || !declared.includes(name))
                    return epPath + "." + nameField + ": link " + endName + " names undeclared " + nameField + " '" + name + "' for node '" + ep.node + "' of type '" + nodeType + "'"
                const nameProblem = root.composeExecutableTextProblem(name)
                if (nameProblem !== "")
                    return epPath + "." + nameField + " " + nameProblem
            }
        }
        return ""
    }

    // Pre-apply gate: the full version 1 document check above. "" means
    // the candidate applies.
    function composeCheckCandidate(doc) {
        return root.composeValidateDocument(doc)
    }

    function composeApplyCandidate(candidate, newSelectedId) {
        const problem = root.composeCheckCandidate(candidate)
        if (problem !== "") {
            root.composeError = problem
            return false
        }
        root.composeDoc = candidate
        root.selectedNodeId = newSelectedId
        root.composeEnsureSelection()
        root.composeError = ""
        root.applyComposition()
        root.scheduleDraftSave()
        return true
    }

    function composeBlankDoc() {
        return {
            "version": 1,
            "key": "blank",
            "viewport": [960, 640],
            "root": { "id": "root", "type": "column", "props": {}, "children": [] }
        }
    }

    function startBlankCompose() {
        root.composeApplyCandidate(root.composeBlankDoc(), "root")
    }

    function openStarterCompose(index) {
        const starter = root.composeStarters[index]
        if (!starter)
            return
        const candidate = root.composeClone(starter)
        root.composeApplyCandidate(candidate, String(candidate.root.id))
    }

    // Add appends to a selected container; on a selected leaf it inserts
    // as the next sibling. No drag-and-drop.
    function composeAddNode() {
        if (!root.composeDoc || !root.composeDoc.root) {
            root.composeError = "start from blank or a starter first"
            return
        }
        const type = root.addType
        if (!root.composeTypeNames().includes(type)) {
            root.composeError = "unknown node type '" + type + "'"
            return
        }
        const candidate = root.composeClone(root.composeDoc)
        const newId = root.composeUniqueIn(type, root.composeCollectIdsIn(candidate.root))
        const fresh = { "id": newId, "type": type, "props": root.composeDefaultProps(type) }
        if (root.composeCanHaveChildren(type))
            fresh.children = []
        const live = root.composeLocateIn(candidate.root, root.selectedNodeId)
        if (!live) {
            if (!root.composeCanHaveChildren(candidate.root.type)) {
                root.composeError = "root does not accept children"
                return
            }
            candidate.root.children = (candidate.root.children || []).concat([fresh])
            root.composeApplyCandidate(candidate, newId)
            return
        }
        if (root.composeCanHaveChildren(live.node.type)) {
            live.node.children = (live.node.children || []).concat([fresh])
        } else if (live.parent) {
            live.parent.children.splice(live.index + 1, 0, fresh)
        } else {
            root.composeError = "root does not accept children"
            return
        }
        root.composeApplyCandidate(candidate, newId)
    }

    // Duplicate deep-clones the selected subtree beside itself; every
    // copied node gets a fresh deterministic unique id. Root is fixed.
    function composeDuplicateNode() {
        const located = root.composeLocate(root.selectedNodeId)
        if (!located || !located.node) {
            root.composeError = "select a node to duplicate"
            return
        }
        if (!located.parent) {
            root.composeError = "root cannot be duplicated"
            return
        }
        const candidate = root.composeClone(root.composeDoc)
        const live = root.composeLocateIn(candidate.root, root.selectedNodeId)
        const taken = root.composeCollectIdsIn(candidate.root)
        const copy = root.composeClone(live.node)
        const reassign = (node) => {
            node.id = root.composeUniqueIn(String(node.id), taken)
            taken[node.id] = true
            for (const child of (Array.isArray(node.children) ? node.children : []))
                reassign(child)
        }
        reassign(copy)
        const copyId = String(copy.id)
        live.parent.children.splice(live.index + 1, 0, copy)
        root.composeApplyCandidate(candidate, copyId)
    }

    function composeMoveNode(delta) {
        const located = root.composeLocate(root.selectedNodeId)
        if (!located || !located.node) {
            root.composeError = "select a node to move"
            return
        }
        if (!located.parent) {
            root.composeError = "root cannot move"
            return
        }
        const next = located.index + delta
        if (next < 0 || next >= located.parent.children.length)
            return
        const candidate = root.composeClone(root.composeDoc)
        const live = root.composeLocateIn(candidate.root, root.selectedNodeId)
        const arr = live.parent.children
        const tmp = arr[live.index]
        arr[live.index] = arr[live.index + delta]
        arr[live.index + delta] = tmp
        root.composeApplyCandidate(candidate, root.selectedNodeId)
    }

    function composeDeleteNode() {
        const located = root.composeLocate(root.selectedNodeId)
        if (!located || !located.node) {
            root.composeError = "select a node to delete"
            return
        }
        if (!located.parent) {
            root.composeError = "root cannot be deleted"
            return
        }
        const candidate = root.composeClone(root.composeDoc)
        const live = root.composeLocateIn(candidate.root, root.selectedNodeId)
        const parentId = String(live.parent.id)
        // Prune every link touching anywhere in the deleted subtree; all
        // other edits keep links untouched via the plain clone above.
        const doomed = {}
        const mark = (node) => {
            doomed[String(node.id)] = true
            for (const child of (Array.isArray(node.children) ? node.children : []))
                mark(child)
        }
        mark(live.node)
        live.parent.children.splice(live.index, 1)
        candidate.links = (Array.isArray(candidate.links) ? candidate.links : []).filter(link => !doomed[String(link.from && link.from.node)] && !doomed[String(link.to && link.to.node)])
        root.composeApplyCandidate(candidate, parentId)
    }

    // Bead 05v.5: descriptor-driven property/viewport/link editing plus
    // per-node control routing. Every mutation clones the last valid
    // document, validates the single edited value against the descriptor,
    // and only then swaps it in and rebuilds. Failures set an adjacent
    // diagnostic and leave the last valid doc/canvas untouched.
    function composeSelectedNode() {
        const located = root.composeLocate(root.selectedNodeId)
        return located ? located.node : null
    }

    function composeSelectedType() {
        const node = root.composeSelectedNode()
        return node ? String(node.type || "") : ""
    }

    function composePropFields(type) {
        const spec = root.composeTypeSpec(type)
        const declared = (spec && spec.props) || {}
        return Object.keys(declared)
    }

    function composePropSpec(type, field) {
        const spec = root.composeTypeSpec(type)
        const declared = (spec && spec.props) || {}
        return declared[field] || null
    }

    function composeNodeProp(nodeId, field) {
        const node = root.composeFindNodeIn(root.composeDoc ? root.composeDoc.root : null, nodeId)
        if (!node || !node.props)
            return undefined
        return node.props[field]
    }

    function composePropDisplay(nodeId, type, field) {
        const current = root.composeNodeProp(nodeId, field)
        if (current !== undefined)
            return current
        const spec = root.composePropSpec(type, field)
        return (spec && spec.default !== undefined) ? spec.default : ""
    }

    function composeExecutableTextProblem(value) {
        const text = String(value)
        const patterns = [/\.qml(\W|$)/i, /file:\/\//i, /\bqrc:/i, /import\s+Qt\w*/, /<script/i, /javascript:/i, /\$\{/, /function\s*\(/, /__proto__/, /constructor\s*\./]
        for (const pattern of patterns)
            if (pattern.test(text))
                return "text looks like executable content"
        return ""
    }

    function composeSetProp(nodeId, field, raw) {
        const node = root.composeFindNodeIn(root.composeDoc ? root.composeDoc.root : null, nodeId)
        if (!node) {
            root.composePropError = "select a node to edit"
            return false
        }
        const type = String(node.type || "")
        const spec = root.composePropSpec(type, field)
        if (!spec) {
            root.composePropError = "'" + field + "' is not a declared property of type '" + type + "'"
            return false
        }
        let value = raw
        if (spec.type === "boolean") {
            if (typeof value !== "boolean") {
                root.composePropError = "'" + field + "' must be on or off"
                return false
            }
        } else if (spec.type === "enum") {
            value = String(value)
            if (!(spec.values || []).includes(value)) {
                root.composePropError = "'" + field + "' must be one of: " + (spec.values || []).join(", ")
                return false
            }
        } else if (spec.type === "spacing") {
            value = String(value)
            const tokens = (root.composeTypes && root.composeTypes.tokens) || ["none", "xs", "sm", "md", "lg"]
            if (!tokens.includes(value)) {
                root.composePropError = "'" + field + "' must be one of: " + tokens.join(", ")
                return false
            }
        } else if (spec.type === "number") {
            const n = Number(value)
            if (!Number.isFinite(n)) {
                root.composePropError = "'" + field + "' must be a finite number"
                return false
            }
            if (spec.integer && !Number.isInteger(n)) {
                root.composePropError = "'" + field + "' must be an integer"
                return false
            }
            if (spec.min !== undefined && n < spec.min) {
                root.composePropError = "'" + field + "' is below minimum " + spec.min
                return false
            }
            if (spec.max !== undefined && n > spec.max) {
                root.composePropError = "'" + field + "' is above maximum " + spec.max
                return false
            }
            value = n
        } else if (spec.type === "string") {
            value = String(value)
            if (value.includes("\0")) {
                root.composePropError = "'" + field + "' contains a null byte"
                return false
            }
            const executableProblem = root.composeExecutableTextProblem(value)
            if (executableProblem !== "") {
                root.composePropError = "'" + field + "' " + executableProblem
                return false
            }
            if (spec.maxLength !== undefined && value.length > spec.maxLength) {
                root.composePropError = "'" + field + "' exceeds max length " + spec.maxLength
                return false
            }
        } else {
            root.composePropError = "'" + field + "' has an unknown descriptor type '" + spec.type + "'"
            return false
        }
        const candidate = root.composeClone(root.composeDoc)
        const live = root.composeFindNodeIn(candidate.root, nodeId)
        if (!live) {
            root.composePropError = "select a node to edit"
            return false
        }
        live.props = live.props || {}
        live.props[field] = value
        const problem = root.composeCheckCandidate(candidate)
        if (problem !== "") {
            root.composePropError = problem
            return false
        }
        root.composeDoc = candidate
        root.composePropError = ""
        root.applyComposition()
        root.scheduleDraftSave()
        return true
    }

    // Compact Composition section: kebab-case key plus bounded integer
    // viewport (320..3840 x 240..2160, mirroring the document validator).
    function composeSetDocKey(raw) {
        if (!root.composeDoc) {
            root.composePropError = "start from blank or a starter first"
            return false
        }
        const key = String(raw || "")
        if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(key)) {
            root.composePropError = "key must be stable kebab-case (lowercase alphanumerics and dashes, max 64 chars)"
            return false
        }
        const candidate = root.composeClone(root.composeDoc)
        candidate.key = key
        root.composeDoc = candidate
        root.composePropError = ""
        root.applyComposition()
        root.scheduleDraftSave()
        return true
    }

    function composeSetViewport(wRaw, hRaw) {
        if (!root.composeDoc) {
            root.composePropError = "start from blank or a starter first"
            return false
        }
        const w = Number(wRaw)
        const h = Number(hRaw)
        if (!Number.isInteger(w) || w < 320 || w > 3840) {
            root.composePropError = "viewport width must be an integer 320..3840"
            return false
        }
        if (!Number.isInteger(h) || h < 240 || h > 2160) {
            root.composePropError = "viewport height must be an integer 240..2160"
            return false
        }
        const candidate = root.composeClone(root.composeDoc)
        candidate.viewport = [w, h]
        root.composeDoc = candidate
        root.composePropError = ""
        root.applyComposition()
        root.scheduleDraftSave()
        return true
    }

    // Named links: closed node/event/action choices taken only from
    // descriptor-declared events/actions. Drafts that stop matching the
    // document read back as "" so only the stale choice resets.
    function composeLinkEventNodes() {
        return root.composeNodeList().filter(row => (root.composeTypeSpec(row.type).events || []).length > 0)
    }

    function composeLinkActionNodes() {
        return root.composeNodeList().filter(row => (root.composeTypeSpec(row.type).actions || []).length > 0)
    }

    function composeLinkEvents(nodeId) {
        const entry = root.composeNodeList().find(row => row.id === nodeId)
        if (!entry)
            return []
        return root.composeTypeSpec(entry.type).events || []
    }

    function composeLinkActions(nodeId) {
        const entry = root.composeNodeList().find(row => row.id === nodeId)
        if (!entry)
            return []
        return root.composeTypeSpec(entry.type).actions || []
    }

    function composeEffectiveLink() {
        const fromOk = root.composeLinkEventNodes().some(row => row.id === root.composeLinkFrom)
        const toOk = root.composeLinkActionNodes().some(row => row.id === root.composeLinkTo)
        const eventOk = fromOk && root.composeLinkEvents(root.composeLinkFrom).includes(root.composeLinkFromEvent)
        const actionOk = toOk && root.composeLinkActions(root.composeLinkTo).includes(root.composeLinkToAction)
        if (!fromOk || !eventOk || !toOk || !actionOk)
            return null
        return { "from": { "node": root.composeLinkFrom, "event": root.composeLinkFromEvent }, "to": { "node": root.composeLinkTo, "action": root.composeLinkToAction } }
    }

    function composeCanAddLink() {
        return !!root.composeDoc && root.composeEffectiveLink() !== null
    }

    function composeAddLink() {
        if (!root.composeDoc) {
            root.composeLinkError = "start from blank or a starter first"
            return false
        }
        const link = root.composeEffectiveLink()
        if (!link) {
            root.composeLinkError = "pick a source node/event and a target node/action first"
            return false
        }
        const existing = Array.isArray(root.composeDoc.links) ? root.composeDoc.links : []
        const dupe = existing.some(item => item && item.from && item.to && String(item.from.node) === link.from.node && String(item.from.event) === link.from.event && String(item.to.node) === link.to.node && String(item.to.action) === link.to.action)
        if (dupe) {
            root.composeLinkError = "that link already exists"
            return false
        }
        const candidate = root.composeClone(root.composeDoc)
        candidate.links = existing.concat([link])
        const problem = root.composeCheckCandidate(candidate)
        if (problem !== "") {
            root.composeLinkError = problem
            return false
        }
        root.composeDoc = candidate
        root.composeLinkError = ""
        root.applyComposition()
        root.scheduleDraftSave()
        return true
    }

    function composeDeleteLink(index) {
        if (!root.composeDoc || !Array.isArray(root.composeDoc.links))
            return false
        if (index < 0 || index >= root.composeDoc.links.length)
            return false
        const candidate = root.composeClone(root.composeDoc)
        candidate.links.splice(index, 1)
        root.composeDoc = candidate
        root.composeLinkError = ""
        root.applyComposition()
        root.scheduleDraftSave()
        return true
    }

    // All-node controls: flattened preview groups carry nodeId, so each
    // section maps back to the exact flattened index and routes through
    // the existing activateControl/activateAction entry points.
    function composeControlGroups(nodeId) {
        const peer = previewLoader.item
        const flat = (peer && peer.controls) ? peer.controls : []
        const out = []
        const list = Array.isArray(flat) ? flat : (flat && typeof flat.length === "number" ? Array.from(flat) : [])
        for (let i = 0; i < list.length; i++) {
            if (list[i] && String(list[i].nodeId) === String(nodeId))
                out.push({ "flat": i, "label": list[i].label, "options": list[i].options || [] })
        }
        return out
    }

    function composeActionEntries(nodeId) {
        const peer = previewLoader.item
        const flat = (peer && peer.actions) ? peer.actions : []
        const out = []
        const list = Array.isArray(flat) ? flat : (flat && typeof flat.length === "number" ? Array.from(flat) : [])
        for (let i = 0; i < list.length; i++) {
            if (list[i] && String(list[i].nodeId) === String(nodeId))
                out.push({ "flat": i, "label": list[i].label })
        }
        return out
    }

    function composeIsExpanded(nodeId) {
        return String(nodeId) === String(root.selectedNodeId) || root.composeExpanded[String(nodeId)] === true
    }

    function composeToggleExpanded(nodeId) {
        const key = String(nodeId)
        const next = Object.assign({}, root.composeExpanded)
        if (next[key] === true)
            delete next[key]
        else
            next[key] = true
        root.composeExpanded = next
    }

    // Launcher boundary: descriptor/starters arrive as environment JSON.
    // --compose enters Compose mode with the exact validated document.
    function initCompose() {
        try {
            const rawTypes = Quickshell.env("QSM_WORKBENCH_COMPOSITION_TYPES") || ""
            if (rawTypes !== "") {
                const parsed = JSON.parse(rawTypes)
                if (parsed && typeof parsed === "object")
                    root.composeTypes = parsed
            }
        } catch (e) {}
        try {
            const rawStarters = Quickshell.env("QSM_WORKBENCH_COMPOSITION_STARTERS") || ""
            if (rawStarters !== "") {
                const parsed = JSON.parse(rawStarters)
                if (Array.isArray(parsed))
                    root.composeStarters = parsed
            }
        } catch (e) {}
        const initial = Quickshell.env("QSM_WORKBENCH_COMPOSITION") || ""
        root.explicitCompose = initial !== ""
        if (initial === "") {
            if (root.composeTypeNames().includes(root.addType) === false)
                root.addType = root.composeTypeNames()[0] || "text-field"
            return
        }
        try {
            root.composeDoc = JSON.parse(initial)
        } catch (e) {
            root.composeDoc = null
            root.composeError = "initial composition is not valid JSON; start from blank or a starter"
            return
        }
        const initialProblem = root.composeValidateDocument(root.composeDoc)
        if (initialProblem !== "") {
            root.composeDoc = null
            root.composeError = "initial composition is invalid (" + initialProblem + "); start from blank or a starter"
            return
        }
        root.navMode = "compose"
        root.compositionFilePath = Quickshell.env("QSM_WORKBENCH_COMPOSITION_PATH") || ""
        if (root.composeTypeNames().includes(root.addType) === false)
            root.addType = root.composeTypeNames()[0] || "text-field"
        root.composeEnsureSelection()
    }

    // Bead 05v.6: one versioned draft file, debounced atomic writes, and
    // last-valid fallback. Only validated documents are ever written; the
    // wrapper carries just the document plus the selected node id. An
    // unreadable or invalid draft is nonfatal: the current valid canvas
    // stays and the file is left alone until a later valid edit/reset.
    function scheduleDraftSave(documentChanged) {
        if (documentChanged === undefined || documentChanged)
            root.compositionFilePath = ""
        if (root.suppressDraftSave || !root.draftReady || !root.composeDoc)
            return
        draftSaveTimer.restart()
    }

    function writeDraftNow() {
        if (!root.draftReady || !root.composeDoc)
            return
        if (root.composeValidateDocument(root.composeDoc) !== "")
            return
        try {
            draftFile.setText(JSON.stringify({ "version": 1, "doc": root.composeDoc, "selectedNodeId": root.selectedNodeId }, null, 2) + "\n")
        } catch (e) {}
    }

    function restoreDraftFromText(text) {
        if (root.explicitStory || root.explicitCompose || !text || text.trim() === "")
            return
        let wrapper = null
        try {
            wrapper = JSON.parse(text)
        } catch (e) {
            root.composeError = "draft is not valid JSON; start from blank or reset from example — last valid canvas kept"
            return
        }
        if (!wrapper || typeof wrapper !== "object" || Array.isArray(wrapper)) {
            root.composeError = "draft is malformed; start from blank or reset from example — last valid canvas kept"
            return
        }
        if (wrapper.version !== 1) {
            root.composeError = "unsupported draft version; start from blank or reset from example — last valid canvas kept"
            return
        }
        const problem = root.composeValidateDocument(wrapper.doc)
        if (problem !== "") {
            root.composeError = "draft is invalid (" + problem + "); start from blank or reset from example — last valid canvas kept"
            return
        }
        root.composeDoc = wrapper.doc
        const wanted = (typeof wrapper.selectedNodeId === "string") ? wrapper.selectedNodeId : ""
        root.suppressDraftSave = true
        if (wanted !== "" && root.composeFindNodeIn(root.composeDoc.root, wanted))
            root.selectedNodeId = wanted
        else
            root.selectedNodeId = String(root.composeDoc.root.id)
        root.suppressDraftSave = false
        root.navMode = "compose"
        root.compositionFilePath = ""
        root.composeError = ""
        root.composeSaveStatus = ""
        root.applyComposition()
    }

    // Explicit recovery only: reset keeps the starter matching the current
    // key, otherwise the TextField matrix. Nothing is discarded implicitly.
    function draftStarterForReset() {
        const starters = Array.isArray(root.composeStarters) ? root.composeStarters : []
        if (root.composeDoc && root.composeDoc.key) {
            const match = starters.find(entry => entry && entry.key === root.composeDoc.key)
            if (match)
                return root.composeClone(match)
        }
        const matrix = starters.find(entry => entry && entry.key === "text-field-matrix")
        if (matrix)
            return root.composeClone(matrix)
        if (starters.length > 0)
            return root.composeClone(starters[0])
        return root.composeBlankDoc()
    }

    function resetDraftFromExample() {
        const candidate = root.draftStarterForReset()
        const nextId = (candidate && candidate.root && candidate.root.id) ? String(candidate.root.id) : "root"
        return root.composeApplyCandidate(candidate, nextId)
    }

    function newBlankDraft() {
        return root.composeApplyCandidate(root.composeBlankDoc(), "root")
    }

    // Reviewable promotion: formatted JSON only to the known compositions
    // directory under the validated kebab key. Never touches scenarios,
    // examples, metadata, and never runs a command.
    function saveDraftToProject() {
        if (!root.composeDoc) {
            root.composeSaveStatus = "not saved: no draft to save"
            return false
        }
        const problem = root.composeValidateDocument(root.composeDoc)
        if (problem !== "") {
            root.composeSaveStatus = "not saved: draft is invalid (" + problem + ")"
            return false
        }
        const key = String(root.composeDoc.key || "")
        if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(key)) {
            root.composeSaveStatus = "not saved: invalid key '" + key + "'"
            return false
        }
        if (!root.workRoot) {
            root.composeSaveStatus = "not saved: unknown workbench root"
            return false
        }
        const path = root.workRoot + "/compositions/" + key + ".json"
        try {
            projectSaveFile.path = path
            projectSaveFile.setText(JSON.stringify(root.composeDoc, null, 2) + "\n")
        } catch (e) {
            root.composeSaveStatus = "save failed: " + path + " (" + e.message + ")"
            return false
        }
        root.composeSaveStatus = "saved to " + path
        root.compositionFilePath = path
        return true
    }

    function compositionUrl() {
        return root.providerAdapter
    }

    function loadComposition() {
        // Clear first so a slow load never shows a stale document.
        previewLoader.source = ""
        root.eventLog = []
        root.lastInspection = null
        root.inspectionText = ""
        if (!root.composeDoc)
            return
        previewLoader.setSource(root.compositionUrl(), {
            "composition": root.composeDoc,
            "resetGeneration": root.resetGeneration
        })
    }

    function applyComposition() {
        root.loadComposition()
    }

    function applyCanvas() {
        if (root.isComposeMode() && root.composeDoc)
            root.applyComposition()
        else
            root.applyStory()
    }

    function enterMode(mode) {
        if (root.navMode === mode)
            return
        root.navMode = mode
        root.applyCanvas()
    }

    function loadPreview() {
        // Clear first so a slow load never shows the previous story as current.
        previewLoader.source = ""
        root.eventLog = []
        root.lastInspection = null
        root.inspectionText = ""
        const selected = root.story(root.selectedKey)
        previewLoader.setSource(root.previewUrl(), {
            "mode": "story",
            "story": selected,
            "component": selected.component,
            "variant": selected.variant,
            "viewportWidth": selected.viewport[0],
            "viewportHeight": selected.viewport[1],
            "storyKey": root.selectedKey,
            "resetGeneration": root.resetGeneration,
            "interactive": false
        })
    }

    function applyStory() {
        const selected = root.story(root.selectedKey)
        if (!selected.viewport)
            return
        root.appliedKey = root.selectedKey
        root.loadPreview()
    }

    // Bead mr9.6: persistence, watching, recovery. All bounded and local.
    function validStoryKey(key) {
        return !!key && !!root.story(key).viewport
    }

    function firstStoryKey() {
        const keys = Object.keys(root.registry)
        return keys.length > 0 ? keys[0] : ""
    }

    function clampIntValue(value, fallback, lo, hi) {
        const n = Math.round(Number(value))
        if (!Number.isFinite(n))
            return fallback
        return Math.min(hi, Math.max(lo, n))
    }

    function clampZoomValue(value) {
        const n = Number(value)
        return (Number.isFinite(n) && n >= 0.1 && n <= 4) ? n : 1
    }

    function validZoomMode(mode) {
        return mode === "manual" ? "manual" : "fit"
    }

    function validInspectorTab(tab) {
        return ["Story", "Controls", "Events", "Inspect", "Tasks", "Diagnostics"].includes(tab) ? tab : "Story"
    }

    // Copy live values into the state adapter plus reload retention, then
    // debounce one atomic file write. Guarded until the first restore.
    function scheduleStateSave() {
        if (!root.stateReady)
            return
        stateAdapter.version = 1
        stateAdapter.selectedKey = root.selectedKey
        stateAdapter.zoom = root.zoom
        stateAdapter.zoomMode = root.zoomMode
        stateAdapter.inspectorTab = root.inspectorTab
        stateAdapter.windowWidth = Math.round(root.width)
        stateAdapter.windowHeight = Math.round(root.height)
        stateAdapter.navigatorWidth = Math.round(root.navigatorWidth)
        stateAdapter.inspectorWidth = Math.round(root.inspectorWidth)
        stateAdapter.navigatorCollapsed = root.navigatorCollapsed
        stateAdapter.inspectorCollapsed = root.inspectorCollapsed
        reloadPersist.selectedKey = root.selectedKey
        reloadPersist.zoom = root.zoom
        reloadPersist.zoomMode = root.zoomMode
        reloadPersist.inspectorTab = root.inspectorTab
        stateSaveTimer.restart()
    }

    // One idempotent restore. Explicit CLI story wins; otherwise the
    // reload-kept values win over the state file, and a saved key applies
    // only if still present in the catalog.
    function restoreAll() {
        if (root.explicitStory && root.validStoryKey(root.initialKey)) {
            root.selectedKey = root.initialKey
        } else if (!root.explicitStory && root.reloadRestored && root.validStoryKey(reloadPersist.selectedKey)) {
            root.selectedKey = reloadPersist.selectedKey
        } else if (root.validStoryKey(root.selectedKey)) {
            // Keep the current selection.
        } else if (!root.explicitStory && stateAdapter.version === 1 && root.validStoryKey(stateAdapter.selectedKey)) {
            root.selectedKey = stateAdapter.selectedKey
        } else {
            const first = root.firstStoryKey()
            if (first)
                root.selectedKey = first
        }
        if (!root.explicitStory && root.reloadRestored) {
            root.zoom = root.clampZoomValue(reloadPersist.zoom)
            root.zoomMode = root.validZoomMode(reloadPersist.zoomMode)
            root.inspectorTab = root.validInspectorTab(reloadPersist.inspectorTab)
        } else if (stateAdapter.version === 1) {
            root.zoom = root.clampZoomValue(stateAdapter.zoom)
            root.zoomMode = root.validZoomMode(stateAdapter.zoomMode)
            root.inspectorTab = root.validInspectorTab(stateAdapter.inspectorTab)
        }
        if (stateAdapter.version === 1) {
            root.width = root.clampIntValue(stateAdapter.windowWidth, root.width, root.minimumWidth, 4096)
            root.height = root.clampIntValue(stateAdapter.windowHeight, root.height, root.minimumHeight, 2160)
            root.navigatorWidth = root.clampIntValue(stateAdapter.navigatorWidth, 264, 180, 600)
            root.inspectorWidth = root.clampIntValue(stateAdapter.inspectorWidth, 264, 200, 600)
            root.navigatorCollapsed = stateAdapter.navigatorCollapsed === true
            root.inspectorCollapsed = stateAdapter.inspectorCollapsed === true
            navPane.SplitView.preferredWidth = root.navigatorWidth
            inspPane.SplitView.preferredWidth = root.inspectorWidth
            if (stateAdapter.selectedKey !== "" && !root.validStoryKey(stateAdapter.selectedKey) && !root.explicitStory)
                root.stateDiagnostic = "saved story '" + stateAdapter.selectedKey + "' is not in the catalog; using first story"
        } else if (root.stateDiagnostic === "") {
            root.stateDiagnostic = "unsupported saved-state version; using defaults"
        }
        if (root.isComposeMode() && root.composeDoc)
            root.applyComposition()
        else if (root.selectedKey !== root.appliedKey)
            root.applyStory()
    }

    // Structural revalidation for runtime registry/metadata refreshes.
    // Mirrors the launcher rules; file-existence checks stay at startup.
    function validateCatalog(reg, meta) {
        if (!reg || typeof reg !== "object" || Array.isArray(reg) || Object.keys(reg).length === 0)
            return "registry must be a non-empty JSON object"
        const registryFields = ["component", "variant", "viewport"]
        const metadataFields = ["title", "description", "tags", "source", "docs", "tests"]
        const forbidden = ["component", "variant", "viewport"]
        for (const key of Object.keys(reg)) {
            if (!/^[a-z0-9][a-z0-9-]*$/.test(key))
                return "story key '" + key + "' is not stable kebab-case"
            const story = reg[key]
            if (!story || typeof story !== "object" || Array.isArray(story))
                return "story '" + key + "' must be an object"
            for (const field of Object.keys(story))
                if (!registryFields.includes(field))
                    return "story '" + key + "' has unknown registry field '" + field + "'"
            if (typeof story.component !== "string" || story.component.trim() === "")
                return "story '" + key + "' needs component"
            if (typeof story.variant !== "string" || story.variant.trim() === "")
                return "story '" + key + "' needs variant"
            if (!Array.isArray(story.viewport) || story.viewport.length !== 2)
                return "story '" + key + "' needs a two-number viewport"
            if (story.viewport.some(value => typeof value !== "number" || !Number.isFinite(value) || value <= 0))
                return "story '" + key + "' has an invalid viewport"
        }
        if (!meta || typeof meta !== "object" || Array.isArray(meta))
            return "metadata must be a JSON object"
        for (const key of Object.keys(meta)) {
            if (!reg[key])
                return "metadata references unknown story '" + key + "'"
            const entry = meta[key]
            if (!entry || typeof entry !== "object" || Array.isArray(entry))
                return "metadata for '" + key + "' must be an object"
            for (const field of Object.keys(entry)) {
                if (forbidden.includes(field))
                    return "metadata for '" + key + "' cannot set rendering field '" + field + "'"
                if (!metadataFields.includes(field))
                    return "metadata for '" + key + "' has unknown field '" + field + "'"
            }
        }
        return ""
    }

    // Reload and merge the catalog in process. Metadata enriches only known
    // canonical keys and never rendering fields. On any malformed runtime
    // file the last good catalog stays and the error is shown.
    function reloadCatalog() {
        const regText = registryWatcher.text()
        const metaText = metadataWatcher.text()
        if (!regText || regText.trim() === "") {
            root.catalogError = "registry file is empty or unreadable; keeping last good catalog"
            return
        }
        let reg, meta
        try {
            reg = JSON.parse(regText)
        } catch (e) {
            root.catalogError = "registry: " + e.message + "; keeping last good catalog"
            return
        }
        try {
            meta = (!metaText || metaText.trim() === "") ? {} : JSON.parse(metaText)
        } catch (e) {
            root.catalogError = "metadata: " + e.message + "; keeping last good catalog"
            return
        }
        const problem = root.validateCatalog(reg, meta)
        if (problem !== "") {
            root.catalogError = problem + "; keeping last good catalog"
            return
        }
        const merged = {}
        for (const key of Object.keys(reg)) {
            merged[key] = Object.assign({}, reg[key], meta[key] ?? {})
            if (!("tags" in merged[key]))
                merged[key].tags = root.storyTags(merged[key])
        }
        root.registry = merged
        root.catalogError = ""
        if (!root.validStoryKey(root.selectedKey)) {
            const first = root.firstStoryKey()
            if (first)
                root.selectKey(first)
        }
    }

    function reloadWorkbench() {
        Quickshell.reload(false)
    }

    function hardReloadWorkbench() {
        Quickshell.reload(true)
    }

    function restartProcess() {
        if (!root.launcherPath || !root.selectedKey)
            return
        Quickshell.execDetached(["node", root.launcherPath, root.selectedKey])
        Qt.quit()
    }

    function isEditingText() {
        const item = root.activeFocusItem
        if (!item)
            return false
        return item instanceof TextInput || item instanceof TextField || item instanceof TextArea
    }

    function escapeToCanvas() {
        if (searchField.text !== "")
            searchField.clear()
        stageFlick.forceActiveFocus()
    }

    function taskRunning() {
        return root.taskStatus === "running"
    }

    function selectedSource() {
        return root.story(root.selectedKey).source || ""
    }

    function capturePathFor(key) {
        return "/tmp/qsm-workbench-" + key + ".png"
    }

    function taskTail(text, base) {
        const fresh = String(text || "").slice(base)
        return fresh.length > 12000 ? fresh.slice(fresh.length - 12000) : fresh
    }

    function taskOutputText() {
        const out = root.taskTail(taskStdout.text, root.taskOutBase)
        const err = root.taskTail(taskStderr.text, root.taskErrBase)
        if (!out && !err)
            return root.taskRunning() ? "Running…" : "No output."
        let text = ""
        if (out)
            text += "stdout\n" + out
        if (err)
            text += (text !== "" ? "\n" : "") + "stderr\n" + err
        return text
    }

    function startTask(op, label, args, capturePath) {
        if (root.taskRunning())
            return
        root.taskLabel = label
        root.taskArgv = ["node", "scripts/task-runner.mjs", op].concat(args)
        root.taskExitCode = -1
        root.taskCancelRequested = false
        root.taskCapturePath = capturePath || ""
        root.taskOutBase = taskStdout.text.length
        root.taskErrBase = taskStderr.text.length
        root.taskStatus = "running"
        taskProcess.command = root.taskArgv
        taskProcess.running = true
    }

    function runValidate() {
        if (root.isComposeMode()) {
            if (root.compositionFilePath === "")
                return
            root.startTask("composition-check", "check " + root.canvasKey(), [root.compositionFilePath], "")
            return
        }
        root.startTask("validate", "validate " + root.providerId, [], "")
    }

    function runCapture() {
        const key = root.canvasKey()
        const path = root.capturePathFor(key)
        if (root.isComposeMode()) {
            if (root.compositionFilePath === "")
                return
            root.startTask("composition-capture", "capture " + key, [root.compositionFilePath, path], path)
            return
        }
        root.startTask("story-capture", "capture " + key, [key, path], path)
    }

    function runLaunchFlow() {
        if (root.launchFlowPath === "")
            return
        root.startTask("flow", "flow " + root.launchFlowPath.split("/").pop(), [root.launchFlowPath], "")
    }

    function cancelTask() {
        root.taskCancelRequested = true
        taskProcess.signal(15)
    }

    function clearTask() {
        root.taskStatus = "idle"
        root.taskLabel = ""
        root.taskArgv = []
        root.taskExitCode = -1
        root.taskCancelRequested = false
        root.taskCapturePath = ""
        root.taskOutBase = taskStdout.text.length
        root.taskErrBase = taskStderr.text.length
    }

    function openProviderPath(relative) {
        if (!relative || !root.providerDir)
            return
        Quickshell.execDetached(["xdg-open", root.providerDir + "/" + relative])
    }

    function openAbsPath(absolute) {
        if (!absolute)
            return
        Quickshell.execDetached(["xdg-open", absolute])
    }

    onWidthChanged: root.scheduleStateSave()
    onHeightChanged: root.scheduleStateSave()
    onSelectedKeyChanged: root.scheduleStateSave()
    onZoomChanged: root.scheduleStateSave()
    onZoomModeChanged: root.scheduleStateSave()
    onInspectorTabChanged: root.scheduleStateSave()
    onNavigatorCollapsedChanged: root.scheduleStateSave()
    onInspectorCollapsedChanged: root.scheduleStateSave()
    onSelectedNodeIdChanged: root.scheduleDraftSave(false)

    Component.onCompleted: {
        root.initCompose()
        if (root.draftPendingLoaded && root.draftPendingText !== "")
            root.restoreDraftFromText(root.draftPendingText)
        if (root.draftPendingError !== "")
            root.composeError = root.draftPendingError
        root.restoreAll()
        root.stateReady = true
        root.composeInitDone = true
        root.draftReady = true
    }

    // Bead mr9.6: one versioned JSON object under the Quickshell state dir.
    // Atomic writes, debounced through stateSaveTimer. watchChanges stays off
    // so our own write never reports back.
    FileView {
        id: stateFile
        path: Quickshell.statePath("workbench.json")
        atomicWrites: true
        printErrors: false
        blockLoading: true
        JsonAdapter {
            id: stateAdapter
            property int version: 1
            property string selectedKey: ""
            property real zoom: 1
            property string zoomMode: "fit"
            property string inspectorTab: "Story"
            property int windowWidth: 1280
            property int windowHeight: 820
            property int navigatorWidth: 264
            property int inspectorWidth: 264
            property bool navigatorCollapsed: false
            property bool inspectorCollapsed: false
        }
        onLoaded: root.restoreAll()
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                root.stateDiagnostic = "saved state unreadable; using defaults"
        }
    }

    Timer {
        id: stateSaveTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (root.stateReady)
                stateFile.writeAdapter()
        }
    }

    // Bead 05v.6: one separate versioned draft outside the v1 window/story
    // schema. Raw text with debounced atomic writes; watchChanges stays off
    // so our own write never reports back. A load that arrives before the
    // launcher boundary is parsed is stashed for Component.onCompleted.
    FileView {
        id: draftFile
        path: Quickshell.statePath("composition-draft.json")
        atomicWrites: true
        printErrors: false
        blockLoading: true
        onLoaded: {
            if (root.composeInitDone)
                root.restoreDraftFromText(draftFile.text())
            else {
                root.draftPendingText = draftFile.text()
                root.draftPendingLoaded = true
            }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                if (root.composeInitDone)
                    root.draftReady = true
                else {
                    root.draftPendingText = ""
                    root.draftPendingLoaded = true
                }
            } else {
                const message = "draft unreadable; starting without it — last valid canvas kept"
                if (root.composeInitDone) {
                    root.composeError = message
                    root.draftReady = true
                } else {
                    root.draftPendingText = ""
                    root.draftPendingLoaded = true
                    root.draftPendingError = message
                }
            }
        }
    }

    Timer {
        id: draftSaveTimer
        interval: 400
        repeat: false
        onTriggered: root.writeDraftNow()
    }

    // Bead 05v.6: the single reviewable promotion path. Its path is always
    // set to <workbench-root>/compositions/<validated-kebab-key>.json right
    // before the atomic write; nothing else is ever written through it.
    FileView {
        id: projectSaveFile
        path: root.projectSavePath
        atomicWrites: true
        printErrors: false
        blockLoading: false
    }

    // Bead mr9.6: retain only selection/tab/zoom across a Quickshell reload.
    // Restart persistence remains the JSON file above.
    PersistentProperties {
        id: reloadPersist
        reloadableId: "qsm-workbench"
        property string selectedKey: ""
        property string inspectorTab: "Story"
        property real zoom: 1
        property string zoomMode: "fit"
        onReloaded: {
            root.reloadRestored = true
            root.restoreAll()
        }
        onLoaded: root.restoreAll()
    }

    // Bead mr9.6: bounded watchers. Exactly these four inputs, debounced.
    FileView {
        id: registryWatcher
        path: root.registryPath
        watchChanges: true
        printErrors: false
        blockLoading: true
        onFileChanged: {
            reload()
            catalogTimer.restart()
        }
    }

    FileView {
        id: metadataWatcher
        path: root.metadataPath
        watchChanges: true
        printErrors: false
        blockLoading: true
        onFileChanged: {
            reload()
            catalogTimer.restart()
        }
    }

    FileView {
        id: storySourceWatcher
        path: root.selectedSource() !== "" && root.providerDir !== "" ? root.providerDir + "/" + root.selectedSource() : ""
        watchChanges: true
        printErrors: false
        onFileChanged: canvasTimer.restart()
    }

    FileView {
        id: previewWatcher
        path: root.providerAdapter
        watchChanges: true
        printErrors: false
        onFileChanged: canvasTimer.restart()
    }

    Timer {
        id: catalogTimer
        interval: 300
        repeat: false
        onTriggered: root.reloadCatalog()
    }

    Timer {
        id: canvasTimer
        interval: 250
        repeat: false
        onTriggered: root.applyCanvas()
    }

    // Bead mr9.6: practical keys beside the visible controls. Navigation and
    // zoom keys stay quiet while the preview is actively editing text.
    Shortcut {
        sequences: ["Ctrl+K"]
        onActivated: searchField.forceActiveFocus()
    }

    Shortcut {
        sequences: ["Up"]
        enabled: !root.isComposeMode() && !root.isEditingText() && !searchField.activeFocus
        onActivated: root.moveSelection(-1)
    }

    Shortcut {
        sequences: ["Down"]
        enabled: !root.isComposeMode() && !root.isEditingText() && !searchField.activeFocus
        onActivated: root.moveSelection(1)
    }

    Shortcut {
        sequences: ["F5"]
        enabled: !root.isEditingText()
        onActivated: root.applyCanvas()
    }

    Shortcut {
        sequences: ["Shift+F5"]
        enabled: !root.isEditingText()
        onActivated: root.hardReloadWorkbench()
    }

    Shortcut {
        sequences: ["Ctrl+0"]
        enabled: !root.isEditingText()
        onActivated: { root.zoom = 1; root.zoomMode = "manual" }
    }

    Shortcut {
        sequences: ["Ctrl+Minus"]
        enabled: !root.isEditingText()
        onActivated: root.zoomOut()
    }

    Shortcut {
        sequences: ["Ctrl+Plus"]
        enabled: !root.isEditingText()
        onActivated: root.zoomIn()
    }

    Shortcut {
        sequences: ["Escape"]
        onActivated: root.escapeToCanvas()
    }

    Connections {
        target: previewLoader.item
        function onEventRecorded(record) {
            root.appendEvent(record)
        }
        function onInspectionReady(inspection) {
            root.lastInspection = inspection
            try {
                let text = JSON.stringify(inspection, null, 2)
                if (text.length > 20000)
                    text = text.slice(0, 20000) + "\n…truncated…"
                root.inspectionText = text
            } catch (e) {
                root.inspectionText = String(inspection)
            }
        }
    }

    // The single named task runner. Fixed supervisor argv only; cancel sends
    // TERM to the supervisor, which owns process-group escalation to KILL.
    // A requested cancel stays cancelled even if the exit code is non-zero.
    Process {
        id: taskProcess
        workingDirectory: root.workRoot
        stdout: StdioCollector {
            id: taskStdout
        }
        stderr: StdioCollector {
            id: taskStderr
        }
        onExited: (exitCode, exitStatus) => {
            root.taskExitCode = exitCode
            if (root.taskCancelRequested)
                root.taskStatus = "cancelled"
            else if (exitCode === 0)
                root.taskStatus = "succeeded"
            else
                root.taskStatus = "failed"
        }
    }

    header: ToolBar {
        background: Rectangle { color: "#131017" }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            Label {
                text: "Workbench"
                color: "#eee9f2"
                font.pixelSize: 13
                font.bold: true
            }

            Label {
                text: root.isComposeMode() ? root.canvasKey() : root.selectedKey
                color: "#9d93a4"
                font.family: "monospace"
                font.pixelSize: 12
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Button {
                text: "Reset"
                onClicked: root.resetStory()
            }

            Button {
                text: "Reload"
                onClicked: root.applyCanvas()
            }
        }
    }

    // Bead mr9.6: flat split panes. Content-sized navigator and inspector,
    // flexible stage, hairline handles. Side panes collapse to keep the stage
    // the primary surface.
    SplitView {
        anchors.fill: parent
    orientation: Qt.Horizontal
    handle: Item {
        implicitWidth: 8

        Rectangle {
            anchors.centerIn: parent
            width: 1
            height: parent.height
            color: "#2b2430"
        }
    }

        // Navigator pane.
        Rectangle {
            id: navPane
            visible: !root.navigatorCollapsed
            SplitView.preferredWidth: 264
            SplitView.minimumWidth: 200
            color: "#131017"
            onWidthChanged: {
                if (!root.stateReady || !visible || width <= 0)
                    return
                root.navigatorWidth = Math.round(width)
                root.scheduleStateSave()
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                // Bead 05v.4: compact Stories | Compose mode switch.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Button {
                        text: "Stories"
                        implicitHeight: 28
                        Layout.fillWidth: true
                        highlighted: !root.isComposeMode()
                        onClicked: root.enterMode("stories")
                    }

                    Button {
                        text: "Compose"
                        implicitHeight: 28
                        Layout.fillWidth: true
                        highlighted: root.isComposeMode()
                        onClicked: root.enterMode("compose")
                    }
                }

                RowLayout {
                    visible: !root.isComposeMode()
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        text: "Stories"
                        color: "#eee9f2"
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Label {
                        text: root.filteredItems().length + " / " + Object.keys(root.registry).length
                        color: "#9d93a4"
                        font.family: "monospace"
                        font.pixelSize: 11
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                    }
                }

                TextField {
                    id: searchField
                    visible: !root.isComposeMode()
                    Layout.fillWidth: true
                    implicitHeight: 28
                    placeholderText: "Search key, title, tags"
                    onTextChanged: root.filterText = text
                    Keys.onDownPressed: root.moveSelection(1)
                    Keys.onUpPressed: root.moveSelection(-1)
                    Keys.onReturnPressed: root.moveSelection(0)
                    Keys.onEnterPressed: root.moveSelection(0)
                }

                ListView {
                    id: storyList
                    visible: !root.isComposeMode()
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 0
                    model: root.filteredItems()
                    currentIndex: root.filteredIndex(root.selectedKey)
                    section.property: "group"
                    section.delegate: Label {
                        required property string section
                        width: storyList.width
                        text: section.charAt(0).toUpperCase() + section.slice(1)
                        color: "#9d93a4"
                        font.pixelSize: 11
                        leftPadding: 8
                        topPadding: 8
                        bottomPadding: 2
                        elide: Text.ElideRight
                    }
                    Keys.onDownPressed: root.moveSelection(1)
                    Keys.onUpPressed: root.moveSelection(-1)

                    delegate: Button {
                        required property var modelData
                        width: storyList.width
                        implicitHeight: 28
                        text: root.story(modelData.key).title || modelData.key
                        highlighted: root.selectedKey === modelData.key
                        leftPadding: 8
                        contentItem: Label {
                            text: parent.text
                            color: parent.highlighted ? "#0c0a0f" : "#eee9f2"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 4
                            color: parent.highlighted ? "#b994dc" : (parent.hovered ? "#1a151f" : "transparent")
                            border.width: parent.activeFocus && !parent.highlighted ? 1 : 0
                            border.color: "#b994dc"
                        }
                        onClicked: root.selectKey(modelData.key)
                    }
                }

                // Bead 05v.4: composition tree replaces the story catalog
                // in Compose mode. The stage and inspector stay shared.
                ColumnLayout {
                    visible: root.isComposeMode()
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    Label {
                        visible: root.composeError !== ""
                        text: root.composeError
                        color: "#ff9d9d"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // Blank state: one direct blank start plus starters.
                    ColumnLayout {
                        visible: !root.composeDoc
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            text: "No draft — start one:"
                            color: "#9d93a4"
                            font.pixelSize: 12
                            Layout.fillWidth: true
                        }

                        Button {
                            text: "Start from blank"
                            implicitHeight: 28
                            Layout.fillWidth: true
                            onClicked: root.startBlankCompose()
                        }

                        Repeater {
                            model: root.composeStarters

                            Button {
                                required property var modelData
                                required property int index
                                text: (modelData && modelData.key) || ("starter " + (index + 1))
                                implicitHeight: 28
                                Layout.fillWidth: true
                                onClicked: root.openStarterCompose(index)
                            }
                        }
                    }

                    ColumnLayout {
                        visible: !!root.composeDoc
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8

                        Label {
                            text: "Tree  " + root.composeNodeList().length + " nodes"
                            color: "#9d93a4"
                            font.family: "monospace"
                            font.pixelSize: 11
                            Layout.fillWidth: true
                        }

                        ListView {
                            id: composeTree
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 0
                            model: root.composeNodeList()
                            currentIndex: root.composeSelectedIndex()
                            Keys.onDownPressed: root.composeMoveSelection(1)
                            Keys.onUpPressed: root.composeMoveSelection(-1)

                            delegate: Button {
                                required property var modelData
                                width: composeTree.width
                                implicitHeight: 28
                                text: modelData.id + "  ·  " + modelData.type
                                highlighted: root.selectedNodeId === modelData.id
                                leftPadding: 8 + modelData.depth * 12
                                contentItem: Label {
                                    text: parent.text
                                    color: parent.highlighted ? "#0c0a0f" : "#eee9f2"
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    radius: 4
                                    color: parent.highlighted ? "#b994dc" : (parent.hovered ? "#1a151f" : "transparent")
                                    border.width: parent.activeFocus && !parent.highlighted ? 1 : 0
                                    border.color: "#b994dc"
                                }
                                onClicked: root.selectedNodeId = modelData.id
                            }
                        }

                        Label {
                            text: "path  " + (root.composeSelectedPath() || "-")
                            color: "#9d93a4"
                            font.family: "monospace"
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            ComboBox {
                                Layout.fillWidth: true
                                implicitHeight: 28
                                model: root.composeTypeOptions()
                                textRole: "label"
                                currentIndex: Math.max(0, root.composeTypeOptions().findIndex(entry => entry.value === root.addType))
                                onActivated: index => { root.addType = root.composeTypeOptions()[index].value }
                            }

                            Button {
                                text: "Add"
                                implicitHeight: 28
                                enabled: !!root.composeDoc
                                onClicked: root.composeAddNode()
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 4

                            Button {
                                text: "Duplicate"
                                implicitHeight: 28
                                font.pixelSize: 11
                                enabled: root.composeCanEditSelected()
                                onClicked: root.composeDuplicateNode()
                            }

                            Button {
                                text: "Up"
                                implicitHeight: 28
                                font.pixelSize: 11
                                enabled: root.composeCanEditSelected()
                                onClicked: root.composeMoveNode(-1)
                            }

                            Button {
                                text: "Down"
                                implicitHeight: 28
                                font.pixelSize: 11
                                enabled: root.composeCanEditSelected()
                                onClicked: root.composeMoveNode(1)
                            }

                            Button {
                                text: "Delete"
                                implicitHeight: 28
                                font.pixelSize: 11
                                enabled: root.composeCanEditSelected()
                                onClicked: root.composeDeleteNode()
                            }
                        }
                    }

                    // Bead 05v.6: explicit recovery and reviewable promotion.
                    // Reset keeps the starter matching the current key,
                    // otherwise the TextField matrix; Save writes formatted
                    // JSON only to the known compositions directory.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#2b2430" }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 4

                            Button {
                                text: "Reset from example"
                                implicitHeight: 28
                                font.pixelSize: 11
                                onClicked: root.resetDraftFromExample()
                            }

                            Button {
                                text: "New blank"
                                implicitHeight: 28
                                font.pixelSize: 11
                                onClicked: root.newBlankDraft()
                            }
                        }

                        Button {
                            text: "Save to project"
                            implicitHeight: 28
                            Layout.fillWidth: true
                            enabled: !!root.composeDoc && root.composeValidateDocument(root.composeDoc) === ""
                            onClicked: root.saveDraftToProject()
                        }

                        Label {
                            visible: root.composeSaveStatus !== ""
                            text: root.composeSaveStatus
                            color: "#9d93a4"
                            font.family: "monospace"
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        // Stage pane: exact canvas on a scrollable calibrated viewport.
        ColumnLayout {
            SplitView.fillWidth: true
            SplitView.minimumWidth: 320
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                color: "#131017"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 4

                    Button {
                        text: "Catalog"
                        implicitHeight: 28
                        highlighted: !root.navigatorCollapsed
                        onClicked: root.navigatorCollapsed = !root.navigatorCollapsed
                    }
                    Button { text: "Fit"; implicitHeight: 28; highlighted: root.zoomMode === "fit"; onClicked: root.zoomMode = "fit" }
                    Button {
                        text: "100%"
                        implicitHeight: 28
                        highlighted: root.zoomMode === "manual" && root.zoom === 1
                        onClicked: { root.zoom = 1; root.zoomMode = "manual" }
                    }
                    Button { text: "−"; implicitHeight: 28; implicitWidth: 32; onClicked: root.zoomOut() }
                    Button { text: "+"; implicitHeight: 28; implicitWidth: 32; onClicked: root.zoomIn() }

                    Label {
                        text: root.zoomText
                        color: "#eee9f2"
                        font.family: "monospace"
                        font.pixelSize: 12
                        leftPadding: 4
                    }

                    // Bead 05v.5: composition path readout. Toolbar chrome
                    // lives outside stageWrap, so it never enters captures.
                    Label {
                        visible: root.isComposeMode() && !!root.composeDoc
                        text: root.composeSelectedPath() || "-"
                        color: "#9d93a4"
                        font.family: "monospace"
                        font.pixelSize: 11
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideMiddle
                    }

                    Label {
                        text: root.viewportWidth() + "×" + root.viewportHeight()
                        color: "#9d93a4"
                        font.family: "monospace"
                        font.pixelSize: 12
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }

                    Button {
                        text: "Inspector"
                        implicitHeight: 28
                        highlighted: !root.inspectorCollapsed
                        onClicked: root.inspectorCollapsed = !root.inspectorCollapsed
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#2b2430" }

            Flickable {
                id: stageFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: root.canvasContentWidth() * root.effZoom
                contentHeight: root.canvasContentHeight() * root.effZoom
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                // Calibration grid: backdrop only, behind the opaque preview,
                // so it never overlays the story or enters capture geometry.
                Canvas {
                    id: stageGrid
                    width: Math.max(stageFlick.width, stageFlick.contentWidth)
                    height: Math.max(stageFlick.height, stageFlick.contentHeight)
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = "#1a151f"
                        ctx.lineWidth = 1
                        const step = 32
                        ctx.beginPath()
                        for (let x = 0.5; x < width; x += step) {
                            ctx.moveTo(x, 0)
                            ctx.lineTo(x, height)
                        }
                        for (let y = 0.5; y < height; y += step) {
                            ctx.moveTo(0, y)
                            ctx.lineTo(width, y)
                        }
                        ctx.stroke()
                    }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                }

                Item {
                    id: stageWrap
                    width: root.viewportWidth()
                    height: root.viewportHeight()
                    visible: width > 0 && height > 0 && !root.isNestedFailed() && (!root.isComposeMode() || root.composeDoc)
                    scale: root.effZoom
                    transformOrigin: Item.TopLeft
                    x: Math.max(0, (stageFlick.width - width * scale) / 2)
                    y: Math.max(0, (stageFlick.height - height * scale) / 2)

                    Rectangle {
                        width: root.canvasContentWidth()
                        height: root.canvasContentHeight()
                        color: "#1c0e27"
                    }

                    Loader {
                        id: previewLoader
                        anchors.fill: parent
                    }

                    // Exact-canvas boundary drawn outside the preview bounds.
                    Rectangle { width: parent.width + 2; height: 1; x: -1; y: -1; color: "#2b2430" }
                    Rectangle { width: parent.width + 2; height: 1; x: -1; y: parent.height; color: "#2b2430" }
                    Rectangle { width: 1; height: parent.height; x: -1; y: 0; color: "#2b2430" }
                    Rectangle { width: 1; height: parent.height; x: parent.width; y: 0; color: "#2b2430" }
                }

                Label {
                    anchors.centerIn: parent
                    visible: !root.isComposeMode() && !root.story(root.selectedKey).viewport
                    text: "Select a story"
                    color: "#9d93a4"
                }

                Label {
                    anchors.centerIn: parent
                    visible: root.isComposeMode() && !root.composeDoc
                    text: "Start from blank or open a starter"
                    color: "#9d93a4"
                }

                Label {
                    anchors.centerIn: parent
                    visible: previewLoader.status === Loader.Loading || root.isNestedLoading()
                    text: "Loading " + root.canvasKey() + "…"
                    color: "#9d93a4"
                    font.family: "monospace"
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 48, 480)
                    visible: root.isNestedFailed()
                    spacing: 8

                    Label {
                        text: "Failed: " + root.canvasKey()
                        color: "#ff9d9d"
                        font.pixelSize: 13
                        font.bold: true
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Label {
                        text: root.nestedSourceOf(previewLoader.item) || root.previewUrl()
                        color: "#9d93a4"
                        font.family: "monospace"
                        font.pixelSize: 11
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Label {
                        text: root.nestedErrorOf(previewLoader.item)
                        visible: root.nestedErrorOf(previewLoader.item) !== ""
                        color: "#9d93a4"
                        font.family: "monospace"
                        font.pixelSize: 11
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8

                        Button {
                            text: "Reset"
                            onClicked: root.resetStory()
                        }

                        Button {
                            text: "Reload"
                            onClicked: root.applyCanvas()
                        }
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 48, 480)
                    visible: previewLoader.status === Loader.Error
                    spacing: 8

                    Label {
                        text: "Failed: " + root.canvasKey()
                        color: "#ff9d9d"
                        font.pixelSize: 13
                        font.bold: true
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Label {
                        text: root.isComposeMode() ? root.compositionUrl() : root.previewUrl()
                        color: "#9d93a4"
                        font.family: "monospace"
                        font.pixelSize: 11
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8

                        Button {
                            text: "Reset"
                            onClicked: root.resetStory()
                        }

                        Button {
                            text: "Reload"
                            onClicked: root.applyCanvas()
                        }
                    }
                }
            }
        }

        // Inspector pane.
        Rectangle {
            id: inspPane
            visible: !root.inspectorCollapsed
            SplitView.preferredWidth: 264
            SplitView.minimumWidth: 200
            color: "#131017"
            onWidthChanged: {
                if (!root.stateReady || !visible || width <= 0)
                    return
                root.inspectorWidth = Math.round(width)
                root.scheduleStateSave()
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Label {
                    visible: !root.isComposeMode()
                    text: root.story(root.selectedKey).title || root.selectedKey
                    color: "#eee9f2"
                    font.pixelSize: 13
                    font.bold: true
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Label {
                    visible: !root.isComposeMode()
                    text: root.selectedKey
                    color: "#9d93a4"
                    font.family: "monospace"
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                // Bead 05v.5: compose header names the document and the
                // selected node; story-mode labels above stay untouched.
                Label {
                    visible: root.isComposeMode() && !!root.composeDoc
                    text: (root.composeDoc ? String(root.composeDoc.key || "compose") : "compose") + "  ·  " + (root.selectedNodeId || "-")
                    color: "#eee9f2"
                    font.pixelSize: 13
                    font.bold: true
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Label {
                    visible: root.isComposeMode() && !!root.composeDoc
                    text: root.composeSelectedType() !== "" ? root.composeSelectedType() + "  " + root.composeSelectedPath() : "-"
                    color: "#9d93a4"
                    font.family: "monospace"
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                Label {
                    text: root.viewportWidth() + "×" + root.viewportHeight() + " @ " + root.zoomText
                    color: "#9d93a4"
                    font.family: "monospace"
                    font.pixelSize: 11
                    Layout.fillWidth: true
                }

                Label {
                    visible: !root.isComposeMode()
                    text: root.story(root.selectedKey).description || "No description yet."
                    color: "#9d93a4"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#2b2430" }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Repeater {
                        model: ["Story", "Controls", "Events", "Inspect", "Tasks", "Diagnostics"]
                        Button {
                            required property string modelData
                            text: modelData
                            implicitHeight: 28
                            Layout.fillWidth: true
                            font.pixelSize: 11
                            highlighted: root.inspectorTab === modelData
                            onClicked: root.inspectorTab = modelData
                        }
                    }
                }

                // Story tab: static selected-story metadata. In Compose mode
                // this tab edits the document, selected node, and links.
                ColumnLayout {
                    visible: root.inspectorTab === "Story" && !root.isComposeMode()
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        text: "component  " + (root.story(root.selectedKey).component || "-")
                        color: "#eee9f2"
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "variant  " + (root.story(root.selectedKey).variant || "-")
                        color: "#eee9f2"
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "source  " + (root.story(root.selectedKey).source || "-")
                        color: "#9d93a4"
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "tags  " + ((root.story(root.selectedKey).tags || []).join(", ") || "-")
                        color: "#9d93a4"
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    // Only paths already validated by the launcher open.
                    Flow {
                        visible: !!root.story(root.selectedKey).source || !!root.story(root.selectedKey).docs || (root.story(root.selectedKey).tests || []).length > 0
                        Layout.fillWidth: true
                        spacing: 4

                        Button {
                            text: "Source"
                            visible: !!root.story(root.selectedKey).source
                            implicitHeight: 28
                            font.pixelSize: 11
                            onClicked: root.openProviderPath(root.story(root.selectedKey).source)
                        }

                        Button {
                            text: "Docs"
                            visible: !!root.story(root.selectedKey).docs
                            implicitHeight: 28
                            font.pixelSize: 11
                            onClicked: root.openProviderPath(root.story(root.selectedKey).docs)
                        }

                        Repeater {
                            model: root.story(root.selectedKey).tests || []
                            Button {
                                required property var modelData
                                text: "Test: " + (modelData.label || "story")
                                implicitHeight: 28
                                font.pixelSize: 11
                                onClicked: root.openProviderPath(modelData.path)
                            }
                        }
                    }
                }

                // Bead 05v.5: compose detail. The Story tab edits the
                // document key/viewport, the selected node's descriptor
                // fields, and named links. Story-mode content above stays
                // untouched.
                Flickable {
                    visible: root.inspectorTab === "Story" && root.isComposeMode()
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: composeStoryColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: composeStoryColumn
                        width: parent.width
                        spacing: 8

                        Label {
                            visible: !root.composeDoc
                            text: "Start from blank or a starter to edit properties."
                            color: "#9d93a4"
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        ColumnLayout {
                            visible: !!root.composeDoc
                            width: parent.width
                            spacing: 8

                            Label {
                                text: "Composition"
                                color: "#9d93a4"
                                font.pixelSize: 11
                                Layout.fillWidth: true
                            }

                            Label {
                                text: "key"
                                color: "#9d93a4"
                                font.family: "monospace"
                                font.pixelSize: 11
                                Layout.fillWidth: true
                            }

                            TextField {
                                id: composeKeyField
                                Layout.fillWidth: true
                                implicitHeight: 28
                                text: root.composeDoc ? String(root.composeDoc.key || "") : ""
                                placeholderText: "kebab-case key"
                                enabled: !!root.composeDoc
                                onEditingFinished: root.composeSetDocKey(text)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                TextField {
                                    id: composeWidthField
                                    Layout.fillWidth: true
                                    implicitHeight: 28
                                    text: root.composeDoc ? String(root.viewportWidth()) : ""
                                    placeholderText: "width 320..3840"
                                    enabled: !!root.composeDoc
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    onEditingFinished: root.composeSetViewport(text, composeHeightField.text)
                                }

                                TextField {
                                    id: composeHeightField
                                    Layout.fillWidth: true
                                    implicitHeight: 28
                                    text: root.composeDoc ? String(root.viewportHeight()) : ""
                                    placeholderText: "height 240..2160"
                                    enabled: !!root.composeDoc
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    onEditingFinished: root.composeSetViewport(composeWidthField.text, text)
                                }
                            }

                            Label {
                                visible: root.composePropError !== ""
                                text: root.composePropError + " — last valid canvas kept"
                                color: "#ff9d9d"
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#2b2430" }

                            Label {
                                text: "Node  " + (root.selectedNodeId || "-")
                                color: "#9d93a4"
                                font.family: "monospace"
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }

                            Label {
                                visible: !!root.composeDoc && root.composePropFields(root.composeSelectedType()).length === 0
                                text: "Select a node to edit its properties."
                                color: "#9d93a4"
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Repeater {
                                model: (root.isComposeMode() && root.composeDoc) ? root.composePropFields(root.composeSelectedType()) : []

                                ColumnLayout {
                                    required property string modelData
                                    property var fieldSpec: root.composePropSpec(root.composeSelectedType(), modelData)
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Label {
                                        text: modelData
                                        color: "#9d93a4"
                                        font.family: "monospace"
                                        font.pixelSize: 11
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    ComboBox {
                                        visible: fieldSpec && (fieldSpec.type === "enum" || fieldSpec.type === "spacing")
                                        Layout.fillWidth: true
                                        implicitHeight: 28
                                        model: {
                                            if (!fieldSpec)
                                                return []
                                            if (fieldSpec.type === "spacing")
                                                return (root.composeTypes && root.composeTypes.tokens) || ["none", "xs", "sm", "md", "lg"]
                                            return fieldSpec.values || []
                                        }
                                        currentIndex: model.indexOf(String(root.composePropDisplay(root.selectedNodeId, root.composeSelectedType(), modelData)))
                                        onActivated: index => root.composeSetProp(root.selectedNodeId, modelData, model[index])
                                    }

                                    CheckBox {
                                        visible: fieldSpec && fieldSpec.type === "boolean"
                                        text: checked ? "On" : "Off"
                                        checked: root.composePropDisplay(root.selectedNodeId, root.composeSelectedType(), modelData) === true
                                        onToggled: root.composeSetProp(root.selectedNodeId, modelData, checked)
                                    }

                                    TextField {
                                        visible: fieldSpec && fieldSpec.type === "number"
                                        Layout.fillWidth: true
                                        implicitHeight: 28
                                        text: String(root.composePropDisplay(root.selectedNodeId, root.composeSelectedType(), modelData))
                                        placeholderText: {
                                            if (!fieldSpec)
                                                return ""
                                            let hint = "number"
                                            if (fieldSpec.min !== undefined && fieldSpec.max !== undefined)
                                                hint += " " + fieldSpec.min + ".." + fieldSpec.max
                                            return hint
                                        }
                                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                                        onEditingFinished: root.composeSetProp(root.selectedNodeId, modelData, text)
                                    }

                                    TextField {
                                        visible: fieldSpec && fieldSpec.type === "string"
                                        Layout.fillWidth: true
                                        implicitHeight: 28
                                        text: String(root.composePropDisplay(root.selectedNodeId, root.composeSelectedType(), modelData))
                                        placeholderText: "max " + ((fieldSpec && fieldSpec.maxLength) || 0) + " chars"
                                        onEditingFinished: root.composeSetProp(root.selectedNodeId, modelData, text)
                                    }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#2b2430" }

                            Label {
                                text: "Links  " + ((root.composeDoc && Array.isArray(root.composeDoc.links)) ? root.composeDoc.links.length : 0)
                                color: "#9d93a4"
                                font.pixelSize: 11
                                Layout.fillWidth: true
                            }

                            Repeater {
                                model: (root.composeDoc && Array.isArray(root.composeDoc.links)) ? root.composeDoc.links : []

                                RowLayout {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Label {
                                        text: String(modelData.from.node) + "." + String(modelData.from.event) + "  →  " + String(modelData.to.node) + "." + String(modelData.to.action)
                                        color: "#eee9f2"
                                        font.family: "monospace"
                                        font.pixelSize: 11
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }

                                    Button {
                                        text: "Delete"
                                        implicitHeight: 28
                                        font.pixelSize: 11
                                        onClicked: root.composeDeleteLink(index)
                                    }
                                }
                            }

                            Label {
                                text: "Source node"
                                color: "#9d93a4"
                                font.family: "monospace"
                                font.pixelSize: 11
                                Layout.fillWidth: true
                            }

                            ComboBox {
                                Layout.fillWidth: true
                                implicitHeight: 28
                                model: root.composeLinkEventNodes().map(row => row.id + "  ·  " + row.type)
                                currentIndex: {
                                    const ids = root.composeLinkEventNodes().map(row => row.id)
                                    return ids.indexOf(root.composeLinkFrom)
                                }
                                displayText: {
                                    const ids = root.composeLinkEventNodes().map(row => row.id)
                                    const at = ids.indexOf(root.composeLinkFrom)
                                    return at >= 0 ? root.composeLinkFrom : "pick source node"
                                }
                                onActivated: index => {
                                    root.composeLinkFrom = root.composeLinkEventNodes()[index].id
                                }
                            }

                            Label {
                                text: "Source event"
                                color: "#9d93a4"
                                font.family: "monospace"
                                font.pixelSize: 11
                                Layout.fillWidth: true
                            }

                            ComboBox {
                                Layout.fillWidth: true
                                implicitHeight: 28
                                model: root.composeLinkEvents(root.composeLinkFrom)
                                currentIndex: model.indexOf(root.composeLinkFromEvent)
                                displayText: root.composeLinkFromEvent !== "" ? root.composeLinkFromEvent : "pick source event"
                                onActivated: index => {
                                    root.composeLinkFromEvent = model[index]
                                }
                            }

                            Label {
                                text: "Target node"
                                color: "#9d93a4"
                                font.family: "monospace"
                                font.pixelSize: 11
                                Layout.fillWidth: true
                            }

                            ComboBox {
                                Layout.fillWidth: true
                                implicitHeight: 28
                                model: root.composeLinkActionNodes().map(row => row.id + "  ·  " + row.type)
                                currentIndex: {
                                    const ids = root.composeLinkActionNodes().map(row => row.id)
                                    return ids.indexOf(root.composeLinkTo)
                                }
                                displayText: {
                                    const ids = root.composeLinkActionNodes().map(row => row.id)
                                    const at = ids.indexOf(root.composeLinkTo)
                                    return at >= 0 ? root.composeLinkTo : "pick target node"
                                }
                                onActivated: index => {
                                    root.composeLinkTo = root.composeLinkActionNodes()[index].id
                                }
                            }

                            Label {
                                text: "Target action"
                                color: "#9d93a4"
                                font.family: "monospace"
                                font.pixelSize: 11
                                Layout.fillWidth: true
                            }

                            ComboBox {
                                Layout.fillWidth: true
                                implicitHeight: 28
                                model: root.composeLinkActions(root.composeLinkTo)
                                currentIndex: model.indexOf(root.composeLinkToAction)
                                displayText: root.composeLinkToAction !== "" ? root.composeLinkToAction : "pick target action"
                                onActivated: index => {
                                    root.composeLinkToAction = model[index]
                                }
                            }

                            Button {
                                text: "Add link"
                                implicitHeight: 28
                                Layout.fillWidth: true
                                enabled: root.composeCanAddLink()
                                onClicked: root.composeAddLink()
                            }

                            Label {
                                visible: root.composeLinkError !== ""
                                text: root.composeLinkError
                                color: "#ff9d9d"
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                }

                // Controls tab: grouped provider controls plus action buttons.
                // In Compose mode every node gets a labelled collapsible
                // section routed through the same preview entry points.
                Flickable {
                    visible: root.inspectorTab === "Controls" && !root.isComposeMode()
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: controlsColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: controlsColumn
                        width: parent.width
                        spacing: 8

                        Label {
                            visible: root.controlsOf(previewLoader.item).length === 0
                            text: "No controls reported by the provider adapter."
                            color: "#9d93a4"
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Repeater {
                            model: root.controlsOf(previewLoader.item)
                            ColumnLayout {
                                id: groupDelegate
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: 4

                                Label {
                                    text: groupDelegate.modelData.label || ("group " + groupDelegate.index)
                                    color: "#9d93a4"
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Repeater {
                                        model: groupDelegate.modelData.options || []
                                        Button {
                                            required property var modelData
                                            required property int index
                                            text: modelData.label
                                            implicitHeight: 28
                                            font.pixelSize: 11
                                            onClicked: root.activateControl(groupDelegate.index, index)
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#2b2430" }

                        Label {
                            text: "Actions"
                            color: "#9d93a4"
                            font.pixelSize: 11
                            Layout.fillWidth: true
                        }

                        Label {
                            visible: root.actionsOf(previewLoader.item).length === 0
                            text: "No actions reported by the provider adapter."
                            color: "#9d93a4"
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: root.actionsOf(previewLoader.item)
                                Button {
                                    required property var modelData
                                    required property int index
                                    text: (modelData && modelData.text !== undefined) ? String(modelData.text) : String(index)
                                    implicitHeight: 28
                                    font.pixelSize: 11
                                    onClicked: root.activateAction(index)
                                }
                            }
                        }
                    }
                }

                // Bead 05v.5: all-node controls. Every node stays visible as
                // a labelled collapsible section; the selected node expands
                // automatically and picking a header syncs tree selection.
                Flickable {
                    visible: root.inspectorTab === "Controls" && root.isComposeMode()
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: composeControlsColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: composeControlsColumn
                        width: parent.width
                        spacing: 4

                        Label {
                            visible: !root.composeDoc
                            text: "Start from blank or a starter to see node controls."
                            color: "#9d93a4"
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Repeater {
                            model: root.isComposeMode() ? root.composeNodeList() : []

                            ColumnLayout {
                                id: nodeSection
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 4

                                Button {
                                    Layout.fillWidth: true
                                    implicitHeight: 28
                                    text: (root.composeIsExpanded(modelData.id) ? "▾  " : "▸  ") + modelData.id + "  ·  " + modelData.type
                                    highlighted: root.selectedNodeId === modelData.id
                                    font.pixelSize: 11
                                    leftPadding: 8
                                    contentItem: Label {
                                        text: parent.text
                                        color: parent.highlighted ? "#0c0a0f" : "#eee9f2"
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        radius: 4
                                        color: parent.highlighted ? "#b994dc" : (parent.hovered ? "#1a151f" : "transparent")
                                    }
                                    onClicked: {
                                        root.selectedNodeId = modelData.id
                                        root.composeToggleExpanded(modelData.id)
                                    }
                                }

                                ColumnLayout {
                                    visible: root.composeIsExpanded(nodeSection.modelData.id)
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Label {
                                        text: "path  " + nodeSection.modelData.path
                                        color: "#9d93a4"
                                        font.family: "monospace"
                                        font.pixelSize: 11
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                        leftPadding: 8
                                    }

                                    Label {
                                        visible: root.composeControlGroups(nodeSection.modelData.id).length === 0 && root.composeActionEntries(nodeSection.modelData.id).length === 0
                                        text: "No controls or actions for this node."
                                        color: "#9d93a4"
                                        font.pixelSize: 12
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                        leftPadding: 8
                                    }

                                    Repeater {
                                        model: root.composeControlGroups(nodeSection.modelData.id)

                                        ColumnLayout {
                                            id: nodeGroup
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 4

                                            Label {
                                                text: nodeGroup.modelData.label || "controls"
                                                color: "#9d93a4"
                                                font.family: "monospace"
                                                font.pixelSize: 11
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                leftPadding: 8
                                            }

                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 4

                                                Repeater {
                                                    model: nodeGroup.modelData.options || []

                                                    Button {
                                                        required property var modelData
                                                        required property int index
                                                        text: modelData.label
                                                        implicitHeight: 28
                                                        font.pixelSize: 11
                                                        onClicked: root.activateControl(nodeGroup.modelData.flat, index)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Flow {
                                        visible: root.composeActionEntries(nodeSection.modelData.id).length > 0
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Repeater {
                                            model: root.composeActionEntries(nodeSection.modelData.id)

                                            Button {
                                                required property var modelData
                                                text: modelData.label
                                                implicitHeight: 28
                                                font.pixelSize: 11
                                                onClicked: root.activateAction(modelData.flat)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Events tab: bounded newest-last recorded intent/action log.
                ColumnLayout {
                    visible: root.inspectorTab === "Events"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            text: root.eventLog.length + " / " + root.eventCap
                            color: "#9d93a4"
                            font.family: "monospace"
                            font.pixelSize: 11
                            Layout.fillWidth: true
                        }

                        Button {
                            text: "Clear"
                            implicitHeight: 28
                            onClicked: root.eventLog = []
                        }
                    }

                    Label {
                        visible: root.eventLog.length === 0
                        text: "No events recorded yet."
                        color: "#9d93a4"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    ListView {
                        visible: root.eventLog.length > 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        model: root.eventLog

                        delegate: ColumnLayout {
                            required property var modelData
                            width: ListView.view.width
                            spacing: 0

                            Label {
                                text: "#" + parent.modelData.sequence + " " + parent.modelData.kind + " " + parent.modelData.name
                                color: "#eee9f2"
                                font.family: "monospace"
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }

                            Label {
                                text: root.payloadText(parent.modelData) + "  " + parent.modelData.storyKey
                                color: "#9d93a4"
                                font.family: "monospace"
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }

                            // Bead 05v.5: node identity stays visible in
                            // Compose mode; route hops name both ends.
                            Label {
                                visible: root.isComposeMode()
                                text: "node  " + (parent.modelData.nodeId || "-") + ((parent.modelData.targetNodeId || "") !== "" ? "  →  " + parent.modelData.targetNodeId : "")
                                color: "#9d93a4"
                                font.family: "monospace"
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                }

                // Inspect tab: settled tree via the Preview's own dumpTree().
                ColumnLayout {
                    visible: root.inspectorTab === "Inspect"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Button {
                            text: "Refresh"
                            implicitHeight: 28
                            Layout.fillWidth: true
                            onClicked: root.refreshInspection()
                        }

                        Button {
                            text: "Clear"
                            implicitHeight: 28
                            onClicked: { root.lastInspection = null; root.inspectionText = "" }
                        }
                    }

                    Label {
                        visible: root.inspectionText === ""
                        text: "No inspection yet — press Refresh."
                        color: "#9d93a4"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Flickable {
                        visible: root.inspectionText !== ""
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: inspectionLabel.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        Label {
                            id: inspectionLabel
                            width: parent.width
                            text: root.inspectionText
                            color: "#eee9f2"
                            font.family: "monospace"
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // Tasks tab: named operations, truthful status, bounded output.
                ColumnLayout {
                    visible: root.inspectorTab === "Tasks"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 4

                    Flow {
                        Layout.fillWidth: true
                        spacing: 4

                        Button {
                            text: root.isComposeMode() ? "Check compose" : "Validate"
                            implicitHeight: 28
                            font.pixelSize: 11
                            enabled: !root.taskRunning() && (!root.isComposeMode() || root.compositionFilePath !== "")
                            onClicked: root.runValidate()
                        }

                        Button {
                            text: "Capture"
                            implicitHeight: 28
                            font.pixelSize: 11
                            enabled: !root.taskRunning() && (!root.isComposeMode() || root.compositionFilePath !== "")
                            onClicked: root.runCapture()
                        }

                        Button {
                            text: "Run flow"
                            implicitHeight: 28
                            font.pixelSize: 11
                            enabled: root.launchFlowPath !== "" && !root.taskRunning()
                            onClicked: root.runLaunchFlow()
                        }

                        Button {
                            text: "Cancel"
                            implicitHeight: 28
                            font.pixelSize: 11
                            enabled: root.taskRunning()
                            onClicked: root.cancelTask()
                        }

                        Button {
                            text: "Clear"
                            implicitHeight: 28
                            font.pixelSize: 11
                            enabled: !root.taskRunning() && root.taskStatus !== "idle"
                            onClicked: root.clearTask()
                        }
                    }

                    Label {
                        visible: root.isComposeMode() && root.compositionFilePath === ""
                        text: "Save to project before checking or capturing the current composition."
                        color: "#9d93a4"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Label {
                        visible: root.launchFlowPath === ""
                        text: "Launch with --flow <flow.json> to enable Run flow for the validated flow."
                        color: "#9d93a4"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "status  " + root.taskStatus + (root.taskLabel !== "" ? "  " + root.taskLabel : "")
                        color: "#eee9f2"
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "argv  " + (root.taskArgv.length > 0 ? root.taskArgv.join(" ") : "-")
                        color: "#9d93a4"
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "exit  " + (root.taskExitCode < 0 ? "-" : root.taskExitCode)
                        color: "#9d93a4"
                        font.family: "monospace"
                        font.pixelSize: 11
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        visible: root.taskCapturePath !== "" && root.taskStatus === "succeeded"
                        Layout.fillWidth: true
                        spacing: 4

                        Button {
                            text: "Open"
                            implicitHeight: 28
                            font.pixelSize: 11
                            onClicked: root.openAbsPath(root.taskCapturePath)
                        }

                        Label {
                            text: root.taskCapturePath
                            color: "#9d93a4"
                            font.family: "monospace"
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }

                    Flickable {
                        visible: root.taskArgv.length > 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: taskOutputLabel.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        Label {
                            id: taskOutputLabel
                            width: parent.width
                            text: root.taskOutputText()
                            color: "#eee9f2"
                            font.family: "monospace"
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // Diagnostics tab: outer plus nested load state and recovery.
                ColumnLayout {
                    visible: root.inspectorTab === "Diagnostics"
                    Layout.fillWidth: true
                    spacing: 4

                    Label {
                        text: "loader  " + root.loaderStatusText(previewLoader.status)
                        color: "#eee9f2"
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "story  " + (root.nestedStatusOf(previewLoader.item) || "-")
                        color: "#eee9f2"
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "source  " + (root.nestedSourceOf(previewLoader.item) || "-")
                        color: "#9d93a4"
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "error  " + (root.nestedErrorOf(previewLoader.item) || "-")
                        color: root.isNestedFailed() ? "#ff9d9d" : "#9d93a4"
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: (root.isComposeMode() ? "compositionKey  " + root.canvasKey()
                            : "storyKey  " + (root.selectedKey || "-"))
                        color: "#9d93a4"
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "reset  " + root.resetGeneration
                        color: "#9d93a4"
                        font.family: "monospace"
                        font.pixelSize: 11
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "state  " + (root.stateDiagnostic || "ok")
                        color: root.stateDiagnostic !== "" ? "#ff9d9d" : "#9d93a4"
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "catalog  " + (root.catalogError || "ok")
                        color: root.catalogError !== "" ? "#ff9d9d" : "#9d93a4"
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Button {
                            text: "Reset story"
                            implicitHeight: 28
                            Layout.fillWidth: true
                            onClicked: root.resetStory()
                        }

                        Button {
                            text: "Reload canvas"
                            implicitHeight: 28
                            Layout.fillWidth: true
                            onClicked: root.applyCanvas()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Button {
                            text: "Reload Workbench"
                            implicitHeight: 28
                            Layout.fillWidth: true
                            onClicked: root.reloadWorkbench()
                        }

                        Button {
                            text: "Hard reload"
                            implicitHeight: 28
                            Layout.fillWidth: true
                            onClicked: root.hardReloadWorkbench()
                        }
                    }

                    Button {
                        text: "Restart process"
                        implicitHeight: 28
                        Layout.fillWidth: true
                        enabled: root.launcherPath !== ""
                        onClicked: root.restartProcess()
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
