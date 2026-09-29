## 1. Project Foundation

- [x] 1.1 Replace copied-registry validation with canonical shell registry and metadata validation
- [x] 1.2 Add focused Node integration tests for valid, malformed, missing, and conflicting catalog inputs
- [x] 1.3 Add the Quickshell `shell.qml` entrypoint and switch the launcher to the installed runtime

## 2. Catalog And Canvas

- [x] 2.1 Implement canonical catalog loading, metadata merge, search, grouping, and direct selection
- [x] 2.2 Implement exact logical viewport rendering with scroll, 100%, Fit, and bounded zoom
- [x] 2.3 Add the smallest additive shell preview contract for status, controls, actions, inspect, reset, and explicit events
- [x] 2.4 Surface controls, actions, diagnostics, inspection, event records, and non-stale failure UI

## 3. Operations And Recovery

- [x] 3.1 Implement the fixed-argv task runner for selected tests, contract/full validation, capture, and known path actions
- [x] 3.2 Implement TERM/timeout/KILL cancellation, truthful lifecycle states, raw logs, and capture reveal
- [x] 3.3 Implement distinct story reset, canvas reload, Quickshell reload, and detached full restart

## 4. State And Daily Usability

- [x] 4.1 Persist and safely restore selected story, zoom, tab, window geometry, and panel dimensions
- [x] 4.2 Add bounded registry/metadata/selected-preview watching with debounced refresh
- [x] 4.3 Finish resizable/collapsible panels, keyboard navigation, shortcuts, and actionable metadata

## 5. Verification

- [x] 5.1 Run OpenSpec strict validation, workbench integration tests, QML lint/load checks, and canonical catalog validation
- [x] 5.2 Run focused selected-story test/capture flows and the complete `qsm-shell` validation suite
- [x] 5.3 Exercise catalog, interaction, controls, tasks, cancellation, diagnostics, persistence, and recovery in the live Wayland window
- [x] 5.4 Update concise run/development documentation and remove the obsolete copied registry
