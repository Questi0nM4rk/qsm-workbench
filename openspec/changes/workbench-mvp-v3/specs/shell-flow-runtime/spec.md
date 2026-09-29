## ADDED Requirements

### Requirement: Shared story and composition execution
The flow runtime SHALL execute solo stories through Preview and compositions through CompositionPreview while preserving each host's exact viewport, reset, actions, controls, events, and truthful loading status.

#### Scenario: Same semantic flow shapes
- **WHEN** one story flow and one composition flow use action and event assertions
- **THEN** both run through the same step protocol and report target-qualified results

### Requirement: Declared third-party event injection
The runtime SHALL allow a flow to emit only a target-declared event through the same recording and composition-routing path used by component intent, and SHALL mark the event origin as injected.

#### Scenario: Inject accepted event
- **WHEN** a composition flow emits `accepted` from the declared `trigger` node
- **THEN** its link opens the declared panel action and event evidence identifies the injected source and routed target

### Requirement: Named actions controls and input drivers
The runtime SHALL execute only declared named actions, labelled control options, and bounded unit-provided text/key drivers against the addressed story or stable composition node.

#### Scenario: Clear and rewrite field
- **WHEN** a flow clears a TextField through its named action, focuses it, writes bounded text, and presses Enter
- **THEN** the same live instance exposes the new text and records its accepted intent

### Requirement: Typed semantic observables
Preview units and composition adapters SHALL expose an allowlisted map of named semantic observables whose values are JSON scalar or bounded JSON data, without arbitrary reflection or child/property paths.

#### Scenario: Assert rollout state
- **WHEN** a flow expects the panel's declared `open` observable to equal true
- **THEN** the runtime reads that observable from the current node instance and reports the exact expected and actual values

### Requirement: Armed animation checkpoints
An opted-in story unit SHALL be able to synchronously pause a supplied QML Animation at a pre-armed named phase boundary, expose checkpoint evidence, and resume the same animation instance on command.

#### Scenario: Capture between two phases
- **WHEN** a flow arms `rollout.shell-revealed` before opening the rollout
- **THEN** the first phase completes, the sequence pauses before phase two, the stable frame can be captured, and continue resumes phase two

### Requirement: Default behavior remains uninstrumented
Unarmed checkpoints and units without integration capabilities SHALL preserve their existing production and preview behavior, and unsupported flow steps SHALL fail truthfully rather than approximating behavior.

#### Scenario: Ordinary preview open
- **WHEN** the rollout opens outside a flow with no checkpoint armed
- **THEN** its complete existing animation runs without pausing or waiting for test control
