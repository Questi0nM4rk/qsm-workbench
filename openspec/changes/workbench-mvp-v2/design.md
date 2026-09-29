## Context

MVP v1 hosts one canonical `qsm-shell` story and already provides exact viewport rendering, controls/actions, events, inspection, diagnostics, tasks, capture, persistence, and recovery. The missing workflow is composition: comparing several instances, putting real inputs inside a container, and exercising shell-owned relationships such as Rollout with ShellBorder. Current units are direct component proof harnesses, while legacy stories and shell surfaces require special host context.

The implementation must stay local, use Quickshell 0.3.1 and Qt/QML, coexist with dirty `qsm-shell` work, remain machine-authorable, and never turn document data into executable QML or JavaScript.

## Goals / Non-Goals

**Goals:**

- Let a shell author build a useful nested integration through visible controls rather than hand-written QML.
- Make the exact same composition reproducible from a small JSON file an AI agent can validate and generate.
- Reuse the existing stage, controls, events, inspect, task, capture, persistence, and recovery contracts.
- Support repeated component instances with independent identity and controls.
- Prove both ordinary component matrices and one real shell relationship.

**Non-Goals:**

- A general QML designer, drag-and-drop canvas, arbitrary source loader, expression language, property binding system, plugin SDK, or production layout format.
- Undo history, file picker, responsive breakpoint authoring, cloud sharing, pixel-diff infrastructure, or exhaustive combination generation.
- Making every legacy story composable in this change.

## Decisions

### One versioned composition document

A document contains `version`, `key`, `viewport`, `root`, and optional `links`. Every node contains a stable `id`, an allowlisted `type`, typed `props`, and children only when its descriptor permits them. Version 1 is bounded to 64 nodes, depth 8, unique kebab-case IDs, and a finite viewport range.

This is preferred over generated QML because it is deterministic, reviewable, safe to validate, and equally usable by UI and agent. It is preferred over extending `scenarios.json` because canonical stories remain shell-owned component fixtures rather than mutable workbench documents.

### Descriptor data plus an execution allowlist

`qsm-shell/previews/composition-types.json` describes user-facing names, node category, child policy, typed editable properties, defaults, controls, events, and actions. It contains no source paths. The Node validator and workbench editor consume this descriptor.

The QML runtime separately maps each known type to a checked-in Component or adapter. A modified descriptor therefore cannot load an arbitrary file. Initial types are:

- layouts: `column`, `row`, `stack`
- leaves: `text-field`, `checkbox`, `switch`, `radio`, `slider`, `segmented`, `spin-box`
- containers: `menu`, `shell-border-rollout`

Spacing and padding use named shell tokens (`none`, `xs`, `sm`, `md`, `lg`); numeric width/height fields are bounded. This is preferred over arbitrary property reflection because impossible combinations are prevented before runtime.

### Recursive preview-owned runtime

`CompositionPreview.qml` owns the same outward contract as `Preview.qml`: status/source/error, controls/actions, event recording, inspection, reset, and exact logical viewport. A recursive `CompositionNode.qml` instantiates only fixed adapters with initial properties through `Loader.setSource(url, properties)`, following Qt's lifecycle guidance.

Ordinary leaves reuse migrated preview units so their real controls and event hooks remain canonical. Layout and container adapters own child placement. `shell-border-rollout` is deliberately one specialized container: it creates the required ScenePointer, ShellBorder host, and Rollout relationship instead of pretending these host contracts are generic nesting.

### Flattened observability with node identity

The runtime registers every loaded node by ID. It flattens controls and actions into groups carrying `nodeId`, while preserving each unit's existing option model. Events add `nodeId` to the record. Duplicate component instances therefore remain distinguishable without changing production components.

### Named links, not bindings

Links have `{from: {node,event}, to: {node,action}}`. Both endpoints must be declared by descriptors. The runtime invokes a fixed adapter action and records the route; documents cannot contain code, arguments, expressions, or property paths. This supports useful routes such as `TextField.accepted -> shell-border-rollout.close` without creating a second programming language.

### Compose workspace extends existing panes

The left pane gains a `Stories | Compose` mode switch. Compose uses an overview-plus-detail tree with visible `Add`, `Duplicate`, `Up`, `Down`, and `Delete` actions. The center remains the exact interactive stage. The right inspector shows tokenized properties for the selected node and collapsible control/action groups for every node, with the selected node expanded. Existing Events, Inspect, Tasks, and Diagnostics remain one-home evidence surfaces.

No drag-and-drop is introduced: explicit reorder controls are keyboard reachable, deterministic, and sufficient for a bounded tree.

### One autosaved draft and deterministic project fixtures

The workbench autosaves one bounded draft to a separate versioned JSON state file and restores it after reload/restart. `compositions/examples/*.json` contains reviewable starter fixtures. `scripts/composition.mjs check <file>` validates any file, and `npm run workbench -- --compose <file>` opens a valid composition directly. The UI can reset from or write the known project draft path; a general file picker is deferred.

### Existing named task boundary is extended

The task runner adds validated composition check and capture operations using argv arrays. Composition capture renders through the preview-owned runtime at the document viewport and excludes workbench chrome. No arbitrary command surface is added.

### Focused verification

Node tests cover schema boundaries, allowlist failures, duplicate IDs, child policy, depth/count, links, CLI opening, and task argv. QML checks cover construction, independent per-node control routing, namespaced events, reset, menu children, and ShellBorder/Rollout registration. The live gate exercises editor mutation, autosave/restore, controls, links, capture, and recovery. Visual constants are not unit tested.

## Risks / Trade-offs

- **Descriptor/runtime drift** -> contract tests require every descriptor type to have a runtime adapter and every declared property/action to be accepted.
- **Recursive QML lifecycle errors** -> pass initial properties at creation, cap depth/count, destroy the old tree before reconstruction, and expose node-specific failure diagnostics.
- **Units are proof harnesses, not universal application widgets** -> use them only as preview adapters; do not move composition concerns into production components.
- **Menu does not semantically turn arbitrary children into menu rows** -> the adapter is explicit that non-row children are layout content; keyboard row selection remains available only for real ListRows.
- **ShellBorder/Rollout is context-heavy** -> keep one specialized adapter rather than abstracting the host protocol prematurely.
- **Autosave can overwrite a useful draft** -> validate before write, write atomically, preserve the last valid draft on invalid edits, and provide reset-to-example rather than destructive implicit fallback.
- **One monolithic Workbench file grows further** -> add only composition-focused QML files for the recursive runtime/editor model; do not split unrelated MVP v1 behavior during this change.

## Migration Plan

1. Add descriptor, validator, examples, and CLI without changing story mode.
2. Add the shell composition runtime and contract tests.
3. Add Compose mode, tree editing, properties, per-node controls, links, and draft persistence.
4. Add composition capture/tasks and starter workflow documentation.
5. Run focused automation, then have the owner exercise the full live Wayland workflow.

Rollback is additive: remove Compose entry points and composition files; existing story registry, preview host, tests, and MVP v1 state remain valid.

## Open Questions

None blocking. Additional node types and richer action payloads are admitted only after a concrete integration fixture requires them.
