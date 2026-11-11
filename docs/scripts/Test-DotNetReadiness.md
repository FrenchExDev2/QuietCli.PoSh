# Test-DotNetReadiness.ps1

## Purpose

Observe SDK release/archive publication, MCR platforms and local SDK/runtime readiness.
[Complete guide](../../README-dotnet-and-global-dot-json.md#check-the-current-situation).

## Usage and parameters

```powershell
$report = ./scripts/Test-DotNetReadiness.ps1 -Channel 11.0
./scripts/Test-DotNetReadiness.ps1 -Preleases -WhatIf
```

Parameters: Channel, Preleases, Rid, Platform, ImageVariant, ProjectPath, SkipLocal,
ReportPath, TimeoutSeconds, QuietCliRoot and FailIfNotReady. Defaults: stable 11.0,
current host RID, Linux amd64/arm64 and this checkout as ProjectPath. ReportPath is optional;
its parent must exist. FailIfNotReady throws after the report when full readiness is false.

## Dependencies and effects

Imports scripts/lib/DotNetReadiness.psm1. Approved probes perform read-only HTTP/native
queries; only an explicit ReportPath writes output. No SDK install, daemon startup or
source migration occurs. WhatIf returns before probes or report writing.

## Findings

- scripts/Test-DotNetReadiness.ps1:51 guards the full operation; native queries use
  scripts/lib/DotNetReadiness.psm1:170 and the independent Ci.Process helper.
- HTTP/TLS failures remain Unknown. A successful manifest does not prove an image pull/run.
- Archive HEAD checks prove URL availability only; installation separately verifies bytes.
- This does not replace Test-SdkReadiness.ps1's Crossgen2 publication feasibility matrix.

## Verdict

A bounded structured availability report, not application or release qualification.

<!-- script-contract:begin -->
## Execution contract

Purpose: Checks .NET SDK publication, downloads, container platforms and local readiness.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
