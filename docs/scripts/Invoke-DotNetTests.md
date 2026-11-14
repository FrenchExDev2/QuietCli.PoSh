# Invoke-DotNetTests.ps1

## Purpose

Select focused offline .NET automation campaigns through the existing shared launcher.

## Usage and parameters

```powershell
./scripts/Invoke-DotNetTests.ps1
./scripts/Invoke-DotNetTests.ps1 -Suite Layout
./scripts/Invoke-WorkspaceCi.ps1 -Suite DotNet -SkipBuild
```

Suite selects Readiness, Provisioning, Layout, Locks or All; RunDirectory preserves an explicit
new report location; TimeoutSeconds bounds the owned worker (default 120 seconds).

## Dependencies and effects

Delegates to Invoke-WorkspaceCi.ps1, which uses the normal-profile background worker,
visible shared monitor and Get-QuietReportRoot's external test directory. The DotNet
worker branch does not build or import the product engine. Tests own disposable file
fixtures and bounded mutants, with no real SDK download or image pull.

## Findings

- scripts/Invoke-DotNetTests.ps1:16 guards process/report creation; it forwards only
  selected scope to the shared launcher instead of maintaining another scheduler.
- FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-DotNetQualification.ps1:1 retains per-suite
  counters/hashes and reports progress through the existing monitor callback.
- The focused suite is independent of Core/All release qualification. Real installation,
  interactive confirmation and unexecuted operating systems remain evidence gaps.

## Verdict

Use for targeted development validation; preserve each terminal report and its source identity.

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs focused offline .NET tooling campaigns through the shared visible test launcher.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
