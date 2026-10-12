# Provider contract

A run loads exactly one explicit provider root with a fixed `workbench/` layout.
The workbench never guesses a provider.

- `workbench/provider.json` declares `version`, `id`, and capabilities.
- `workbench/stories.json` is versioned data: `{ "version": 1, "stories": { ... } }`.
- `workbench/Adapter.qml` renders story and composition modes and exposes the
  neutral controls, actions, events, and inspection contract.
- An optional fixed `workbench/shell.qml` lets a provider supply its Quickshell
  config root while loading the same generic Workbench UI.
- `workbench/composition-types.json` bounds composition data.
- `workbench/tasks.json` maps provider task names to fixed workbench operations.
  No command strings are accepted.

The flow host belongs to the harness, not to a provider:
`qml/QsmWorkbench/FlowHost.qml` is the fixed template the flow runner injects
data into and runs against the selected provider's `Adapter.qml`.

`fixtures/providers/generic` is the generic regression provider.
`fixtures/providers/second` proves that a second provider can validate.
