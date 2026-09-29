## 1. Provider Boundary

- [x] 1.1 Define the trusted provider layout, manifest, adapter ownership, and
  non-executable data boundary.
- [x] 1.2 Add strict fixed-layout provider manifest loading with synthetic
  fixture coverage.
- [x] 1.3 Make launcher selection and catalog loading provider-aware.
- [x] 1.4 Add a neutral provider canvas and observability bridge.

## 2. Provider Runtime

- [x] 2.1 Move composition descriptor validation behind the selected provider.
- [x] 2.2 Move flow target resolution and fixed host loading behind the provider.
- [x] 2.3 Move named task operation resolution behind validated provider
  operation definitions.
- [x] 2.4 Update live-workbench errors, status, inspection, and persistence for
  provider identity.

## 3. qsm-shell Provider Migration

- [x] 3.1 Add qsm-shell `workbench/` manifest, adapter, catalog, descriptor,
  flow host, and named task declarations.
- [x] 3.2 Migrate active component-family stories and delete each equivalent
  legacy unit/Preview branch only after provider validation and live review.
- [x] 3.3 Retire the last `previews/units` and legacy preview host.

## 4. Guidance And Verification

- [x] 4.1 Move canonical workbench skills and agents to `.opencode`; remove
  duplicate `.claude` projections.
- [x] 4.2 Validate a synthetic second provider, qsm-shell provider, provider
  flows, task cancellation, and full workbench checks.
