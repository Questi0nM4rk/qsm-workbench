## ADDED Requirements

### Requirement: Versioned bounded flow document
The system SHALL accept only version 1 flow documents with a stable key, exactly one story or composition target, bounded render settings, and at most 64 allowlisted ordered steps.

#### Scenario: Unknown step supplied
- **WHEN** a flow contains an undeclared step type or field
- **THEN** validation fails before a preview runtime is started

### Requirement: Non-executable flow data
Flow documents SHALL NOT contain QML source paths, JavaScript, expressions, arbitrary property paths, shell commands, selectors, loops, variables, or unbounded waits.

#### Scenario: Agent supplies property expression
- **WHEN** an assertion names `parent.children[0].opacity` or embeds executable text
- **THEN** the validator rejects the flow as non-declarative data

### Requirement: Declared target and endpoint validation
The validator and runtime preflight SHALL reject unavailable story/composition targets, node IDs, controls, actions, events, observables, drivers, and checkpoints before executing the first mutating step.

#### Scenario: Solo story lacks observable
- **WHEN** a flow expects `text` from a unit that does not declare that observable
- **THEN** preflight fails with the target and missing capability and no step runs

### Requirement: Semantic-first coverage policy
Every flow SHALL contain at least one semantic property or event assertion, every visual capture SHALL state a non-empty reason, and a flow SHALL contain no more than four capture steps.

#### Scenario: Screenshot-only flow
- **WHEN** a generated flow contains captures but no `expect` or `expectEvent`
- **THEN** validation rejects it with the semantic-first policy

### Requirement: Deterministic flow CLI
The project SHALL provide commands to validate and run a flow file, with baseline updates available only through an explicit CLI flag outside the document.

#### Scenario: Agent runs valid flow
- **WHEN** an agent invokes the documented run command for a valid semantic flow
- **THEN** the exact target and steps execute with structured pass/fail output and no registry modification
