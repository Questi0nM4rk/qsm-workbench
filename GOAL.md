# Goal

Make QML component workbench workflows portable across providers without copying
provider-specific runtime assumptions into the workbench core.

The workbench should open one provider, render its real adapter, validate its
bounded data, run its semantic flows, execute only declared fixed tasks, and
produce truthful diagnostics and captures.
