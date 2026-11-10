# Invoke-ModuleExportProbe.ps1

ExpectedFunctions and ExpectedCmdlets are optional independent exact-set comparisons; their coverage flags are recorded. Staged imports map the loaded module path back to the original path for source-hash correlation while retaining the staged-scope flag.

Internal worker of [Test-PowerShellModuleExports](../Test-PowerShellModuleExports.md). The launcher writes a validated request and starts this worker in a fresh normal-profile process. Direct execution is not the supported selection/authorization entry point.

WorkspaceRoot selects the shared report writer; RunDirectory owns request/status/summary/logs. The worker rechecks entry/policy hashes, imports the exact selected entry and calls Get-Module to resolve its actual identity. It records public functions, cmdlets, aliases, command source/type and RequiredModules. Import pipeline output is counted without retaining arbitrary business content. An import failure or unexpected output fails the probe. An optional exact function set distinguishes observation from an export-contract pass.

Side effects: selected module import and owned JSON progress/evidence. ShouldProcess guards both; WhatIf returns before import/writes. No automatic removal/retry/activation of modules outside the disposable child. The process exits after saving terminal state. The monitor/supervisor is owned by the launcher.

Critical review: [worker](../../../scripts/workers/Invoke-ModuleExportProbe.ps1:25) isolates assembly state but cannot constrain effects of imported source code. RequiredModules records runtime module dependencies, not every native/reflective dependency. A real export set does not establish function-body correctness. Companion regression covers actual public/private exports, unavailable dependency and preview. Verdict: a bounded evidence worker, with behavior and migration qualification explicitly separate.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
