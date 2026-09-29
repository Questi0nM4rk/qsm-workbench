## Context

The current workbench is a native Quickshell application, but its launcher,
canvas, composition interpreter, flow host, task supervisor, test fixtures, and
agent guidance assume qsm-shell's repository layout and preview files. The
result cannot inspect a second component library without copying qsm-shell
behavior or weakening its command and QML loading boundaries.

The target is one local workbench process that composes real components from a
selected trusted Quickshell provider. qsm-shell becomes the first provider and
retires its temporary `previews/units` hosts after feature-equivalent provider
stories exist.

## Goals / Non-Goals

**Goals:**

- Keep the workbench reusable across local Quickshell/QML component libraries.
- Keep stories, compositions, controls, actions, event records, flows, capture,
  inspection, and named tasks working through a stable provider boundary.
- Keep component code in its library and render that exact code in workbench.
- Keep manifests and composition documents non-executable and bounded.
- Make `qsm-workbench/.opencode/skills` and `.opencode/agents` the only
  canonical workbench agent guidance.

**Non-Goals:**

- Sandboxing untrusted QML providers, cloud sharing, a plugin marketplace, or
  generic support for non-QML UI toolkits.
- Automatic introspection of arbitrary QML signals/properties.
- A second component implementation, copied story registry, arbitrary command
  execution, arbitrary QML URLs, QML source strings, JavaScript expressions, or
  style merging between providers.

## Decisions

### Trusted provider root

The launcher selects one explicit provider root. A provider has a fixed
`workbench/` directory containing `provider.json`, `Adapter.qml`, `stories.json`,
`composition-types.json`, and optional `FlowHost.qml`. The manifest names only
data files within that root and capability flags; it never names a QML source
path or command. `Adapter.qml` is executable trusted project code loaded from
the fixed provider location.

An explicit root is simpler than a global plugin registry and makes local trust
visible in the launch command. QML cannot safely sandbox arbitrary imports, so
a manifest must not turn untrusted input into `Loader.source`.

### Adapter owns executable mapping

`Adapter.qml` maps stable story and composition type IDs to literal internal
components, provides initial properties, controls, actions, event
canonicalization, semantic observables, bounded drivers, and diagnostics. The
workbench receives the adapter's declared public contract; it never reaches
into a component's private object IDs or infers arbitrary signals.

This replaces qsm-shell's `Preview.qml`, `CompositionPreview.qml`,
`CompositionNode.qml`, and `FlowHost.qml` as a hardcoded dependency. A provider
may use one host for all modes or separate fixed hosts, but each returns the
same canvas contract.

### Neutral canvas and event contract

Workbench owns catalog UI, exact viewport/zoom presentation, reset, event log,
inspection panel, persistence, and error presentation. A provider canvas
receives immutable story/composition data plus reset generation and returns
`loading`, `ready`, or `failed`; controls, actions, capabilities, inspection,
and ordered event records use the existing explicit bridge shape.

Initial story properties are applied at construction. Loader replacement clears
the prior canvas first and a generation ID rejects stale callbacks. Focus is
forwarded deliberately because `Loader` is a focus scope.

### Data-only stories and compositions

The provider owns its canonical `stories.json`; workbench metadata remains a
separate sidecar and cannot change rendering. Compositions remain typed,
bounded JSON trees. Their descriptor is provider-owned, while the workbench
owns generic document validation, editing, links, persistence, and display.
The adapter is the only code that maps a declared type to QML.

This preserves one source of truth without allowing JSON to inject code.

### Named provider tasks

The provider manifest advertises a small operation vocabulary (`validate`,
`capture`, `flow`, and focused checks) with fixed argv templates implemented by
the workbench launcher, not arbitrary command text. Workbench retains process
group ownership, raw output, cancellation, timeout, and status behavior.

Quickshell `Process.command` and Node spawn use argument arrays; no provider or
workbench path may expose `sh -c`.

### qsm-shell migration

Create the qsm-shell provider under `qsm-shell/workbench/` first. Move one
component family at a time from `previews/units` into its adapter story host,
with equivalent composition and flow capability where the component supports
one. After the workbench validates and renders the provider story, remove the
old shell unit and its Preview branch. `previews/` disappears when the final
legacy story is migrated.

### Canonical agent guidance

Move workbench skill and agent source files to `qsm-workbench/.opencode/skills`
and `.opencode/agents`. Remove `.claude` duplicates rather than maintaining two
sources. Generic skills use provider-neutral language; qsm-shell adapter work
gets one explicit provider skill.

## Risks / Trade-offs

- [Provider QML can affect process-global imports/singletons] -> One selected
  provider per workbench process; require unique module URIs and restart to
  change provider.
- [Adapter contract becomes broad] -> Start with story canvas, descriptor,
  capability bridge, and named tasks; add a method only when two providers need
  it.
- [Migration temporarily has two paths] -> Delete each old harness immediately
  after its adapter replacement passes; track only remaining migrations.
- [Existing qsm-shell dirty work collides] -> Do adapter work in isolated
  worktrees and integrate narrow reviewed diffs.
- [Provider task templates become an execution surface] -> Validate operation
  names and all path/value arguments, keep executable and argv prefix fixed in
  workbench code, and reject shell syntax.

## Migration Plan

1. Add provider manifest parsing and trusted-root validation with a synthetic
   provider fixture.
2. Add the neutral provider canvas/bridge and make launcher/catalog selection
   provider-aware without changing qsm-shell behavior.
3. Move composition, flow, and task loading behind the adapter contract.
4. Build the qsm-shell provider; migrate stories by active component family and
   delete their shell units as each passes workbench validation and live review.
5. Move canonical workbench skills/agents into `.opencode`, update guidance,
   remove `.claude` duplicates, and validate qsm-shell plus a synthetic second
   provider.

Rollback before step 4 selects the existing qsm-shell provider path. After a
family migration, restore only that deleted harness from version control if its
adapter cannot construct the real component.

## Open Questions

- Should provider roots be selected only by CLI/environment initially, or also
  remembered in local workbench state?
- Which first non-qsm-shell fixture best proves the provider boundary without
  creating a second maintained component library?
