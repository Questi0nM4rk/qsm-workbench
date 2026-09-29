## ADDED Requirements

### Requirement: Useful starter compositions
The project SHALL ship valid starter compositions for a TextField size/state matrix, a three-field menu form, and a ShellBorder/Rollout integration.

#### Scenario: Open TextField matrix
- **WHEN** the author opens the matrix fixture
- **THEN** several independently controllable TextFields render together for direct size and state comparison

### Requirement: Composition capture
The task runner SHALL capture a validated composition through the shell preview runtime at its declared viewport without workbench chrome.

#### Scenario: Capture menu form
- **WHEN** the author captures the menu form composition
- **THEN** a PNG of only the composed preview is written to the validated output path and can be opened through a named path action

### Requirement: Focused composition checks
The workbench and shell validation suites SHALL cover document validation, descriptor/runtime parity, nested construction, independent control routing, event identity, links, reset, and the specialized ShellBorder/Rollout host contract.

#### Scenario: Runtime adapter omitted
- **WHEN** a descriptor type is added without a corresponding runtime adapter
- **THEN** automated validation fails before the type can ship

### Requirement: Reviewable promotion
The workflow SHALL let an author persist a valid draft as a deterministic project composition file without automatically changing the canonical story registry.

#### Scenario: Promote draft
- **WHEN** the author chooses the named save/promote operation for a valid draft
- **THEN** a formatted JSON fixture is written to the known compositions directory for review and no story registry entry is added
