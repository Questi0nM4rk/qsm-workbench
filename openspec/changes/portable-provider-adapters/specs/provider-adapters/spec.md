## ADDED Requirements

### Requirement: Explicit trusted provider selection
The launcher SHALL select exactly one provider root through an explicit local
argument or environment value and SHALL reject a missing, malformed, or unsafe
provider before Quickshell starts.

#### Scenario: Valid provider root
- **WHEN** an author launches workbench with a provider containing a valid
  versioned manifest and fixed adapter entrypoint
- **THEN** workbench receives that provider's validated catalog, descriptor,
  import roots, and capability declaration

#### Scenario: Unsafe manifest value
- **WHEN** a provider manifest contains a QML URL, source text, JavaScript,
  shell command, path escaping its provider root, or an unknown field
- **THEN** the launcher fails with the provider field that was rejected and
  starts no workbench process

### Requirement: Fixed provider layout
Each provider SHALL expose a fixed `workbench/` layout containing a manifest,
trusted `Adapter.qml`, canonical stories, and a composition descriptor. Optional
flow support SHALL use a fixed provider flow host path.

#### Scenario: Adapter path resolution
- **WHEN** the launcher accepts a provider root
- **THEN** it resolves executable adapter and flow host paths only from the
  fixed provider layout rather than a manifest-controlled QML source path

### Requirement: One provider per process
The workbench SHALL load one provider per process and SHALL reconstruct the
process when the selected provider changes.

#### Scenario: Switching providers
- **WHEN** an author selects a different provider after workbench has started
- **THEN** workbench does not mix QML module singletons or style backends from
  both providers in one live canvas
