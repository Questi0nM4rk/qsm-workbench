---
name: workbench-component-authoring
description: Add provider-owned QML stories or adapter behavior for qsm-workbench.
---

# Provider Component Authoring

Component rendering belongs to the selected provider. A provider story is
versioned data; the provider adapter constructs visible QML and exposes neutral
status, controls, actions, events, and inspection.

Validate provider stories through `node scripts/workbench.mjs --check --provider <root>`.
