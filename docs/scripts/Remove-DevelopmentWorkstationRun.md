# Remove-DevelopmentWorkstationRun.ps1

## Purpose

Garbage-collects expired, registered "workstation smoke run" directories (and the disposable Podman resources they own) that other scripts in this ecosystem create during local, interactive development/testing — without ever touching active, foreign, unmanaged, or unverifiable runs, and without touching real product installations under `LocalAppData`/`~/.local/share` (explicitly out of scope per its own `.DESCRIPTION`, line 9). It solves the housekeeping problem of disk/container cruft accumulating from repeated local smoke-test runs. It is a standalone maintenance entry point; no other script in `scripts/` was found to call it, implying it is meant to be run manually (or on a schedule) by a developer or CI housekeeping job, consistent with its `ConfirmImpact='High'` destructive classification.

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `WorkspaceRoot` | `string` | No | `Split-Path $PSScriptRoot -Parent` |
| `RetentionDays` | `int` (`ValidateRange(0,3650)`) | No | `7` |
| `KeepLatest` | `int` (`ValidateRange(0,1000)`) | No | `3` |
| `ActiveGraceMinutes` | `int` (`ValidateRange(0,1440)`) | No | `15` |

Supports `-WhatIf`/`-Confirm` (`SupportsShouldProcess`, `ConfirmImpact='High'`); `-WhatIf` performs no removal (stated explicitly in `.DESCRIPTION`, line 7).

```powershell
# Preview what would be removed
./scripts/Remove-DevelopmentWorkstationRun.ps1 -WhatIf

# Actually clean up, keeping the 5 most recent runs regardless of age
./scripts/Remove-DevelopmentWorkstationRun.ps1 -KeepLatest 5
```

## Dependencies

- Dot-sources `ReportPaths.ps1` (line 22) — supplies `Get-QuietReportRoot` (used line 24).
- `Import-Module (Join-Path $PSScriptRoot 'lib/WorkstationResources.psm1')` (line 23) — supplies `Get-WorkstationCleanupDecision`, `Test-WorkstationDirectoryBoundary`, `Test-WorkstationPodmanIdentity`, and `Remove-WorkstationOwnedResource`, all of which carry the real business logic this script orchestrates.
- Shells out indirectly through `Remove-WorkstationOwnedResource` (presumably to Podman, given `Test-WorkstationPodmanIdentity`), though the native calls themselves live in the `.psm1`, not in this file.
- Opens an `IO.FileStream` on each run's `run.lease` file with `FileShare.Delete` (line 40) as a cooperative locking mechanism to detect/avoid a concurrently-running producer — a deliberate, documented design (comment, lines 37-38).
- Assumes the workstation-run directory layout and `receipt`/`run.lease` conventions produced elsewhere in the ecosystem (not shown in this file) are already in place; this script is purely a consumer/cleaner of that convention, not its producer.

## Side effects

- For each candidate run directory, emits one `[pscustomobject]` status row per iteration (`Retained`, `Protected`, `Eligible`, or `Removed`) — a read/report-only effect.
- When a run is judged `Inactive` and not protected by any boundary/lease/resource check, and `-WhatIf` is not set and the user confirms: calls `Remove-WorkstationOwnedResource` for real (line 47, without `-Preview`) to release owned Podman resources, then recursively deletes the run directory (`Remove-Item -Recurse -Force -Confirm:$false`, line 51) — the only filesystem deletion in the script, and it is explicitly gated by `$PSCmdlet.ShouldProcess` (line 46) beforehand.
- Disposes the lease `FileStream` in a `finally` (line 54) regardless of outcome.

## Findings

- The function re-validates `Test-WorkstationDirectoryBoundary` a second time (line 50) immediately before the actual `Remove-Item -Recurse -Force` (line 51), after having already checked it once earlier (line 34) — an explicit, deliberate TOCTOU (time-of-check-to-time-of-use) mitigation given that resource release (lines 47-49) runs in between and could theoretically change state. This is good defensive design against a narrow race window, not a bug.
- `Remove-Item -Confirm:$false` at line 51 **suppresses PowerShell's own built-in destructive-action confirmation prompt** on top of the script's own `$PSCmdlet.ShouldProcess` gate at line 46. This is intentional and correct here — the script already obtained its own `ShouldProcess` confirmation one level up, so suppressing the cmdlet's redundant second prompt avoids double-prompting — but it is worth a reviewer's attention since `-Confirm:$false` can look alarming out of context; it is safe only because it is reached exclusively through the already-gated branch.
- DESIGN: the lease-based mutual exclusion (`FileShare.Delete`, lines 39-40) is a clever but implicit protocol — nothing in this file documents what writes/renews `run.lease`, so a reviewer auditing only this script (without also reading `WorkstationResources.psm1` and the run-registration script) cannot fully verify the protocol's correctness. This is a cross-file coupling that would benefit from a short doc-comment cross-reference (e.g. "see New-WorkstationRun.ps1 for the producer side of this lease").
- No `.PARAMETER` doc is given for the implicit `-WhatIf`/`-Confirm` common parameters, but that's standard and not expected to be documented explicitly.
- No hardcoded paths needing parameterization were found; `WorkspaceRoot`, `RetentionDays`, `KeepLatest`, and `ActiveGraceMinutes` already cover the tunable surface, and defaults are sensible.
- Testability: good — `FrenchExDev2.QuietCli.Core.Tests.PoSh\WorkstationResources.Tests.ps1` exists and presumably exercises `WorkstationResources.psm1`'s decision/boundary/identity functions that this script orchestrates. This script's own orchestration loop (lines 28-56) is not itself directly unit-tested as far as could be determined, but the riskier logic (what counts as "inactive," boundary checks, Podman identity verification) is the part covered.
- CONVENTION: dense single-line statements again appear here (e.g. line 30-34 compress multi-step logic onto very few lines), consistent with the style already flagged for sibling scripts; no functional defect, but it reduces readability for a script explicitly marked `ConfirmImpact='High'` where careful human review matters most.

## Verdict

Fit for purpose; this is one of the more carefully engineered scripts in the batch, with deliberate TOCTOU mitigation and conservative, multi-layered protection checks (boundary, lease, Podman identity) before any deletion. The one improvement worth prioritizing is documentation: cross-reference the `run.lease` producer/consumer protocol in a comment here so the safety argument doesn't require reading `WorkstationResources.psm1` in full to verify.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Reports and cleans expired, registered workstation smoke runs and their labelled disposable resources.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
