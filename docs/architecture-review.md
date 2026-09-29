# Architecture Review

Workbench core is a provider-neutral orchestrator. Provider-specific execution
enters only through fixed files inside the selected provider root:

- `Adapter.qml` for visual story/composition rendering.
- `composition-types.json` for bounded composition validation.
- `FlowHost.qml` for bounded semantic flow execution.
- `tasks.json` for named operation declarations.

The core rejects missing providers, unknown schema fields, executable document
content, arbitrary task commands, and unsupported adapter contracts before
starting runtime work where possible.
