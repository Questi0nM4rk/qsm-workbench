## Context

MVP v2 provides exact story/composition hosts, named controls/actions/events,
stable composition node IDs, inspection, offscreen capture, and fixed task
execution. Its tests can prove runtime contracts, but they cannot express a
reviewable end-to-end interaction flow or stop a multi-phase animation at a
meaningful boundary.

The shell already treats preview units as adapters: units expose controls,
actions, and an optional event recorder while Preview and CompositionPreview
own orchestration. QML Animation supports synchronous `pause()` and `resume()`
but exposes no safe global QML timeline seek. Existing captures use exact
logical viewports and a settled delay; workbench zoom is presentation-only.

V3 must speed up shell development rather than create another test framework.
The useful loop is: reproduce a meaningful integration with data, assert its
public state/events, optionally approve one visual frame, and rerun it from CLI
or the workbench. The flow must remain safe for agent generation and concise
for shell authors.

## Goals / Non-Goals

**Goals:**

- Use the same flow format and runtime for solo stories and compositions.
- Let third-party integration tests emit declared events directly, while still
  supporting named actions/controls and bounded text/key input.
- Observe only explicitly named live properties with typed JSON values.
- Pause a declared animation synchronously at an armed phase boundary, capture
  a stable frame, and resume the same instance.
- Capture at explicit render scale independently of workbench presentation
  zoom and compare only compatible baseline metadata.
- Make semantic assertions the default and visual assertions an explicit,
  high-value opt-in.
- Keep the shell-author contract small and preview-owned.

**Non-Goals:**

- Arbitrary QML/JavaScript execution, CSS-style selectors, unrestricted object
  reflection, shell commands, arbitrary pointer scripts, or action arguments.
- Global animation clock replacement, seeking to an arbitrary millisecond,
  controlling uninstrumented Behaviors, or freezing every application
  animation.
- Automatic baseline approval, screenshot matrices for every scale/theme, or
  replacing focused component/unit tests.
- A visual flow editor, recorder, cloud service, or production automation API.

## Decisions

### One bounded versioned flow document

A flow contains `version`, `key`, one target (`story` key or `composition`
path), optional `scale`/`theme`, and at most 64 ordered steps. Allowed steps are
`reset`, `emit`, `control`, `action`, `write`, `key`, `expect`, `expectEvent`,
`armCheckpoint`, `awaitCheckpoint`, `continueCheckpoint`, `capture`, and
`awaitIdle`. Every object uses strict field allowlists, bounded strings and
JSON-safe payloads, and project-relative paths that cannot escape known roots.

This is preferred over JavaScript test files because agent output stays
reviewable and non-executable. It is preferred over extending composition
documents because a fixture and its verification lifecycle have different
ownership and churn.

Every flow must include at least one `expect` or `expectEvent`. A `capture` step
must include a short `reason`, and at most four captures are allowed per flow.
This makes screenshot-only and combinatorial snapshot flows invalid by policy.

### Runtime capability discovery plus preflight

The Node validator proves document shape, target/path safety, baseline policy,
and descriptor-known composition endpoints. The QML host then loads the target
and preflights every runtime endpoint before executing step one. Missing solo
story actions, observables, drivers, or checkpoints fail as unavailable
capabilities rather than halfway through a flow.

Composition types continue to use `composition-types.json` plus the fixed
runtime allowlist. Solo preview units opt in through one `integration` object;
flow-targeted Qt Actions receive a stable `objectName`. Runtime capability
output is included in failure diagnostics and focused parity tests prevent
descriptor drift.

### Small shell-author integration object

A preview unit may expose:

```qml
readonly property var integration: ({
    events: ["accepted", "changed"],
    observables: {
        text: () => root.text,
        enabled: () => root.enabled
    },
    writeText: value => root.text = value,
    pressKey: key => root.pressIntegrationKey(key)
})
property var integrationController: null
```

Only properties worth asserting are named. Authors do not mirror geometry,
internal paint items, or every component property. Existing controls/actions
remain canonical. The host provides direct declared-event emission and event
recording, so units do not implement an event bus.

The initial migrated input units receive focused observables/drivers from their
existing public component APIs. Legacy inline stories remain unsupported until
they have a concrete flow, avoiding a broad migration.

### Declared event injection is first class

`emit` verifies that the target declares the event, records it through the same
host event path as a real component intent, and therefore exercises composition
links and route records. It does not invoke arbitrary signals or mutate the
source component. Real input behavior is tested separately with `write` and
`key`, which use a unit's bounded integration driver.

