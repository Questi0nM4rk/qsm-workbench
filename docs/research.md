# Research

The current product direction is a provider-portable local QML workbench. A
provider supplies runtime-specific QML and data descriptors; workbench core keeps
generic validation, orchestration, state, capture, and task supervision.

Design references remain component-workbench patterns: searchable story catalogs,
controls/actions panels, event logs, inspection dumps, headless captures, and
semantic flows. None require a provider-specific path in the core product.
