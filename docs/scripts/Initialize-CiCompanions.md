# Initialize-CiCompanions.ps1

Reads `build/companions.yml` through `scripts/lib/CiCompanions.psm1` and returns selected tests,
product/tool closure, image layers, Core-evidence policy and configuration SHA-256. It starts no
tests or native tools. Missing pinned parser resources are prepared by the consumer.

`Suite` accepts a declared suite or All. `RuntimeIdentifier` and `RuntimeMajor` default to the host;
workflows supply the selected Windows host explicitly. Optional `OutputPath` appends `has_core`
to a GitHub output file. Optional `EnvironmentPath` appends `QUIETCLI_SUITE_HAS_CORE` and declared,
target-matched mutation controls in UTF-8/LF, preserving prior content. WhatIf returns before any
resource preparation or output writes.

```powershell
./scripts/Initialize-CiCompanions.ps1 -Suite Vagrant
./scripts/Initialize-CiCompanions.ps1 -Suite All -RuntimeIdentifier win-x64 -RuntimeMajor 11 -EnvironmentPath $env:GITHUB_ENV
```

Tool dependencies do not select their test suites: Core requiring Git's handler does not enable
Git mutations. Integration suites declare several companions and their own test module/command.

<!-- script-contract:begin -->
## Execution contract

Purpose: Resolves declared companion requirements and writes optional GitHub outputs and environment controls.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
