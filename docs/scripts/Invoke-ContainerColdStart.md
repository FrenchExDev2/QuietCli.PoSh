# Invoke-ContainerColdStart.ps1

## Purpose

Launches `Invoke-ContainerColdStartWorker.ps1` in the background with a visible host-side monitor
(local-only), i.e. it is the Windows-host launcher for the containerized cold-start gateway — the
Linux-target analogue of `Invoke-ColdStartGate.ps1` running directly on Windows. It solves the same
problem as `Invoke-ContainerCi.ps1` (give a container-run worker a visible monitor and bounded timeout)
but specifically for the cold-start A/A-gated A/B pipeline rather than general test suites. It is invoked
by `Invoke-ColdStartMatrix.ps1` (line 161) for each selected Linux target in the matrix.

## Usage

Parameters:
- `-WorkspaceRoot` (string, optional, default `(Split-Path $PSScriptRoot -Parent)`).
- `-Image` (string, **mandatory**) — prepared local image with PowerShell and .NET 11 RC.
- `-Platform` (string, **mandatory**, `[ValidateSet('alpine','debian')]`) — platform label for monitor/RID check.
- `-CandidateModule` (string, **mandatory**) — host path to the already-built ReadyToRun candidate `.psd1`.
- `-CandidateLabel` (string, optional, `[ValidateNotNullOrEmpty()]`, default `'readytorun'`).
- `-ExpectedRuntimeIdentifier` (string, optional, `[ValidatePattern('^linux-(musl-)?(x64|arm64)$')]`) — required guest RID.
- `-Headless` (switch, optional) — CI-only, no desktop window.
- `-TimeoutSeconds` (int, optional, `[ValidateRange(1,7200)]`, default `1200`) — maximum worker duration.

Example (from its own help, line 32):
```powershell
./scripts/Invoke-ContainerColdStart.ps1 -Image $image.Image -Platform debian -CandidateModule $candidate -ExpectedRuntimeIdentifier linux-x64 -Headless
```

## Dependencies

- Dot-sources `Common.ps1` (line 44) for `Get-QuietReportRoot`, `ConvertTo-CiArgument`, `Wait-WorkspaceWorker`.
- Starts `Invoke-ContainerColdStartWorker.ps1` as a background `pwsh -File` process (lines 48–52).
- Starts `Watch-Tests.ps1` as the visible monitor (line 54) unless `-Headless`.
- Native tool: resolves `pwsh` via `Get-Command` (line 47).
- Filesystem: creates a per-run directory under `Get-QuietReportRoot $WorkspaceRoot 'coldstart-containers'` (line 45).

## Side effects

- Creates the per-run report directory and `worker.stdout.log`/`worker.stderr.log` files.
- Starts two OS processes (worker + optional monitor).
- Throws `'A local visible monitor requires the Windows host launcher.'` (line 51) if non-headless on non-Windows.
- Throws `"Container cold-start report did not complete: $run"` (line 58) only on `'Crash'` or `'Timeout'` state — notably **not** on other non-Success states (see Findings).

## Findings

- BUG/DESIGN: Line 58's failure check is `if ($summary.State.State -eq 'Crash' -or $summary.State.State -eq 'Timeout')`. Comparing against `Invoke-ContainerColdStartWorker.ps1`'s actual state machine, that worker can also end in `'InconclusiveNoiseFloor'` or `'Failed'` (its generic catch path also sets `'Crash'`, but other paths exist conceptually). If the worker ever returns a state other than `'Success'`/`'Crash'`/`'Timeout'` — for instance if `Wait-WorkspaceWorker` itself defines additional terminal states not visible in this file — this script would return normally without throwing, silently treating a non-success, non-crash, non-timeout outcome as acceptable. This narrow allow-list-style check (rather than `-ne 'Success'`) is a correctness risk: it should arguably be `if ($summary.State.State -ne 'Success')` to fail closed instead of open, matching the pattern used in `Invoke-ContainerCi.ps1` (`if($summary.State.State -ne 'Success')`).
- Missing input validation: as with `Invoke-ContainerCi.ps1`, no existence check on `-Image`, `-CandidateModule` before forwarding to the worker (lines 48, 49).
- CONVENTION: consistent, correct use of `ConvertTo-CiArgument` for all path-shaped arguments (lines 48–49) — good security practice, matches sibling scripts.
- No companion Pester test found for `Invoke-ContainerColdStart.ps1`.
- Test-run monitor convention: correctly uses `Start-Process -FilePath $runner -WindowStyle Normal` (line 54) for the visible monitor, consistent with `AGENTS.md`.

## Verdict

Mostly fit for purpose, but the narrow `'Crash'`/`'Timeout'`-only failure check at line 58 is a real correctness gap — it should fail closed (`-ne 'Success'`) rather than fail open on any other non-success state the worker might report (e.g. `'InconclusiveNoiseFloor'`, `'Failed'`). This is the highest-priority fix.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
