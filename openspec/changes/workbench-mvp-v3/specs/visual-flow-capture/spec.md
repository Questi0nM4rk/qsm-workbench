## ADDED Requirements

### Requirement: Explicit scale-aware capture
Each flow capture SHALL render the logical target viewport at the flow's explicit scale, report physical dimensions equal to logical dimensions multiplied by scale, and remain independent of workbench presentation zoom.

#### Scenario: Capture at 1.25 scale
- **WHEN** a 960 by 600 composition is captured with scale 1.25
- **THEN** the artifact is 1200 by 750 pixels and metadata records both logical and physical dimensions

### Requirement: Compatible baseline metadata
Visual comparison SHALL require matching target, flow step, logical viewport, render scale, physical dimensions, theme, Qt major/minor, and renderer metadata and SHALL NOT resample incompatible images.

#### Scenario: Wrong-scale baseline
- **WHEN** a 1.25-scale actual is compared with a 1.0-scale baseline
- **THEN** comparison fails as incompatible before pixel metrics are calculated

### Requirement: Bounded visual comparison
An opted-in capture step SHALL compare expected and actual PNGs using declared bounded color fuzz and maximum changed-pixel ratio and SHALL preserve expected, actual, diff, metadata, and concise metrics on failure.

#### Scenario: Visual regression exceeds threshold
- **WHEN** changed pixels exceed the step's declared ratio
- **THEN** the flow fails and emits navigable paths for the actual and highlighted diff artifacts

### Requirement: Stable checkpoint frame
Capture at an armed animation checkpoint SHALL wait for the paused state plus two queued render passes before grabbing the frame and SHALL not advance the paused animation.

#### Scenario: Paused phase capture
- **WHEN** a sequence is paused at `rollout.shell-revealed`
- **THEN** repeated captures before continue observe the same checkpoint state within the declared visual tolerance

### Requirement: Explicit baseline approval
Baseline creation or replacement SHALL occur only when the runner receives `--update-baseline`, SHALL write only beneath the project baseline directory, and SHALL never be enabled by document content.

#### Scenario: Missing baseline without approval
- **WHEN** a visual flow runs without a baseline and without the update flag
- **THEN** it fails with the expected baseline path and leaves project files unchanged
