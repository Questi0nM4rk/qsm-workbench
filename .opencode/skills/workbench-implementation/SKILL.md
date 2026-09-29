---
name: workbench-implementation
description: Implement provider-neutral qsm-workbench changes.
---

# Workbench Implementation

- Preserve unrelated dirty files.
- Require explicit provider roots for runtime work.
- Keep provider-specific rendering in provider `workbench/Adapter.qml` and
  provider-specific flow execution in provider `workbench/FlowHost.qml`.
- Keep core scripts generic: schema validation, capture runner, flow runner, and
  fixed named task operation dispatch.
- Never accept shell command strings or `sh -c` through provider data.
- Finish with `npm test` and `npm run validate`.
