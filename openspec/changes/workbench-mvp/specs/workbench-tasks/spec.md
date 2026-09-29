## ADDED Requirements

### Requirement: Named operations only
The workbench SHALL expose fixed argv-based operations for selected unit tests, contract validation, full validation, capture, and opening known paths, and SHALL NOT expose arbitrary shell command execution.

#### Scenario: Run selected test
- **WHEN** the user runs the selected story test
- **THEN** the runner invokes the existing shell command associated with that test level using a validated argument array

### Requirement: Truthful task lifecycle
Each operation SHALL report idle, running, succeeded, failed, or cancelled status with preserved raw stdout and stderr.

#### Scenario: Command fails
- **WHEN** a named operation exits non-zero
- **THEN** its status is failed and its raw output remains available

### Requirement: Cancellation
The workbench SHALL allow the running task to be cancelled using TERM followed by bounded KILL escalation if it does not exit.

#### Scenario: Task ignores termination
- **WHEN** a cancelled task remains running after the cancellation timeout
- **THEN** the runner sends KILL and reports the final task as cancelled

### Requirement: Capture ownership
Capture SHALL use the existing shell capture command, the selected canonical story, and its declared viewport without workbench chrome.

#### Scenario: Capture succeeds
- **WHEN** capture completes successfully
- **THEN** the output path is shown and can be opened through a named path action
