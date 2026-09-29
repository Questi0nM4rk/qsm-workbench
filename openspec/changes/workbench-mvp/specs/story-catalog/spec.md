## ADDED Requirements

### Requirement: Canonical story discovery
The workbench SHALL load every valid story from `qsm-shell/previews/scenarios.json` and SHALL NOT maintain a copied rendering registry.

#### Scenario: Shell adds a story
- **WHEN** a valid story is added to the canonical shell registry
- **THEN** the story appears in the workbench without editing a workbench registry

### Requirement: Metadata enrichment
The workbench SHALL merge optional presentation metadata without allowing it to replace component, unit, variant, or viewport fields.

#### Scenario: Metadata contains an unknown story
- **WHEN** metadata references a key absent from the canonical registry
- **THEN** validation fails with the unknown key identified

### Requirement: Story navigation
The workbench SHALL support text search, keyboard navigation, grouped display, and direct initial selection by stable story key.

#### Scenario: Direct opening
- **WHEN** the launcher receives a valid story key
- **THEN** that story is selected when the window opens

### Requirement: Actionable metadata
The workbench SHALL expose real actions for known source, documentation, and test paths rather than displaying inert labels.

#### Scenario: Open source
- **WHEN** the user activates the source action for a story with a valid source path
- **THEN** the path is opened using a named local operation
