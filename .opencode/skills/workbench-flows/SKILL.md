---
name: workbench-flows
description: Work with provider-neutral semantic flow documents.
---

Flow JSON is bounded data. The workbench validates it against selected provider
stories and descriptor data, then executes it through the harness's own
`qml/QsmWorkbench/FlowHost.qml` against the provider's `Adapter.qml`. Use
`node scripts/flow-runner.mjs run <flow> --provider <root>`.
