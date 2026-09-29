## Context

The repository contains a Node/QML spike that passes a copied registry through process arguments to a Qt `qml` process. `qsm-shell` already owns the canonical registry, real preview host, unit controls, inspect tree, tests, and capture commands. The implementation must coexist with uncommitted shell work, stay local-only, and become usable in one session without introducing a second component runtime.

## Goals / Non-Goals

**Goals:**

- Deliver one understandable Quickshell/QML workbench that hosts the real shell preview.
- Keep registry, component behavior, tests, and capture implementation owned by `qsm-shell`.
- Make selection, failures, recovery, tasks, output, and persisted state truthful.
- Prefer direct bindings and named commands over abstraction layers.

**Non-Goals:**

- Generic support for arbitrary QML libraries, plugins, cloud features, collaboration, or telemetry.
- Automatic signal reflection, pixel-diff testing, a custom IPC protocol, or a compiled backend.
- Migrating every legacy inline shell story to a unit during this change.

## Decisions

### One Quickshell configuration

`qml/shell.qml` creates one `Workbench` window. The visible UI, catalog store, persistence, file watching, task process, logs, and recovery controls remain in a small set of QML files under one process. This is preferred over Node IPC or a service split because the product is single-user and local.

### Thin Node preflight

`scripts/workbench.mjs` resolves paths, validates the canonical registry and metadata, checks the preview contract, exports explicit environment values, and starts `quickshell --path qml/shell.qml`. It does not become an application backend. `--check` performs the same static validation without launching.

### Canonical data plus metadata sidecar

The workbench reads `qsm-shell/previews/scenarios.json` directly. `stories/metadata.json` may add only title, description, tags, source, docs, and structured tests. It cannot override rendering fields, and unknown metadata keys fail validation.

### Exact canvas through dynamic construction

The selected preview is created with initial properties through `Loader.setSource(url, properties)`. Its logical width and height always equal the declared viewport. A surrounding scroll area and presentation transform implement `100%` and `Fit`; zoom never changes preview inputs.

The existing shell preview receives only additive observability hooks where needed: story key, reset generation, load status/error, controls/actions access, inspect notification, and explicit event recording. Existing preview behavior and user changes remain intact.

### One named task runner

A single `Quickshell.Io.Process` runs validated argv arrays for selected unit tests, full shell validation, capture, and opening known paths. Starting another task is disabled while one runs. Cancellation sends TERM, followed by KILL after a timeout. Combined raw output and exit status remain visible. No arbitrary command string or `sh -c` is exposed.

### Small persistence surface

Reload persistence uses `PersistentProperties`; restart persistence uses one versioned JSON file under the workbench state directory. Only selection, zoom, selected bottom tab, and window/panel dimensions are stored. Invalid or stale values fall back to defaults.

### Focused verification

Node integration tests cover registry/metadata/path validation and CLI argument construction. QML is verified by lint/load smoke checks, existing `qsm-shell` tests, task execution, and live Wayland interaction. Visual constants and source shape are not tested.

## Risks / Trade-offs

- **Dirty `qsm-shell` files could be overwritten** -> apply only narrow additive patches after reading the current file and never reset or replace it wholesale.
- **Nested QML failures can be difficult to structure** -> expose the inner loader status and raw error string from the existing preview; show a failed state instead of retaining stale content.
- **Process descendants may survive TERM** -> existing shell runners remain the command boundary; task cancellation escalates to KILL and reports cancellation truthfully. Full process-group ownership is deferred unless live testing proves it necessary.
- **Automatic Quickshell reload can interrupt work** -> watch only registry, metadata, selected unit, and canvas files; debounce catalog refresh and keep explicit hard reload/restart controls.
- **Legacy stories lack external controls/events** -> they remain renderable; richer controls/events appear only when the canonical unit exposes them.

## Migration Plan

1. Add canonical validation and metadata, then delete the copied registry.
2. Switch the launcher to Quickshell and land the exact-size canvas/catalog.
3. Add observability, controls, tasks, persistence, and recovery in vertical slices.
4. Run focused checks, `qsm-shell` validation, and a live Wayland workflow.

Rollback is file-local: the old spike remains recoverable from git history once the repository has commits; no persisted project data or external API is migrated.

## Open Questions

None blocking. Process-group cancellation will be strengthened only if integration testing demonstrates orphaned children.
