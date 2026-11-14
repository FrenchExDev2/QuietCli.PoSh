# Update-DotNetGlobalJson.ps1

## Purpose

Verify an exact installed SDK and update only explicitly selected global.json files,
with original-byte backups. [Complete guide](../../README-dotnet-and-global-dot-json.md#update-only-globaljson).

## Usage and parameters

```powershell
./scripts/Update-DotNetGlobalJson.ps1 -Version 11.0.100 -WhatIf
./scripts/Update-DotNetGlobalJson.ps1 -Version 11.0.100 -Confirm
```

Path defaults to this checkout's global.json. Version can be explicit or resolved from
Channel. Preleases controls preview/RC policy; RollForward overrides an existing policy;
SdkDirectory adds relative sdk.paths plus host fallback; DotNetPath verifies installation.
SkipInstalledCheck explicitly permits CI pin preparation. Create and AllowDowngrade are
required for those respective effects. QuietCliRoot selects process infrastructure.

## Dependencies and effects

Imports scripts/lib/DotNetProvisioning.psm1. The approved operation can query metadata
and native inventories, create unique backups and atomically replace individual files.
Explicit-version WhatIf can validate local documents without native/network effects.

## Findings

- scripts/Update-DotNetGlobalJson.ps1:40 guards delegation; the direct library function
  has its own guard at scripts/lib/DotNetProvisioning.psm1:167.
- scripts/lib/DotNetProvisioning.psm1:29 validates every selected document before writes;
  unrelated JSON values survive, but changed formatting/comments may be normalized.
- scripts/lib/DotNetProvisioning.psm1:106 detects observed concurrent changes and preserves
  original bytes. This is not a cross-file transaction or a lock against every race.
- sdk.paths requires a .NET 10+ host and affects SDK selection, not application runtime lookup.

## Verdict

Covered by offline preservation, malformed-input, idempotence and backup assertions.
Interactive confirmation and real multi-host SDK resolution require separate evidence.

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [DotNetProvisioning.psm1](lib/DotNetProvisioning.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Verifies an SDK, backs up global.json and updates its SDK selection settings.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
