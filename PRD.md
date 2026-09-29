# Product Requirements

QSM Workbench is a local, provider-neutral QML workbench for rendering,
inspecting, capturing, and semantically driving component stories and
compositions.

## Requirements

- Launch requires one explicit provider root.
- Providers own their adapter, story catalog, composition descriptor, flow host,
  and task declarations through fixed paths.
- Composition and flow documents remain bounded, data-only JSON.
- Tasks resolve only manifest-declared names to fixed workbench-owned argv.
- Headless capture creates PNG artifacts through the provider adapter.
- Runtime failures in provider adapters or flow hosts are surfaced truthfully.

## Acceptance floor

`npm test` and `npm run validate` must pass against the generic provider fixture.
