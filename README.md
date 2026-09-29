# QSM Workbench

Local provider-neutral QML workbench. A run loads exactly one explicit provider
root with a fixed `workbench/` layout: manifest, adapter, stories, optional
composition descriptor, optional flow host, and optional named task definitions.

## Run

```bash
npm run workbench -- --provider /path/to/provider
QSM_WORKBENCH_PROVIDER_ROOT=/path/to/provider npm run workbench
```

Validation never guesses a provider:

```bash
npm run validate
node scripts/workbench.mjs --check --provider fixtures/providers/generic
```

## Provider contract

- `workbench/provider.json` declares `version`, `id`, and capabilities.
- `workbench/stories.json` is versioned data: `{ "version": 1, "stories": { ... } }`.
- `workbench/Adapter.qml` renders story and composition modes and exposes the
  neutral controls/actions/events/inspection contract.
- An optional fixed `workbench/shell.qml` lets a provider supply its Quickshell
  config root while loading the same generic Workbench UI.
- `workbench/composition-types.json` bounds composition data.
- `workbench/FlowHost.qml` executes bounded semantic flow steps.
- `workbench/tasks.json` maps provider task names to fixed workbench operations;
  no command strings are accepted.

The included `fixtures/providers/generic` provider is the generic regression
provider and `fixtures/providers/second` proves a second provider can validate.
