## ADDED Requirements

### Requirement: Allowlisted nested runtime
The composition preview SHALL recursively construct only fixed adapters for `column`, `row`, `stack`, `text-field`, `checkbox`, `switch`, `radio`, `slider`, `segmented`, `spin-box`, `menu`, and `shell-border-rollout`, using initial properties and exact document viewport dimensions.

#### Scenario: Three fields in a menu
- **WHEN** a valid menu document contains a column with three TextField nodes
- **THEN** all three real interactive units render in document order inside the menu container at the declared viewport

### Requirement: Tokenized layout
Layout and container spacing SHALL resolve from declared shell spacing tokens, and numeric dimensions SHALL remain within descriptor bounds.

#### Scenario: Author changes padding
- **WHEN** the author changes a container padding from `sm` to `lg`
- **THEN** the runtime applies the corresponding shell token without changing child component state

### Requirement: Per-node observability
The runtime SHALL expose controls, actions, events, loading failures, and inspection identity with the stable node ID for every constructed node.

#### Scenario: Repeated component controls
- **WHEN** a composition contains three TextField nodes and the author applies a control to the second node
- **THEN** only that node changes and the event or diagnostic identifies its ID

### Requirement: Safe named links
The runtime SHALL route a declared source event to a declared target action only when both endpoints exist in the descriptors and loaded node registry.

#### Scenario: Accepted field closes rollout
- **WHEN** a valid link routes a TextField `accepted` event to the surrounding shell-border/rollout `close` action
- **THEN** the rollout closes and the event log records both source node and routed target

### Requirement: Specialized shell integration
The `shell-border-rollout` adapter SHALL create the real preview-owned ScenePointer, ShellBorder host, and Rollout relationship and SHALL allow composed child content inside the Rollout.

#### Scenario: Rollout registers with border
- **WHEN** the rollout is opened in a composition
- **THEN** the ShellBorder receives the real visual and hit-region registrations and composed content remains interactive

### Requirement: Truthful reconstruction
Reset or document replacement SHALL destroy the prior node tree, clear stale node registries and events, and expose loading, ready, or failed status for the current document only.

#### Scenario: Replacement fails
- **WHEN** a newly selected composition cannot construct one node
- **THEN** the prior successful composition is not presented as current and the failure identifies the node ID and type
