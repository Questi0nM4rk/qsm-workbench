## ADDED Requirements

### Requirement: Exact interactive canvas
The workbench SHALL construct the real shell preview with initial story properties and SHALL preserve the declared logical viewport at every presentation zoom.

#### Scenario: Story is larger than available space
- **WHEN** the declared viewport does not fit in the canvas panel
- **THEN** the preview keeps its declared logical size and the surrounding viewport scrolls or scales it without changing preview inputs

### Requirement: Controls and actions
The workbench SHALL expose controls and actions declared by a migrated story unit without adding manager chrome to captures.

#### Scenario: Property-only state
- **WHEN** a unit declares a control option and the user activates it
- **THEN** the option is applied to the live unit and the preview remains interactive

### Requirement: Diagnostics and inspection
The workbench SHALL show selected-story loading status, nested load errors, raw diagnostics, and the settled inspection tree, and SHALL never present stale success as the current failed story.

#### Scenario: Unit fails to load
- **WHEN** the selected unit cannot be compiled or created
- **THEN** the workbench identifies the selected story and shows the available URL, location, and raw error instead of the previous story

### Requirement: Explicit event ordering
The workbench SHALL display explicitly recorded component intent and action events with deterministic sequence, name, payload, and story key, and SHALL NOT infer arbitrary QML signals.

#### Scenario: Recorded intent
- **WHEN** a hosted unit records an intent event
- **THEN** the event log appends a record after all records with lower sequence numbers

### Requirement: Recovery levels
The workbench SHALL provide distinct reset, canvas reload, Quickshell reload, and full process restart actions.

#### Scenario: Reset selected story
- **WHEN** the user activates reset
- **THEN** the selected story is reconstructed in its deterministic initial state without changing selection
