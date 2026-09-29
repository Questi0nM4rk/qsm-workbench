## ADDED Requirements

### Requirement: Versioned bounded document
The system SHALL accept only version 1 composition documents with a stable key, finite viewport, one root node, unique stable node IDs, allowlisted node types, typed properties, valid child relationships, at most 64 nodes, and depth at most 8.

#### Scenario: Duplicate node ID
- **WHEN** a document contains two nodes with the same ID
- **THEN** validation fails with the duplicate ID and its document location identified

#### Scenario: Unknown type or property
- **WHEN** a document names an undeclared node type or property
- **THEN** validation fails without resolving a source path or constructing QML

### Requirement: Non-executable data contract
Composition documents SHALL NOT contain QML source paths, JavaScript, expressions, property paths, shell commands, or arbitrary action arguments.

#### Scenario: Agent supplies executable content
- **WHEN** a generated document includes a script, source URL, or undeclared field
- **THEN** the validator rejects it before launch or write

### Requirement: Shared descriptors
The editor and Node validator SHALL consume one descriptor document for editable types, fields, defaults, events, and actions, while the QML runtime SHALL retain a fixed checked-in execution allowlist.

#### Scenario: Descriptor declares unsupported runtime type
- **WHEN** a descriptor type has no runtime adapter
- **THEN** contract validation fails and the type is unavailable to the editor

### Requirement: Deterministic agent CLI
The project SHALL provide deterministic commands to validate a composition file and open a valid file directly in Compose mode.

#### Scenario: Agent opens generated composition
- **WHEN** an agent writes a valid JSON file and invokes the documented compose command
- **THEN** the workbench opens that exact document in Compose mode without modifying the canonical story registry

### Requirement: Recoverable working draft
The workbench SHALL autosave one versioned composition draft atomically after successful validation and SHALL preserve the last valid draft when an edit or disk content is invalid.

#### Scenario: Draft file becomes malformed
- **WHEN** the current draft cannot be parsed or validated
- **THEN** the last valid canvas remains available and the editor presents a non-fatal diagnostic with reset recovery
