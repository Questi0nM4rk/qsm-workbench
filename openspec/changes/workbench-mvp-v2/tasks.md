## 1. Composition Contract

- [x] 1.1 Add the source-free composition type descriptor and version 1 document validator with bounded IDs, viewport, node count, depth, properties, children, and links
- [x] 1.2 Add focused validator regression tests for valid examples, unknown fields/types, duplicate IDs, child policy, bounds, and executable-content rejection
- [x] 1.3 Add deterministic composition CLI validation and direct `--compose <file>` launch without changing story registry ownership
- [x] 1.4 Add valid TextField matrix, menu form, and ShellBorder/Rollout example documents

## 2. Shell Composition Runtime

- [x] 2.1 Add recursive composition preview/node QML with exact viewport, fixed runtime allowlist, tokenized Column/Row/Stack layout, and truthful reconstruction status
- [x] 2.2 Add migrated input leaf adapters and independent stable node registration, controls, actions, events, inspection, and reset
- [x] 2.3 Add Menu and specialized ShellBorder/Rollout containers with real child interaction and host contracts
- [x] 2.4 Add descriptor/runtime parity checks, safe named event-to-action routing, and focused QML contract tests

## 3. Compose Workspace

- [x] 3.1 Add Stories/Compose mode, composition tree, blank/starter states, and direct example/file opening while preserving the existing stage
- [x] 3.2 Add keyboard-reachable Add, Duplicate, Up, Down, Delete operations with deterministic IDs and immediate validated reconstruction
- [x] 3.3 Add descriptor-driven enum, boolean, bounded number, string, spacing, and viewport property editing with inline invalid-state recovery
- [x] 3.4 Add all-node collapsible controls/actions, selected-node synchronization, composition path, and named link editing
- [x] 3.5 Add atomic one-draft autosave/restore, last-valid fallback, reset-to-example, and reviewable save-to-project operation

## 4. Workflow Integration

- [x] 4.1 Add fixed-argv composition validation and chrome-free capture operations with output reveal
- [x] 4.2 Update concise README and implementation skill guidance for human and agent composition workflows

## 5. Verification

- [x] 5.1 Run workbench integration tests, QML lint/load smoke, descriptor/runtime parity, all example validation, and OpenSpec strict validation
- [x] 5.2 Run focused composition construction/control/link/capture flows and the complete qsm-shell validation suite
- [x] 5.3 Exercise authoring, repeated-node controls, links, autosave/restore, menu form, TextField matrix, ShellBorder/Rollout, diagnostics, capture, and recovery in the live Wayland window
