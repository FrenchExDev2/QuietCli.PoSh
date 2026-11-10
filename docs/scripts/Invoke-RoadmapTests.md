# Invoke-RoadmapTests.ps1

The complete tooling campaign also covers .NET discovery, whitelist/exact target boundaries, no-effect WhatIf with pure JSON, Unicode tables, native outcome invariants and targeted Release/selection/outcome mutants. Owned C# fixtures are actually built in Release: one deliberately fails and one succeeds, retaining individual diagnostics. These expected fixture build failures do not qualify any product or mean the tooling assertions failed.

The full suite now includes migration dependency/whitelist gates, actual isolated Get-Module export observations and the resource-aware progression planner. Existing graph properties/malformed corpora/mutations remain; additional independent controls cover missing imports, cyclic scripts, hostile XML, unapproved selection, .gitkeep scaffolds, report WhatIf, actual public/private exports and failed imports. These tooling checks do not qualify migration candidates or registry products.

Starts the complete planning-tooling campaign in a background PowerShell Core process with its normal profile and a dedicated visible [Watch-Tests](Watch-Tests.md) window. The window closes normally after a saved terminal summary. Tests do not modify repository sources or provision i3.

```powershell
./scripts/Invoke-RoadmapTests.ps1 -TimeoutSeconds 180
# Reopen a completed report using the exact directory printed by the launcher:
./scripts/Watch-Tests.ps1 -RunDirectory '<reported-run-directory>'
```

Parameters: `WorkspaceRoot` defaults to this monorepo; `RunDirectory` must be new and defaults to the shared external temporary reports root; `TimeoutSeconds` is an owned worker deadline from 1 to 600 seconds, default 180. This local launcher requires Windows and offers no headless bypass.

Dependencies: PowerShell Core 7.6, the independent test companion [worker](../../FrenchExDev2.QuietCli.Core.Tests.PoSh/roadmap-tests/Invoke-RoadmapTests.ps1), `Common.ps1`, `ReportPaths.ps1`, `Watch-Tests.ps1` and the planning contract module. The launcher reuses the existing engine-independent worker-supervision/argument-quoting helpers. It does not load Core, build the product or install dependencies. The worker has no native executable to invoke.

The deterministic seed is 20261110. Evidence keeps example/fault checks, 80 generated DAGs plus their self-cycle controls, a malformed model/JSON/identifier corpus, file/WhatIf/idempotence controls and four targeted source mutants separate. A mutant is killed only when removing its guard makes the independent rejection witness fail; import/target failures crash the campaign rather than count as a kill. Retain source mutants, fixtures and diagnostics in the owned run directory.

Outputs: `status.json`, terminal `summary.json` with cases/categories/source hashes/runtime/seed, `planning-assessment.json`, `mutations.json` and stdout/stderr logs. Reports are temporary; archive required durable evidence explicitly. The worker reads a copied fixture for destructive scenarios. Monitor rows identify the concrete test project, task, full source/workspace paths, PID, Duration and available counters.

Critical review ([launcher](../../scripts/Invoke-RoadmapTests.ps1), [companion](../../FrenchExDev2.QuietCli.Core.Tests.PoSh/roadmap-tests/Invoke-RoadmapTests.ps1)): deadline/crash supervision and resize rendering reuse existing helpers rather than duplicating them. This campaign establishes the planning controller's declared scope only; it does not rerun QuietCli Core/Git/Vagrant, validate future modules, measure product performance, instrument coverage or establish a release matrix. Four targeted mutants are a bounded catalogue. A monitor startup failure kills the owned worker and reports the failure; it does not silently run without a window.

Verdict: complete local campaign for this planning-tooling change, with product acceptance explicitly excluded. Re-run on changed controller, generator, fixtures, assertions or source models. Read-only documentary wording changes do not justify rerunning unrelated product campaigns.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
