# Test-MigrationDependencies.ps1

Inspects only whitelisted migration candidates. It delegates to [Migration.Dependencies](lib/Migration.Dependencies.md). It never migrates or imports inspected code.

```powershell
$report = ./scripts/Test-MigrationDependencies.ps1 -SourceRoot C:/code/FrenchExDev/FrenchExDev_i2 -ItemId Kubernetes-PoSh
$report.Items
$report.Dependencies
# Save a new external report, previewing the write first.
./scripts/Test-MigrationDependencies.ps1 -SourceRoot C:/code/FrenchExDev/FrenchExDev_i2 -ItemId Result -OutputPath "$env:TEMP/result-dependencies.json" -WhatIf
```

`SourceRoot` is mandatory. `PolicyPath` defaults to the versioned deny-by-default whitelist. `ItemId` is validated against that selected policy; no static ValidateSet freezes extensible candidate names. Without ItemId all non-Exclude policy entries are assessed. `OutputPath` optionally saves new UTF-8/LF JSON in an existing directory; it never overwrites evidence and forwards WhatIf/Confirm. `RequireGate` throws if MigrationDependencies is blocked. Its default diagnostic mode still returns the blocked report.

Dependencies: PowerShell Core 7.6+, local library, AST/XML APIs and policy/source files. No engine, SDK, network or native executable. Side effects: only the explicit report export. Missing files, unapproved candidates, unresolved/dynamic references and missing evaluated build evidence block the dependency gate. Passing this sub-gate alone never qualifies migration/cutover.

Critical review: [facade](../../scripts/Test-MigrationDependencies.ps1:21) forwards effects to the reusable export owner. The library inspects declarations rather than executing MSBuild or scripts. Tests cover owned fixtures, safe inspection, malformed policies, boundaries and targeted mutation controls. Verdict: reusable dependency-assessment gate, with explicit semantic/runtime gaps.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
