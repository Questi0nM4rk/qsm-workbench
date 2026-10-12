<div align="center">

# `qsm-workbench`

**A local workbench that renders, inspects and captures Quickshell QML components, with the components supplied by a provider you point it at.**

[![license](https://img.shields.io/badge/license-GPL--3.0-blue)](./LICENSE)
[![Quickshell](https://img.shields.io/badge/Quickshell-QML-1f6feb)](https://quickshell.org)
[![Hyprland](https://img.shields.io/badge/Hyprland-Wayland-58e1ff)](https://hypr.land)
[![last commit](https://img.shields.io/github/last-commit/Questi0nM4rk/qsm-workbench)](https://github.com/Questi0nM4rk/qsm-workbench/commits)
[![code size](https://img.shields.io/github/languages/code-size/Questi0nM4rk/qsm-workbench)](https://github.com/Questi0nM4rk/qsm-workbench)

</div>

## Why it exists

I like building my own stuff and owning the tools I use, and that includes the desktop shell on my screen.
Working on a QML shell means restarting the whole shell to see one component, and nothing records what you saw.
This workbench opens one component at a time, from a provider you name, and keeps the checks and captures repeatable.
It refuses to be a general QML designer or a plugin host: documents are bounded data, and tasks are fixed names, not commands.
It would have no reason to exist if Quickshell shipped a component preview with scripted flows.

## Quickstart

Requires Arch Linux, Hyprland, Quickshell, and Node.js 24.

```bash
git clone https://github.com/Questi0nM4rk/qsm-workbench && cd qsm-workbench
npm run validate
# the test summary ends with `ℹ fail 0`, then: validated <N> stories from .../fixtures/providers/generic/workbench/stories.json
```

`npm run validate` does not open a window. To open the workbench on a provider:

```bash
npm run workbench -- --provider fixtures/providers/generic
# or: QSM_WORKBENCH_PROVIDER_ROOT=/path/to/provider npm run workbench
```

This starts `quickshell` and opens a window. Set `QSM_QUICKSHELL_BIN` to use another binary.
A run needs an explicit provider and fails without one.

## How it works

```text
provider root/                    workbench (this repo)
  workbench/provider.json  ---->  scripts/*.mjs   validate data, run tasks, run flows
  workbench/stories.json   ---->  qml/Workbench.qml   the UI
  workbench/Adapter.qml    ---->  qml/QsmWorkbench/FlowHost.qml   drives the adapter
  workbench/tasks.json
```

- The provider owns its adapter, stories, composition descriptor and task names.
- The workbench owns validation, orchestration and the flow host.
- Compositions and flows are data-only JSON, checked before anything runs.
- A task name in `tasks.json` maps to a fixed workbench operation. No command strings.

Details are in [docs/provider-contract.md](docs/provider-contract.md).
The behaviour specs are in `openspec/`.

## Numbers

[![last commit](https://img.shields.io/github/last-commit/Questi0nM4rk/qsm-workbench)](https://github.com/Questi0nM4rk/qsm-workbench/commits)
[![code size](https://img.shields.io/github/languages/code-size/Questi0nM4rk/qsm-workbench)](https://github.com/Questi0nM4rk/qsm-workbench)

| What | How to measure |
| --- | --- |
| Lines of code per language | `scc --exclude-dir .git,.beads .` on the committed tree |
| Test count and duration | `npm test`, the summary at the end prints `ℹ tests` and `ℹ duration_ms` |
| Fixture provider validation | `npm run validate` |
| Window startup time | Not measured |

Commits include agent-authored work under my identity; design, orchestration and review are mine.

## Status

- Works: provider validation, composition and flow checks, the generic and second fixture providers, the test suite.
- Experimental: the interactive window and headless capture. Their tests check how the harness starts them, not the pixels.
- Known gaps: `qmllint` exits 255 with no output on `qml/Workbench.qml`, so QML is not lint-checked yet.
- Known gaps: only the fixture providers are in this repo, and `stories/metadata.json` names components of a shell that is not published.
- Known gaps: tested on one machine only.

## License

[GPL-3.0](./LICENSE).
