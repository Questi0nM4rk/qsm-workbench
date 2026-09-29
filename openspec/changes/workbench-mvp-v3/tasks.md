## 1. Flow Contract

- [x] 1.1 Add the version 1 flow validator with strict target, step, path, bounds, non-executable-data, and semantic-first visual policy checks
- [x] 1.2 Add focused validator and CLI regression coverage for valid story/composition flows, unavailable shapes, unsafe paths/content, capture limits, and explicit baseline flags
- [x] 1.3 Add representative solo TextField and ShellBorder/Rollout flow documents with no baseline files yet

## 2. Shell Integration Contract

- [x] 2.1 Add a preview-owned integration controller with declared capability preflight, direct event injection evidence, typed observable reads, and bounded text/key drivers
- [x] 2.2 Expose the integration bridge consistently through Preview and CompositionPreview/CompositionNode with stable solo and node-qualified addressing
- [x] 2.3 Migrate only the flow-required input and rollout adapters to semantic observables/drivers and stable named actions, preserving ordinary behavior
- [x] 2.4 Add focused QML contract tests for capability discovery, injected event routing, action/control/input execution, observable assertions, reset, and unsupported-capability failure

## 3. Semantic Flow Execution

- [x] 3.1 Add the offscreen QML flow host and sequential state machine for story/composition loading, preflight, reset, emit, action, control, write, key, expect, expectEvent, and structured results
- [x] 3.2 Add the Node flow runner with bounded timeout/cancellation, temporary-host cleanup, target resolution, and deterministic concise output
- [x] 3.3 Prove the solo TextField clear/write/accept flow and direct ShellBorder/Rollout event-route flow through the real offscreen runtime

## 4. Deterministic Animation Checkpoints

- [x] 4.1 Add arm/reach/continue checkpoint state that synchronously pauses and resumes the supplied QML Animation without affecting unarmed execution
- [x] 4.2 Add one meaningful two-phase preview animation checkpoint to the ShellBorder/Rollout integration adapter and expose declared idle/checkpoint capabilities
- [x] 4.3 Add focused tests proving pause-before-phase-two, stable repeated paused frames, continuation on the same instance, bounded await failure, and unchanged ordinary animation

## 5. Scale-Aware Visual Comparison

- [x] 5.1 Add explicit render scale to the flow host with logical/physical size and screen-context metadata independent of workbench zoom
- [x] 5.2 Add PNG plus metadata capture after two queued paused/settled render passes and exact compatibility checks without resampling
- [x] 5.3 Add opt-in ImageMagick comparison with bounded fuzz/changed ratio, expected/actual/diff artifacts, and explicit baseline update restricted to the baseline root
- [x] 5.4 Approve only the representative ShellBorder/Rollout checkpoint baseline at its declared scale and add focused pass/failure/incompatible-metadata tests

## 6. Workflow Integration

- [x] 6.1 Add fixed `flow <file>` task-runner operation and `--flow <file>` launcher target opening with strict prevalidation
- [x] 6.2 Add one narrow Run flow Tasks action with existing status/output/cancel/evidence behavior and no runner logic in Workbench.qml
- [x] 6.3 Update README and implementation skill with the minimal shell-author integration object, checkpoint pattern, scale rules, baseline policy, and agent commands

## 7. Verification

- [x] 7.1 Run workbench flow/unit/integration tests, all example and flow validation, clean QML lint/load checks, capture comparisons, and OpenSpec strict validation
- [x] 7.2 Run focused shell integration/checkpoint tests and the complete qsm-shell validation suite
- [x] 7.3 Run the architecture gate or document the permitted no-baseline skip, then exercise solo/composition semantic flows, checkpoint pause/capture/continue, scale evidence, Tasks execution, diagnostics, and recovery in the live Wayland workbench
