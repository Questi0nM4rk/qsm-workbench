## Why

qsm-workbench currently embeds qsm-shell paths, preview hosts, component type
names, and task commands. That makes the workbench a useful qsm-shell tool but
not the reusable local Quickshell component compositor it needs to become.

## What Changes

- Add a versioned, trusted provider-adapter contract for a component library.
- Load a provider's real QML story and composition hosts through that contract;
  workbench retains its canvas, controls, event log, inspection, persistence,
  flow execution, capture, and task supervision.
- Make catalog, composition descriptors, flow hosts, and named task operations
  provider-selected validated data rather than qsm-shell paths hardcoded in
  workbench core.
- Move qsm-shell preview harnesses behind a qsm-shell provider adapter, then
  retire `previews/units/` as each story host moves to the adapter.
- Make `qsm-workbench/.opencode/skills` and `.opencode/agents` the canonical
  workbench guidance; remove duplicate `.claude` projections.

## Capabilities

### New Capabilities
- `provider-adapters`: trusted, versioned library adapter registration and
  validation without executable manifest values.
- `provider-story-canvas`: provider-owned real-QML story host consumed through
  a workbench-neutral canvas and observability contract.
- `provider-compositions`: descriptor-driven, provider-owned composition
  runtime with bounded data documents and named event/action links.
- `provider-task-backends`: provider-declared named task operations for tests,
  captures, validation, and flows under existing workbench process supervision.

### Modified Capabilities
- None.

## Impact

The launcher, Workbench canvas loading, composition and flow runners, task
supervisor, test fixtures, documentation, and agent guidance change. qsm-shell
adds its provider adapter and removes shell-local preview harnesses only after
the workbench loads equivalent real component stories through that adapter.
