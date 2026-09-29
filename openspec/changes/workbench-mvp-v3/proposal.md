## Why

The workbench can compose, inspect, and capture real shell integrations, but an
agent still cannot express a repeatable interaction contract such as “emit this
declared event, pause after the first animation phase, assert these live
properties, and compare the scaled frame.” Shell authors therefore reproduce
integration regressions manually or write one-off QML tests that do not share
the workbench environment.

## What Changes

- Add a bounded declarative flow document for solo stories and saved
  compositions, with named event emission, actions, controls, real text/key
  input, live-property assertions, expected event/route records, and reset.
- Add a shell-owned integration contract that lets preview units expose only
  typed observable properties and opt into deterministic named animation
  checkpoints without moving test logic into production components.
- Add an offscreen flow host that executes against the same Preview and
  CompositionPreview instances used by the workbench and captures the exact
  current frame.
- Add scale-aware visual baselines and ImageMagick comparison as an explicit
  opt-in step, with dimensions/metadata checks and expected/actual/diff
  artifacts on failure.
- Add fixed CLI/task operations and a narrow Tasks-tab entry so humans and
  agents run the same validated flows.
- Add author guidance and policy gates that prefer semantic integration
  assertions and permit screenshots only for meaningful visual or animation
  states; baseline updates are always explicit.

## Capabilities

### New Capabilities

- `integration-flow-documents`: Versioned, bounded, non-executable flow schema
  for story/composition targets, steps, assertions, checkpoints, and visual
  expectations.
- `shell-flow-runtime`: Shared solo-story/composition execution, declared event
  injection, named actions/controls, real input, typed observables, and
  deterministic opt-in animation checkpoint control.
- `visual-flow-capture`: Story-scale-aware capture, baseline metadata,
  comparison tolerance, failure artifacts, and explicit baseline updates.
- `integration-flow-workflows`: Fixed CLI/task/UI entry points plus concise
  shell-author and agent guidance that keeps integration coverage high-value.

### Modified Capabilities

None. No durable specifications have been promoted under `openspec/specs/`;
v3 adds contracts without changing canonical story or composition documents.

## Impact

- `qsm-workbench` gains flow validation, execution orchestration, baseline
  comparison, fixtures, tests, one named task operation, and concise UI/docs.
- `qsm-shell` gains a small preview-owned flow bridge, typed observable and
  animation-checkpoint hooks for units, scale-aware capture support, and
  focused QML contracts.
- ImageMagick is an optional visual-test system prerequisite already available
  in the development environment; semantic-only flows do not require it.
- Existing story registry, composition files, production component APIs, and
  default animation behavior remain unchanged.

## Critiques

### Devil's Advocate

A generic automation DSL could become a second programming language and make
tests less trustworthy than direct QML. Addressed by a closed step allowlist,
descriptor-declared endpoints, typed exact assertions, no expressions or
arbitrary property paths, and one shared runtime host.

### Future Archaeologist

Event, action, observable, checkpoint, scale, and baseline contracts could
drift across story units, composition adapters, and the Node validator.
Addressed by one unit-side `integration` object consumed by both hosts,
descriptor parity for composition nodes, runtime capability discovery, and
focused contract tests that reject unavailable steps before execution.

### Scope Sniper

Global animation time travel, arbitrary pointer scripting, every-device pixel
matrices, automatic baseline approval, and screenshots for every static
variant are not needed. V3 supports declared event/action/control/input steps,
exact live properties, phase-boundary checkpoints, explicit render scales, and
opt-in high-value screenshots only.
