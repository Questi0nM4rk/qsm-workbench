## ADDED Requirements

### Requirement: Dedicated Compose workspace
The workbench SHALL provide a visible `Stories | Compose` mode switch while preserving the existing navigator, exact stage, inspector, and evidence regions.

#### Scenario: Enter Compose mode
- **WHEN** the author activates Compose
- **THEN** the composition tree and editing actions replace the story catalog while the center stage and evidence surfaces remain available

### Requirement: Explicit tree editing
The editor SHALL provide keyboard-reachable Add, Duplicate, Up, Down, and Delete actions with immediate validated preview feedback and without requiring drag-and-drop.

#### Scenario: Duplicate selected field
- **WHEN** the author duplicates a selected TextField
- **THEN** a sibling with a unique deterministic ID appears after it and renders independently

### Requirement: Typed property editing
The editor SHALL render property controls from descriptors using closed enums, booleans, bounded numbers, short strings, and spacing tokens, and SHALL prevent invalid values from replacing the last valid document.

#### Scenario: Out-of-range dimension
- **WHEN** the author enters a width beyond the descriptor maximum
- **THEN** the value is rejected inline and the last valid canvas remains unchanged

### Requirement: All-node control visibility
The inspector SHALL show labelled collapsible controls and actions for every loaded node, automatically expanding the selected node's group.

#### Scenario: Select repeated node
- **WHEN** the author selects the `email` TextField in the tree
- **THEN** its property editor and `email` control group become the active detail without hiding controls for sibling nodes

### Requirement: Named link editing
The editor SHALL create and delete links using only selectable declared nodes, events, and actions.

#### Scenario: Target has no matching action
- **WHEN** the selected target node does not declare the requested action
- **THEN** that action is unavailable rather than accepted and failed later

### Requirement: Honest editing states
Compose SHALL provide intentional blank, loading, invalid, failed, and restored states and SHALL never discard the last valid draft without an explicit reset.

#### Scenario: New blank composition
- **WHEN** no draft exists
- **THEN** Compose offers a blank start and the three starter fixtures without showing an empty unexplained canvas
