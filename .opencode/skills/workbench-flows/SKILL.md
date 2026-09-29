---
name: workbench-flows
description: Work with provider-neutral semantic flow documents.
---

# Workbench Flows

Flow JSON is bounded data. The workbench validates it against selected provider
stories and descriptor data, then executes it through the provider's fixed
`workbench/FlowHost.qml`. Use `node scripts/flow-runner.mjs run <flow> --provider <root>`.
