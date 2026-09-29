import QtQuick

// Offscreen semantic flow host. The harness owns this state machine and the
// capability walk. A provider contributes exactly one file, its Adapter.qml,
// whose URL the runner injects: the adapter hosts the unit its catalog names
// and forwards that unit's `integration`, `controls` and `actions`, so every
// step below is answered through the adapter contract and never around it.
//
// A unit's `integration` is the whole drivability surface. `events` names
// what the host may inject, `observables` and `keys` map a name to the
// function that reads or presses it, `textDriver` writes, and `checkpoints`
// maps a name to `{ arm, reached, resume }` so the host can hold an animation
// at a declared boundary. Actions and controls travel the adapter's own
// `actions`/`triggerAction` and `controls`/`applyControl` doors.
//
// Sequential: a truthful loading wait, a full preflight before the first
// mutation, then every step in order through Qt.callLater plus bounded
// polling where loading or a checkpoint requires it. Never a document sleep.
// A step this host cannot execute FAILS and names its type. Exactly one
// QSM_FLOW_RESULT record is printed, then the process exits.
Item {
    id: host

    // Whole-line data replacement by scripts/flow-runner.mjs, so no document
    // text can become QML source, an import, or a command. Exactly one of
    // storyConfig / compositionDoc is set, matching flowData.target.
    property url adapterSource: "" // __ADAPTER_URL__
    property var flowData: null // __FLOW_DATA__
    property var storyConfig: null // __STORY_CONFIG__
    property var compositionDoc: null // __COMPOSITION_DOC__
    property bool verbose: false // __VERBOSE__

    readonly property bool isSolo: !!host.flowData && !!host.flowData.target
        && host.flowData.target.story !== undefined
    readonly property var adapter: adapterLoader.item
    readonly property var integration: host.has("integration") ? host.adapter.integration : null
    readonly property var logicalViewport: host.isSolo
        ? (host.storyConfig ? host.storyConfig.viewport : null)
        : (host.compositionDoc ? host.compositionDoc.viewport : null)
    readonly property string flowTheme: host.flowData && host.flowData.theme !== undefined
        ? String(host.flowData.theme) : "deep-night"
    readonly property real renderScale: host.flowData && host.flowData.scale !== undefined
        ? Number(host.flowData.scale) : 1
    readonly property int logicalWidth: host.asArray(host.logicalViewport).length === 2
        ? Number(host.asArray(host.logicalViewport)[0]) || 800 : 800
    readonly property int logicalHeight: host.asArray(host.logicalViewport).length === 2
        ? Number(host.asArray(host.logicalViewport)[1]) || 600 : 600
    readonly property real physicalWidthRaw: host.logicalWidth * host.renderScale
    readonly property real physicalHeightRaw: host.logicalHeight * host.renderScale
    readonly property int physicalWidth: Math.round(host.physicalWidthRaw)
    readonly property int physicalHeight: Math.round(host.physicalHeightRaw)

    width: host.physicalWidth
    height: host.physicalHeight

    property var eventLog: []
    property var stepResults: []
    property int stepIndex: 0
    property string phase: "boot"
    property int pollCount: 0
    // Small bounded polling only where waiting requires it: 50ms x 200.
    property int pollInterval: 50
    property int maxPolls: 200
    property var waitingStep: null
    property var armed: ({})

    // Arrays crossing a Loader arrive as QVariantList, for which
    // Array.isArray is false, and an adapter need not declare a property at
    // all. `in` is the one existence test, so a missing property reads as
    // absent instead of throwing.
    function has(field: string): bool {
        return host.adapter !== null && host.adapter !== undefined && field in host.adapter
    }

    function asArray(v): var {
        if (v === null || v === undefined)
            return [];
        if (Array.isArray(v))
            return v;
        if (typeof v.length === "number") {
            const out = [];
            for (let i = 0; i < v.length; i++)
                out.push(v[i]);
            return out;
        }
        return [];
    }

    // Flow names are stable kebab ids; a unit declares human labels, so every
    // lookup folds a name the same way and no declaration is written twice.
    function canonicalName(label): string {
        return String(label ?? "").toLowerCase().replace(/\s+/g, "-");
    }

    function indexOfName(list, name): int {
        const want = host.canonicalName(name);
        const items = host.asArray(list);
        for (let i = 0; i < items.length; i++) {
            const item = items[i];
            if (item === null || item === undefined)
                continue;
            if (typeof item === "string") {
                if (host.canonicalName(item) === want)
                    return i;
                continue;
            }
            if (item.trigger !== undefined && host.canonicalName(item.trigger) === want)
                return i;
            if (item.label !== undefined && host.canonicalName(item.label) === want)
                return i;
        }
        return -1;
    }

    // Exact semantic equality over bounded JSON values, not string display.
    // Length-indexed so QVariantList sequences compare like real arrays.
    function jsonEqual(a, b): bool {
        if (a === b)
            return true;
        if (typeof a !== typeof b)
            return false;
        if (a === null || b === null)
            return false;
        if (typeof a !== "object")
            return false;
        const aIsList = Array.isArray(a) || typeof a.length === "number";
        const bIsList = Array.isArray(b) || typeof b.length === "number";
        if (aIsList || bIsList) {
            if (!aIsList || !bIsList || a.length !== b.length)
                return false;
            for (let i = 0; i < a.length; i++) {
                if (!host.jsonEqual(a[i], b[i]))
                    return false;
            }
            return true;
        }
        const aKeys = Object.keys(a);
        const bKeys = Object.keys(b);
        if (aKeys.length !== bKeys.length)
            return false;
        for (let i = 0; i < aKeys.length; i++) {
            if (!Object.prototype.hasOwnProperty.call(b, aKeys[i]))
                return false;
            if (!host.jsonEqual(a[aKeys[i]], b[aKeys[i]]))
                return false;
        }
        return true;
    }

    function safeJson(value): string {
        try {
            return JSON.stringify(value);
        } catch (e) {
            return "<unserializable: " + e + ">";
        }
    }

    function flowTarget(): string {
        if (host.isSolo)
            return "story '" + String(host.flowData.target.story ?? "") + "'";
        return "composition '" + String(host.flowData.target.composition ?? "") + "'";
    }

    function describeStep(step): string {
        if (!step || typeof step !== "object")
            return "<missing>";
        let label = String(step.type ?? "<missing>");
        if (step.node !== undefined)
            label += " " + String(step.node);
        if (step.name !== undefined)
            label += " " + String(step.name);
        else if (step.event !== undefined)
            label += " " + String(step.event);
        else if (step.observable !== undefined)
            label += " " + String(step.observable);
        return label;
    }

    function nodeExists(id): bool {
        let found = false;
        function walk(node) {
            if (!node || found)
                return;
            if (String(node.id ?? "") === String(id))
                found = true;
            const children = host.asArray(node.children);
            for (let i = 0; i < children.length; i++)
                walk(children[i]);
        }
        if (host.compositionDoc)
            walk(host.compositionDoc.root);
        return found;
    }

    function recordEvent(origin, name, payload, node): void {
        const record = {
            "sequence": host.asArray(host.eventLog).length,
            "origin": String(origin ?? ""),
            "name": String(name ?? ""),
            "nodeId": node !== undefined && node !== null ? String(node) : "",
            "payload": payload !== undefined && payload !== null ? payload : {}
        };
        host.eventLog = host.asArray(host.eventLog).concat([record]);
    }

    function flowCapabilities(): var {
        const integration = host.integration;
        const groups = host.has("controls") ? host.asArray(host.adapter.controls) : [];
        const actions = host.has("actions") ? host.asArray(host.adapter.actions) : [];
        const names = function (list) {
            const out = [];
            for (let i = 0; i < list.length; i++) {
                const item = list[i];
                out.push(typeof item === "string"
                    ? host.canonicalName(item)
                    : host.canonicalName((item && item.trigger) !== undefined ? item.trigger : (item ? item.label : "")));
            }
            return out;
        };
        return {
            target: host.flowTarget(),
            drivable: integration !== null && integration !== undefined,
            events: integration ? host.asArray(integration.events).map(String) : [],
            actions: names(actions),
            controls: groups.map(function (group) {
                return {
                    "name": host.canonicalName(group && group.label),
                    "options": host.asArray(group && group.options).map(function (option) {
                        return host.canonicalName(option && option.label);
                    })
                };
            }),
            observables: integration && integration.observables
                ? Object.keys(integration.observables) : [],
            textDriver: !!(integration && typeof integration.textDriver === "function"),
            keys: integration ? Object.keys(integration.keys || {}) : [],
            checkpoints: integration ? Object.keys(integration.checkpoints || {}) : []
        };
    }

    // Read-only availability walk over every step shape, so a step this host
    // cannot execute is named before the first mutation rather than after it.
    function flowDescribeStep(step, index): string {
        const type = step && typeof step === "object" ? String(step.type ?? "") : "";
        const at = "step " + index + " (" + (type || "<missing>") + ")";
        if (type === "reset" || type === "awaitIdle")
            return "";
        if (!host.integration)
            return at + ": " + host.flowTarget() + " declares no unit integration, so it can be looked at and not driven";
        const node = String(step.node ?? "");
        if (!host.isSolo && type !== "armCheckpoint" && type !== "awaitCheckpoint"
            && type !== "continueCheckpoint") {
            if (node === "")
                return at + ": missing node";
            if (!host.nodeExists(node))
                return at + ": unknown node '" + node + "' for this composition target";
        }
        const caps = host.flowCapabilities();
        switch (type) {
        case "emit":
        case "expectEvent":
            if (caps.events.indexOf(String(step.event ?? "")) < 0)
                return at + ": " + host.flowTarget() + " declares no event '" + String(step.event ?? "") + "'";
            return "";
        case "action":
            if (host.indexOfName(host.has("actions") ? host.adapter.actions : null, String(step.name ?? "")) < 0)
                return at + ": " + host.flowTarget() + " declares no action '" + String(step.name ?? "") + "'";
            return "";
        case "control": {
            const resolved = host.resolveControl(String(step.group ?? ""), String(step.option ?? ""));
            return resolved.ok ? "" : at + ": " + resolved.error;
        }
        case "write":
            if (!caps.textDriver)
                return at + ": " + host.flowTarget() + " has no text driver";
            return "";
        case "key":
            if (caps.keys.indexOf(String(step.key ?? "")) < 0)
                return at + ": " + host.flowTarget() + " supports no key '" + String(step.key ?? "") + "'";
            return "";
        case "expect":
            if (caps.observables.indexOf(String(step.observable ?? "")) < 0)
                return at + ": " + host.flowTarget() + " exposes no observable '" + String(step.observable ?? "") + "'";
            return "";
        case "armCheckpoint":
        case "awaitCheckpoint":
        case "continueCheckpoint": {
            const name = String(step.name ?? "");
            const gate = caps.checkpoints.indexOf(name) < 0
                || typeof host.integration.checkpoints[name].reached !== "function"
                || typeof host.integration.checkpoints[name].resume !== "function";
            if (gate)
                return at + ": " + host.flowTarget() + " declares no usable checkpoint '" + name + "'";
            return "";
        }
        default:
            return at + ": not a step type this host executes";
        }
    }

    function flowPreflight(steps): var {
        const missing = [];
        const list = host.asArray(steps);
        for (let i = 0; i < list.length; i++) {
            const problem = host.flowDescribeStep(list[i], i);
            if (problem !== "")
                missing.push(problem);
        }
        return missing;
    }

    // Direct declared-event injection: the unit declares the event, and the
    // record carries the injected origin so a flow can never pass on evidence
    // a component did not produce.
    function flowEmit(step): var {
        const event = String(step.event ?? "");
        if (host.flowCapabilities().events.indexOf(event) < 0)
            return { ok: false, error: "undeclared event '" + event + "'" };
        const payload = step.payload !== undefined && step.payload !== null ? step.payload : {};
        host.recordEvent("injected", event, payload, step.node);
        return { ok: true };
    }

    // Name resolution only. Preflight walks this and must not touch the
    // target, so the two doors stay apart.
    function resolveControl(group, option): var {
        const groups = host.has("controls") ? host.asArray(host.adapter.controls) : [];
        const groupIndex = host.indexOfName(groups, group);
        if (groupIndex < 0)
            return { ok: false, error: "no control group '" + group + "'" };
        const optionIndex = host.indexOfName(host.asArray(groups[groupIndex] && groups[groupIndex].options), option);
        if (optionIndex < 0)
            return { ok: false, error: "control group '" + group + "' has no option '" + option + "'" };
        return { ok: true, groupIndex: groupIndex, optionIndex: optionIndex };
    }

    function flowApplyControl(step): var {
        const group = String(step.group ?? "");
        const option = String(step.option ?? "");
        const resolved = host.resolveControl(group, option);
        if (!resolved.ok)
            return { ok: false, error: resolved.error };
        if (!host.has("applyControl") || host.adapter.applyControl(resolved.groupIndex, resolved.optionIndex) !== true)
            return { ok: false, error: "the adapter refused control '" + group + "' option '" + option + "'" };
        return { ok: true };
    }

    function flowInvokeAction(step): var {
        const name = String(step.name ?? "");
        const index = host.indexOfName(host.has("actions") ? host.adapter.actions : null, name);
        if (index < 0)
            return { ok: false, error: "undeclared action '" + name + "'" };
        if (!host.has("triggerAction") || host.adapter.triggerAction(index) !== true)
            return { ok: false, error: "the adapter refused action '" + name + "'" };
        return { ok: true };
    }

    function flowWrite(step): var {
        if (typeof host.integration.textDriver !== "function")
            return { ok: false, error: "no text driver" };
        if (host.integration.textDriver(String(step.text ?? "")) !== true)
            return { ok: false, error: "text driver rejected the write" };
        return { ok: true };
    }

    function flowPressKey(step): var {
        const key = String(step.key ?? "");
        const press = host.integration.keys ? host.integration.keys[key] : null;
        if (typeof press !== "function")
            return { ok: false, error: "unsupported key '" + key + "'" };
        if (press() !== true)
            return { ok: false, error: "the unit refused key '" + key + "'" };
        return { ok: true };
    }

    function flowRead(step): var {
        const name = String(step.observable ?? "");
        const reader = host.integration.observables ? host.integration.observables[name] : null;
        if (typeof reader !== "function")
            return { ok: false, error: "unavailable observable '" + name + "'" };
        let value;
        try {
            value = reader();
        } catch (e) {
            return { ok: false, error: "observable '" + name + "' failed: " + e };
        }
        if (!host.jsonEqual(value, step.equals)) {
            return { ok: false,
                error: "expected " + host.safeJson(step.equals) + " but observed " + host.safeJson(value),
                expected: step.equals, actual: value };
        }
        return { ok: true, actual: value };
    }

    // expectEvent matching over the recorded events. Ordinary steps match by
    // event name, origin and source node; route steps match the source
    // event/node and optional target node through the route payload.
    function eventMatches(record, step): bool {
        if (!record || typeof record !== "object")
            return false;
        const origin = step.origin !== undefined ? String(step.origin) : "component";
        if (origin === "route") {
            if (String(record.origin) !== "route")
                return false;
            const from = record.payload ? record.payload.from : null;
            if (!from)
                return false;
            if (String(from.event) !== String(step.event))
                return false;
            if (!host.isSolo && String(from.node) !== String(step.node))
                return false;
            if (step.targetNode !== undefined) {
                const to = record.payload ? record.payload.to : null;
                if (!to || String(to.node) !== String(step.targetNode))
                    return false;
            }
            return true;
        }
        if (String(record.origin) !== origin)
            return false;
        if (String(record.name) !== String(step.event))
            return false;
        return host.isSolo || String(record.nodeId) === String(step.node);
    }

    function findEvent(step): var {
        const log = host.asArray(host.eventLog);
        for (let i = 0; i < log.length; i++) {
            if (host.eventMatches(log[i], step))
                return log[i];
        }
        return null;
    }

    function flowExpectEvent(step): var {
        const found = host.findEvent(step);
        if (found === null) {
            return { ok: false, error: "no recorded event '" + String(step.event ?? "") + "' from "
                + host.flowTarget() + " with origin '"
                + (step.origin !== undefined ? String(step.origin) : "component")
                + "' among " + host.asArray(host.eventLog).length + " records" };
        }
        return { ok: true, matched: found.sequence };
    }

    function flowArmCheckpoint(step): var {
        const name = String(step.name ?? "");
        const gate = host.integration.checkpoints ? host.integration.checkpoints[name] : null;
        if (!gate || typeof gate.arm !== "function")
            return { ok: false, error: "undeclared checkpoint '" + name + "'" };
        if (host.armed[name] === true)
            return { ok: false, error: "checkpoint '" + name + "' is already armed" };
        if (gate.arm() !== true)
            return { ok: false, error: "the unit refused to arm checkpoint '" + name + "'" };
        host.armed[name] = true;
        return { ok: true };
    }

    function flowCheckpointReached(step): bool {
        return host.armed[String(step.name ?? "")] === true
            && host.integration.checkpoints[String(step.name ?? "")].reached() === true;
    }

    function flowContinueCheckpoint(step): var {
        const name = String(step.name ?? "");
        const gate = host.integration.checkpoints ? host.integration.checkpoints[name] : null;
        if (host.armed[name] !== true)
            return { ok: false, error: "checkpoint '" + name + "' is not armed" };
        if (!gate || typeof gate.resume !== "function" || gate.resume() !== true)
            return { ok: false, error: "the unit cannot resume checkpoint '" + name + "'" };
        delete host.armed[name];
        return { ok: true };
    }

    function flowIdle(): bool {
        if (host.has("storyStatus") && String(host.adapter.storyStatus) !== "ready")
            return false;
        if (host.integration && typeof host.integration.idle === "function")
            return host.integration.idle() === true;
        return true;
    }

    function begin(): void {
        if (host.phase !== "boot")
            return;
        if (!host.flowData || typeof host.flowData !== "object") {
            host.finish(false, "no flow data: the runner must serialize flowData");
            return;
        }
        if (String(host.adapterSource) === "") {
            host.finish(false, "no provider adapter URL: the runner must serialize it");
            return;
        }
        if (host.isSolo && (!host.storyConfig || typeof host.storyConfig !== "object")) {
            host.finish(false, "no story configuration for story target");
            return;
        }
        if (!host.isSolo && (!host.compositionDoc || typeof host.compositionDoc !== "object")) {
            host.finish(false, "no composition document for composition target");
            return;
        }
        if (!isFinite(host.renderScale) || Math.abs(host.physicalWidthRaw - host.physicalWidth) > 0.000001
            || Math.abs(host.physicalHeightRaw - host.physicalHeight) > 0.000001) {
            host.finish(false, "flow scale/viewport does not produce integer physical dimensions: "
                + host.logicalWidth + "x" + host.logicalHeight + " at scale " + host.renderScale);
            return;
        }
        host.phase = "waiting-ready";
        host.pollCount = 0;
        poller.start();
    }

    // "ready" advances, "loading" keeps waiting, and any other status is a
    // terminal answer: polling an "empty" or "failed" target cannot help.
    function poll(): void {
        if (host.phase !== "waiting-ready" && host.phase !== "waiting-reset")
            return;
        if (adapterLoader.status === Loader.Error) {
            host.finish(false, "the provider adapter did not load: " + String(host.adapterSource));
            return;
        }
        const status = host.has("storyStatus") ? String(host.adapter.storyStatus) : "";
        if (status === "ready") {
            if (host.phase === "waiting-ready")
                host.preflight();
            else
                host.afterReset();
            return;
        }
        if (status !== "loading") {
            const detail = host.has("storyError") && String(host.adapter.storyError) !== ""
                ? String(host.adapter.storyError) : "target reports status '" + (status === "" ? "unknown" : status) + "'";
            host.finish(false, "target did not become ready: " + detail);
            return;
        }
        host.pollCount++;
        if (host.pollCount >= host.maxPolls) {
            host.finish(false, "target did not become ready within "
                + (host.pollInterval * host.maxPolls) + "ms (status: " + status + ")");
            return;
        }
        poller.start();
    }

    function preflight(): void {
        const missing = host.flowPreflight(host.asArray(host.flowData.steps));
        if (missing.length > 0) {
            host.finish(false, "preflight found unavailable capabilities: " + missing.join("; "));
            return;
        }
        host.phase = "running";
        host.stepIndex = 0;
        host.stepResults = [];
        Qt.callLater(function() { host.runNext(); });
    }

    function runNext(): void {
        if (host.phase !== "running")
            return;
        const steps = host.asArray(host.flowData.steps);
        if (host.stepIndex >= steps.length) {
            host.finish(true);
            return;
        }
        const step = steps[host.stepIndex];
        const type = step && typeof step === "object" ? String(step.type ?? "") : "";
        if (type === "awaitCheckpoint" || type === "awaitIdle") {
            host.startStepWait(step, type === "awaitIdle" ? "idle" : "checkpoint");
            return;
        }
        if (type === "reset") {
            // Reset rides the adapter's generation route, which rebuilds the
            // unit, and waits for the rebuilt tree to report ready again.
            host.phase = "waiting-reset";
            host.eventLog = [];
            host.armed = ({});
            if (host.has("resetGeneration"))
                host.adapter.resetGeneration = host.adapter.resetGeneration + 1;
            host.pollCount = 0;
            Qt.callLater(function() { poller.start(); });
            return;
        }
        const result = host.execute(step);
        host.stepResults = host.asArray(host.stepResults)
            .concat([Object.assign({ index: host.stepIndex, type: type }, result)]);
        if (!result.ok) {
            host.finish(false, "step " + host.stepIndex + " (" + type + ") failed: "
                + (result.error || "unknown failure"));
            return;
        }
        host.stepIndex++;
        Qt.callLater(function() { host.runNext(); });
    }

    function startStepWait(step, kind: string): void {
        if (host.verbose)
            console.log("QSM_FLOW_VERBOSE wait " + kind + " at step " + host.stepIndex);
        host.phase = "waiting-" + kind;
        host.waitingStep = step;
        host.pollCount = 0;
        stepPoller.start();
    }

    function pollStepWait(): void {
        if (host.phase !== "waiting-checkpoint" && host.phase !== "waiting-idle")
            return;
        const kind = host.phase === "waiting-checkpoint" ? "checkpoint" : "idle";
        const type = String(host.waitingStep.type ?? "");
        const ready = kind === "checkpoint" ? host.flowCheckpointReached(host.waitingStep) : host.flowIdle();
        if (ready) {
            host.phase = "running";
            host.stepResults = host.asArray(host.stepResults)
                .concat([{ index: host.stepIndex, type: type, ok: true }]);
            host.stepIndex++;
            Qt.callLater(function() { host.runNext(); });
            return;
        }
        host.pollCount++;
        if (host.pollCount >= host.maxPolls) {
            host.stepResults = host.asArray(host.stepResults)
                .concat([{ index: host.stepIndex, type: type, ok: false, error: kind + " wait timed out" }]);
            host.finish(false, "step " + host.stepIndex + " (" + type + ") failed: " + kind
                + " wait timed out after " + (host.pollInterval * host.maxPolls) + "ms");
            return;
        }
        stepPoller.start();
    }

    function afterReset(): void {
        host.phase = "running";
        host.stepResults = host.asArray(host.stepResults)
            .concat([{ index: host.stepIndex, type: "reset", ok: true }]);
        host.stepIndex++;
        Qt.callLater(function() { host.runNext(); });
    }

    function execute(step): var {
        if (!step || typeof step !== "object")
            return { ok: false, error: "step is not an object" };
        const type = String(step.type ?? "");
        if (host.verbose)
            console.log("QSM_FLOW_VERBOSE execute step " + host.stepIndex + " " + host.describeStep(step));
        switch (type) {
        case "emit":
            return host.flowEmit(step);
        case "control":
            return host.flowApplyControl(step);
        case "action":
            return host.flowInvokeAction(step);
        case "write":
            return host.flowWrite(step);
        case "key":
            return host.flowPressKey(step);
        case "expect":
            return host.flowRead(step);
        case "expectEvent":
            return host.flowExpectEvent(step);
        case "armCheckpoint":
            return host.flowArmCheckpoint(step);
        case "continueCheckpoint":
            return host.flowContinueCheckpoint(step);
        case "reset":
        case "awaitIdle":
        case "awaitCheckpoint":
            return { ok: false, error: "'" + type + "' is a waiting step, not a direct one" };
        default:
            return { ok: false, error: "'" + (type === "" ? "<missing>" : type) + "' is not a step type this host executes" };
        }
    }

    function finish(ok, error, capabilities): void {
        if (host.phase === "done")
            return;
        host.phase = "done";
        let events = [];
        try {
            events = JSON.parse(JSON.stringify(host.asArray(host.eventLog)));
        } catch (e) {
            events = [{ sequence: 0, origin: "note", name: "event evidence was not JSON-safe: " + e, nodeId: "", payload: {} }];
        }
        const result = {
            status: ok ? "pass" : "fail",
            key: host.flowData ? String(host.flowData.key ?? "") : "",
            target: host.isSolo
                ? { story: String(host.flowData.target.story ?? "") }
                : { composition: String(host.flowData.target.composition ?? "") },
            steps: host.asArray(host.stepResults),
            events: events,
            error: error !== null && error !== undefined ? String(error) : null,
            viewport: { width: host.logicalWidth, height: host.logicalHeight },
            scale: host.renderScale,
            physical: { width: host.physicalWidth, height: host.physicalHeight },
            theme: host.flowTheme,
            capabilities: capabilities !== null && capabilities !== undefined
                ? capabilities : host.flowCapabilities()
        };
        console.log("QSM_FLOW_RESULT " + JSON.stringify(result));
        Qt.exit(ok ? 0 : 1);
    }

    Timer {
        id: poller
        interval: host.pollInterval
        repeat: false
        onTriggered: host.poll()
    }

    Timer {
        id: stepPoller
        interval: host.pollInterval
        repeat: false
        onTriggered: host.pollStepWait()
    }

    Loader {
        id: adapterLoader
        anchors.fill: parent
        source: host.adapterSource
        onLoaded: {
            const peer = adapterLoader.item;
            if (!peer)
                return;
            peer.mode = host.isSolo ? "story" : "composition";
            peer.story = host.storyConfig;
            peer.composition = host.isSolo ? null : host.compositionDoc;
            peer.component = host.storyConfig ? String(host.storyConfig.component ?? "") : "";
            peer.variant = host.storyConfig ? String(host.storyConfig.variant ?? "") : "";
            peer.storyKey = host.isSolo ? String(host.flowData.target.story ?? "") : "";
            peer.viewportWidth = host.logicalWidth;
            peer.viewportHeight = host.logicalHeight;
            peer.resetGeneration = 0;
            peer.interactive = true;
        }
    }

    Connections {
        target: host.adapter
        function onEventRecorded(record) {
            host.recordEvent(record ? record.origin : "", record ? record.name : "",
                record ? record.payload : {}, record ? record.nodeId : undefined)
        }
    }

    Component.onCompleted: Qt.callLater(function() { host.begin(); });
}
