## ADDED Requirements

### Requirement: Provider-owned real component stories
The workbench SHALL render a selected story through the trusted provider adapter
using the provider's real component code and declared initial story data.

#### Scenario: Construct a story
- **WHEN** an author selects a valid provider story
- **THEN** the adapter constructs the real component host with its initial
  variant and exact declared viewport before `Component.onCompleted`

### Requirement: Neutral canvas observability
The provider canvas SHALL expose status, structured failure context, controls,
actions, declared capabilities, ordered event records, and inspection output
through a provider-neutral public contract.

#### Scenario: Component reports intent
- **WHEN** a provider component emits a declared public intent
- **THEN** the adapter records one ordered event with story key, semantic name,
  payload, and origin without workbench inspecting private child objects

### Requirement: Truthful replacement and recovery
The workbench SHALL clear a prior canvas before loading a replacement and SHALL
ignore stale callbacks from a prior provider canvas generation.

#### Scenario: Replacement story fails
- **WHEN** a selected provider story fails to construct
- **THEN** workbench shows that story's failure and does not present the prior
  successful story as current
