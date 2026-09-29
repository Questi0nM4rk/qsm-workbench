## Why

The current workbench makes isolated component development usable, but shell behavior is defined by components interacting inside layouts, menus, and edge surfaces. Authors still hand-write one-off QML fixtures to compare states or reproduce those interactions, and an AI agent has no stable data contract for producing the same setup a human can build in the UI.

## What Changes

- Add a bounded, versioned JSON composition document that humans and agents can create, validate, open, and reproduce.
- Add an allowlisted composition runtime for layouts, migrated input units, a menu container, and a shell-border/rollout container without evaluating arbitrary QML or JavaScript.
- Add a `Compose` workspace where authors add, duplicate, remove, reorder, select, and configure nodes while keeping the real preview interactive.
- Namespace controls, actions, diagnostics, inspection, and events by stable node ID so repeated instances remain independently observable.
- Add safe named event-to-action links between declared nodes without a general expression or binding language.
- Autosave one working draft, preserve it across reload/restart, and expose deterministic project files and CLI validation for agent-authored compositions.
- Ship useful starter compositions for a TextField size/state matrix, a menu form, and shell-border/rollout interaction.
- Extend focused capture and validation operations to compositions while preserving exact viewport rendering and workbench-free output.

## Capabilities

### New Capabilities

- `composition-documents`: Versioned schema, allowlists, bounded validation, deterministic files, draft persistence, and agent-facing CLI behavior.
- `composition-runtime`: Safe nested creation, layout/container semantics, per-node observability, named links, reset, diagnostics, and exact viewport rendering.
- `composition-editor`: The task-focused Compose workspace for tree editing, tokenized properties, node controls/actions, and truthful editing states.
- `composition-workflows`: Starter integrations, composition capture, focused checks, and promotion from a local draft to a reviewable project fixture.

### Modified Capabilities

None. The existing story catalog and story canvas remain intact; composition mode is additive.

## Impact

- `qsm-workbench` gains the document validator/CLI, draft and examples, composition selection state, and Compose UI.
- `qsm-shell` gains a narrow preview-owned composition runtime and allowlisted adapters; production shell components remain independent of the workbench.
- Existing story registry ownership does not change, no copied registry is introduced, and no server, database, plugin system, or new runtime dependency is added.

## Critiques

### Devil's Advocate

A composition editor can silently become a generic QML designer. Addressed by a closed node catalog, tokenized layout fields, typed properties, bounded depth/count, named links only, and no source paths, expressions, scripts, arbitrary properties, or arbitrary commands in documents.

### Future Archaeologist

Duplicating component contracts between a Node validator, QML runtime, and editor could drift. Addressed by one checked-in descriptor document consumed by validation and editing, with the runtime still enforcing its own fixed source allowlist as the execution boundary.

### Scope Sniper

Drag-and-drop, undo history, responsive authoring, general data binding, pixel diffs, file pickers, and exhaustive combinatorial generation are not required to prove the workflow. MVP v2 uses visible add/duplicate/delete/move controls, one autosaved draft, three layouts, a small component/container catalog, and three high-value starter compositions.
