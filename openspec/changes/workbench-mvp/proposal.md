## Why

Developing `qsm-shell` currently requires moving between registry files, preview commands, tests, captures, and raw logs. The workbench spike proves native previewing works, but its copied catalog and weak failure handling make it unsafe as the default component-library workflow.

## What Changes

- Replace the copied story catalog with the canonical `qsm-shell` registry plus a metadata-only sidecar.
- Run the manager as one local Quickshell/QML application with searchable navigation and direct story opening.
- Render each story through the real `qsm-shell` preview at its exact logical viewport, with controls, reset, zoom, inspection, diagnostics, events, and recovery.
- Add named, cancellable test, validation, capture, and open-path tasks that preserve raw output.
- Persist the selected story and useful window/panel state locally, with safe fallback for malformed state.
- Add focused validation and integration checks only for contracts and failure paths likely to regress.
- Remove the copied `stories/scenarios.json` registry.

## Capabilities

### New Capabilities

- `story-catalog`: Canonical registry loading, metadata enrichment, search, grouping, direct selection, and path validation.
- `story-canvas`: Exact-size interactive preview, external controls/actions, inspect and event output, diagnostics, reset, reload, and recovery.
- `workbench-tasks`: Named test, validation, capture, and open-path operations with cancellation, truthful status, and raw logs.
- `local-workbench-state`: Local persistence of selection and layout preferences with bounded file watching and malformed-state recovery.

### Modified Capabilities

None.

## Impact

- Replaces the current Node-launched `qml/Workbench.qml` spike with a Quickshell configuration while retaining a thin Node preflight launcher.
- Reads `qsm-shell/previews/scenarios.json` and renders `qsm-shell/previews/Preview.qml`; a minimal additive preview contract may be added to `qsm-shell` without reverting its existing uncommitted work.
- Uses only Qt 6, Quickshell 0.3.1, Node.js built-ins, and existing `qsm-shell` commands; no server, database, web stack, or new runtime library is introduced.

## Critiques

### Devil's Advocate

The full PRD could turn a small catalog into a framework. Addressed by keeping one QML application, one task runner, four named task types, and the existing shell preview/CLI implementations; there is no generic plugin or command API.

### Future Archaeologist

Cross-repository ownership could become ambiguous. Addressed by making `qsm-shell` the sole owner of stories, units, component behavior, tests, and capture mechanics, while the workbench owns orchestration, display, persistence, and metadata only.

### Scope Sniper

Event instrumentation for every legacy story is not required to make the MVP useful. The MVP exposes explicit events where units provide the hook and never guesses arbitrary QML signals; full unit migration remains outside this change.