This preserves both useful test shapes: third-party flow contracts can inject
an event directly, while input-focused flows can prove that typing and Enter
produce that event naturally.

### Armed synchronous animation checkpoints

The preview host owns an `IntegrationController`. Before a trigger, a flow arms
a named checkpoint. An opted-in unit places a `ScriptAction` between animation
phases and calls `integrationController.checkpoint(name, sequence)`. If armed,
the controller synchronously calls `sequence.pause()`, records the checkpoint,
and blocks the next phase. Capture waits for two `Qt.callLater` render passes,
then `continueCheckpoint` calls `resume()` on that same sequence.

Unarmed checkpoints are no-ops, so production and ordinary preview animation
behavior is unchanged. `awaitIdle` uses a declared unit idle predicate or host
ready state with a bounded timeout. Exact midpoint seeking inside one
NumberAnimation is deferred; authors split a meaningful visual transition into
phases when a stable intermediate contract is valuable.

### Scale is capture input, not workbench zoom

`scale` is bounded and explicit in the flow. The offscreen root is sized to
`logical viewport × scale`, the preview remains at logical dimensions and is
transformed from its top-left origin, and the host reports the same scale in
its screen context. Workbench Fit/100% zoom never enters flow capture.

Each approved PNG has deterministic metadata containing flow/step, target,
logical viewport, render scale, physical dimensions, theme, Qt major/minor,
and renderer. Comparison rejects mismatched metadata or dimensions rather than
resampling. Multiple scale baselines are authored only when the flow explicitly
tests those scales.

### Node orchestration and ImageMagick comparison

`scripts/flow.mjs` validates documents. `scripts/flow-runner.mjs` creates one
temporary QML host, executes the flow offscreen, consumes structured result
records, and invokes ImageMagick only for capture steps. Exact semantic
assertions run in QML against the live instance. Visual comparison uses bounded
color fuzz and maximum changed-pixel ratio; failure preserves expected, actual,
diff, metadata, and a concise metric.

`--update-baseline` is explicit, writes only beneath the checked-in baseline
directory, and cannot be requested from inside a flow document. Agents may
produce actual/diff artifacts but never approve a baseline implicitly.

### Thin workbench integration

The task runner adds one validated `flow <file>` operation. The launcher accepts
`--flow <file>`, validates it, opens its target, and exposes the exact flow path
to QML. The Tasks tab adds only `Run flow`; all execution, comparison, and
diagnostics stay outside Workbench.qml. CLI remains the primary agent surface.

## Risks / Trade-offs

- **Checkpoint calls leak test concerns into units** → Keep the controller
  optional, preview-owned, and add checkpoints only at meaningful existing
  phase boundaries.
- **Functions inside `integration` are not statically inspectable** → Runtime
  preflight lists capabilities before execution and focused unit tests assert
  the declared contract.
- **Direct event emission can bypass component behavior** → Record injected
  origin explicitly and use `write`/`key` when the behavior producing the event
  is itself under test.
- **Pixel output varies across environments** → Pin renderer/theme/Qt metadata,
  require exact scale and dimensions, allow small explicit fuzz, and preserve
  diagnostics instead of auto-updating.
- **ImageMagick is a system dependency** → Require it only when a flow contains
  capture comparison; semantic flows remain dependency-free.
- **Flow DSL growth** → Version 1 has a closed step set and no conditions,
  loops, variables, selectors, expressions, arbitrary waits, or commands.
- **Live-property assertions become white-box tests** → Only unit-declared
  semantic observables are addressable; internal child/property paths are not.

## Migration Plan

1. Add the flow validator/CLI and representative valid/invalid documents.
2. Add the shared QML integration controller, runtime bridge, and initial input
   observables/drivers without changing default preview behavior.
3. Add the offscreen story/composition flow host and semantic execution.
4. Add scale-aware capture, metadata, comparison, and explicit baseline update.
5. Add fixed task/launcher/UI entry points and author/agent documentation.
6. Prove one solo input flow and one ShellBorder/Rollout checkpoint flow before
   inviting broader story migration.

Rollback is additive: remove flow entry points, hosts, fixtures, and optional
unit integration objects; story and composition rendering continue unchanged.

## Open Questions

None blocking. Arbitrary animation progress and richer typed event payload
schemas require a concrete future integration before admission.
