## ADDED Requirements

### Requirement: Fixed flow task boundary
The task supervisor SHALL expose one validated `flow` operation using argv arrays, bounded cancellation, and no arbitrary command surface.

#### Scenario: Run flow from Tasks
- **WHEN** the author runs the validated current flow from the Tasks tab
- **THEN** status, argv, semantic results, capture paths, and failure diagnostics appear through the existing task evidence surface

### Requirement: Direct flow launch
The launcher SHALL accept a valid `--flow <file>` argument, open that flow's exact story or composition target, and expose only the validated flow path to the workbench task action.

#### Scenario: Open composition flow
- **WHEN** an agent launches a flow targeting a saved composition
- **THEN** Compose opens that document and Run flow targets the same validated file

### Requirement: Focused author workflow
Documentation SHALL define the minimal shell-unit integration object, stable action naming, semantic observable selection, event injection semantics, animation checkpoint mechanics, scale behavior, and criteria for adding visual baselines.

#### Scenario: Author adds meaningful checkpoint
- **WHEN** a shell author has a two-phase visual transition with a contract-worthy intermediate state
- **THEN** the guidance shows one optional controller property and one named phase checkpoint rather than a custom test harness

### Requirement: Representative integration flows
The project SHALL ship one solo TextField semantic flow and one ShellBorder/Rollout composition flow that proves direct event routing, semantic state, a phase checkpoint, scale-aware capture, and continuation.

#### Scenario: Run shipped flows
- **WHEN** the complete validation suite runs
- **THEN** both representative flows pass and no unrelated static story receives a screenshot baseline
