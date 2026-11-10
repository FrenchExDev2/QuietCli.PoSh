# Test-PowerShellModuleExports.ps1

`ExpectedCmdlets` optionally checks the exact cmdlet set independently from `ExpectedFunctions`. Both comparison flags are saved; the complete migration gate requires both. An explicitly empty set is valid. Alias exports are observed separately and still need their own API review.

Explicit real-import observation for one whitelisted PowerShell module. The [library](lib/Migration.Exports.md) owns selection, process lifecycle and ShouldProcess; the facade forwards arguments and common parameters.

```powershell
./scripts/Test-PowerShellModuleExports.ps1 -SourceRoot C:/code/FrenchExDev/FrenchExDev_i2 -ItemId Kubernetes-PoSh -EntryPath Kubernetes.PoSh.psd1 -WhatIf
# Explicitly executing the same selected probe observes Get-Module exports.
# Add ExpectedFunctions only when the exact public contract has been approved.
```

Parameters: SourceRoot, PolicyPath, exact configured ItemId, explicit relative EntryPath (.psd1/.psm1), optional exact ExpectedFunctions, StageCopy, new external RunDirectory and bounded TimeoutSeconds. StageCopy makes a bounded verified owned source copy, excludes generated/Git caches and records original/staged identities; location-sensitive behavior is scoped to that copy. A static ValidateSet would freeze the configurable whitelist, so the reusable function validates current membership. Without ExpectedFunctions the observation has Qualification=NotAssessed. Matching functions yields ExportContractPassed, never behavior/migration qualification. Cmdlets and aliases are recorded separately.

Side effects: module import executes selected code in a fresh monitored child process and saves progress/final evidence. WhatIf performs no import or report-directory creation. The normal profile is retained. Missing dependencies, import failures and export mismatches are explicit failures; timeouts are supervised. A separate process is not an OS security sandbox and does not prohibit arbitrary effects from selected module code. Use owned fixtures or reviewed modules.

Dependencies: PowerShell 7.6+ on Windows for the current visible-monitor launcher, local Common/ReportPaths/Ci.Process supervisor, Watch-Tests and the dedicated [worker](workers/Invoke-ModuleExportProbe.md). Crossplatform product import qualification remains required independently; current launcher refuses unsupported local monitoring platforms.

Critical review: [facade](../../scripts/Test-PowerShellModuleExports.ps1:23) forwards WhatIf/Confirm to the effect owner. The actual module is matched by selected directory/name after import; re-exported names retain their observed source. Independent companion cases cover preview, public/private distinction and failed import. Verdict: actual export observation, bounded to an explicit probe, with no automatic approval of migration.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
