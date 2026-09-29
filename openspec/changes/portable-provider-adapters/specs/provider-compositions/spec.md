## ADDED Requirements

### Requirement: Provider descriptor-driven compositions
The workbench SHALL validate and edit a composition only against the selected
provider's versioned descriptor, while the provider adapter owns fixed QML type
mapping and component-specific property translation.

#### Scenario: Compose provider components
- **WHEN** an author adds a valid declared type to a provider composition
- **THEN** the adapter constructs the provider's real component and the
  workbench exposes its declared controls, actions, and events by stable node ID

### Requirement: Non-executable composition data
A composition SHALL contain only bounded node IDs, declared type IDs, typed
allowlisted properties, bounded children, and named event-to-action links.

#### Scenario: Reject executable composition input
- **WHEN** a composition includes a QML path, JavaScript expression, callback,
  import, command, prototype key, or undeclared property
- **THEN** validation rejects the document before the adapter constructs QML

### Requirement: Explicit event and action routing
The adapter SHALL canonicalize only declared component intents and invoke only
declared named actions for a valid composition link.

#### Scenario: Route a declared event
- **WHEN** a component emits an adapter-declared event linked to a declared
  target action
- **THEN** the adapter performs exactly that action and workbench records the
  source event and routed action with their stable node IDs
