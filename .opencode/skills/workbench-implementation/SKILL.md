---
name: workbench-implementation
description: Implement provider-neutral qsm-workbench changes.
---

# Workbench Implementation

- Preserve unrelated dirty files.
- Require explicit provider roots for runtime work.
- Keep provider-specific rendering in provider `workbench/Adapter.qml`. Flow
  execution is the harness's: `qml/QsmWorkbench/FlowHost.qml` runs against any
  provider's adapter, and a provider shipping a `workbench/FlowHost.qml` is
  rejected.
- Keep core scripts generic: schema validation, capture runner, flow runner, and
  fixed named task operation dispatch.
- Never accept shell command strings or `sh -c` through provider data.
- Finish with `npm test` and `npm run validate`.
