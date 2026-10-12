# Backlog

- Existing fullscreen/environment, native input, session-control and inspector
  changes remain mixed, partly staged work on `master`; preserve that work when
  preparing commits. Do not treat an installed development snapshot as a clean release.
- Capture now shares the flow runner's Quickshell namespace staging, waits for
  declared ready/idle plus two render frames, and has bounded runtime failure.
  It captures the isolated adapter, never the owner's desktop. Offscreen SVG
  glyph fidelity and live owner acceptance remain outside this evidence.
- Focused capture checks pass for a unit-backed provider, a Quickshell namespace
  provider with declared idle state, and a refused story. The installed package
  includes the current development snapshot; unrelated implementation remains
  uncommitted and must be reviewed before release.
