## ADDED Requirements

### Requirement: Restart persistence
The workbench SHALL persist a versioned, bounded set of local UI preferences including selected story, zoom, selected bottom tab, and window or panel dimensions.

#### Scenario: Application restarts
- **WHEN** the workbench starts with valid saved state
- **THEN** it restores values that remain valid for the current catalog and display

### Requirement: Safe fallback
The workbench SHALL ignore malformed, unsupported, or out-of-range persisted values and use documented defaults.

#### Scenario: State JSON is malformed
- **WHEN** the saved state cannot be parsed
- **THEN** the workbench opens with defaults and presents a non-fatal diagnostic

### Requirement: Bounded file refresh
The workbench SHALL watch only the canonical registry, metadata, selected unit, and preview canvas inputs and SHALL debounce refreshes.

#### Scenario: Canonical registry changes
- **WHEN** the registry file changes repeatedly during one save operation
- **THEN** the catalog refreshes after a debounce interval without entering a reload loop
