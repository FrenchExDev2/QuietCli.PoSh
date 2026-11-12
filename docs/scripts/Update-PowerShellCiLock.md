# Update-PowerShellCiLock.ps1

## Purpose and usage

Updates only PowerShell host/image pins after verifying published resources. SDK, OS base images and the separately pinned Alpine runtime remain unchanged.

```powershell
./scripts/Update-PowerShellCiLock.ps1 -PlanOnly -AllowAlpineVersionLag
./scripts/Update-PowerShellCiLock.ps1 -AllowAlpineVersionLag -WhatIf
./scripts/Update-PowerShellCiLock.ps1 -AllowAlpineVersionLag -Confirm
```

WorkspaceRoot defaults to this checkout. PlanOnly performs the availability audit and returns proposed documents without writes. WhatIf makes no HTTP call, import, directory or backup. AllowAlpineVersionLag explicitly retains the available native package when current GA is unavailable; without it the update fails. The exception is persisted with its requested/retained versions and reason.

Stable host entries use actual Microsoft archive digests. An unpublished next-version preview has availability metadata but no invented archive/hash. Preview remains an explicit CI opt-in. If a future native Alpine GA package requires another runtime major, that runtime must be prepared separately before acceptance.

## Dependencies and side effects

Delegates to [PowerShellReleases](lib/PowerShellReleases.md). All required evidence is checked before either selected lock is written. Changed locks receive original-byte backups and UTF-8/LF temporary-file replacement. Replacement is atomic per file, not a cross-file transaction. No native execution, system installation, SDK update, image build or publication occurs.

## Critical review and verdict

`scripts/Update-PowerShellCiLock.ps1:1` is the explicit PowerShell counterpart to the independent .NET lock updater. Property/malformed-evidence fixtures test archive identity, missing packages, native architecture sets, preview isolation and preserved unrelated pins. Actual resource availability is audited separately; hosted runner and image qualification remain required.

<!-- script-contract:begin -->
## Execution contract

Purpose: Verifies published GA/next-preview resources and updates PowerShell host/image pins.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
