## ADDED Requirements

### Requirement: Named provider task operations
The workbench SHALL expose only provider-declared named operations for focused
checks, validation, capture, and flow execution, with each operation resolved
to validated argument arrays.

#### Scenario: Run a capture
- **WHEN** an author requests capture for a valid provider story or composition
- **THEN** workbench starts only the provider's validated capture operation and
  preserves status, raw output, artifact path, and cancellation behavior

### Requirement: No arbitrary command surface
Neither a provider manifest nor a workbench UI action SHALL accept a shell
string, executable override, arbitrary argument, or `sh -c` route.

#### Scenario: Reject arbitrary task input
- **WHEN** an author or manifest supplies an unknown operation or unsafe task
  argument
- **THEN** workbench rejects it before spawning a child process

### Requirement: Provider flow host
The workbench SHALL execute a provider flow through a fixed provider flow host
and the shared bounded semantic flow runner.

#### Scenario: Run provider semantic flow
- **WHEN** a flow targets a valid provider story or composition
- **THEN** the runner validates declared controls, actions, events, observables,
  and drivers before executing the provider host
