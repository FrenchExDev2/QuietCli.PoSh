# Invoke-GitHubRunWorker.ps1

## Purpose

A read-only GitHub Actions run-status polling worker: it repeatedly queries an existing workflow run's
and its jobs' status via `gh api` (never re-triggering or cancelling anything), and writes durable
success/failure/cancellation/timeout reports, without ever exposing a token directly to this script (it
relies on `gh`'s own authenticated session). This exists so a developer can watch a remote CI run's
progress from a local visible monitor without needing direct GitHub API/token handling in this codebase.
It is invoked by `Watch-GitHubRun.ps1` (line 19) as a hidden background `pwsh -File` process, which is
itself presumably the visible-monitor launcher for this worker (analogous to the `*Worker.ps1` /
launcher pairs seen elsewhere in this folder).

## Usage

Parameters (standard ShouldProcess binding; no mandatory attributes despite all four being required for the
script to do anything useful):
- `-RunId` (long) — existing GitHub Actions run identifier.
- `-Repository` (string) — `owner/repository`.
- `-WorkspaceRoot` (string) — project workspace, used only to identify the run in the monitor's `$state`.
- `-RunDirectory` (string) — private status/report directory.

Example (internal invocation shape, as constructed by `Watch-GitHubRun.ps1` line 19):
```powershell
pwsh -File ./scripts/Invoke-GitHubRunWorker.ps1 -RunId 123456789 -Repository FrenchExDev/FrenchExDev_i2 -WorkspaceRoot C:\repo -RunDirectory C:\run\ghrun-1
```

## Dependencies

- Dot-sources `Common.ps1` (line 16) for `Write-WorkspaceJson`, `Invoke-CiProcess`.
- Native tool: `gh` (GitHub CLI) — `gh api <endpoint> --jq <projection>` (line 28), relying entirely on the ambient `gh auth` session for credentials; no token parameter exists in this script, which is a deliberate secrets-handling choice (the comment at line 1, "Lire les états GitHub de chaque job sans exposer de jeton", explicitly states the goal of never exposing a token).
- Queries two endpoints per poll cycle: `repos/$Repository/actions/runs/$RunId` and `repos/$Repository/actions/runs/$RunId/jobs?per_page=100` (lines 36–37).

## Side effects

- Writes `jobs.json` every poll cycle (line 40) and `status.json` every cycle while still running (line 43).
- Writes `summary.json` and a final `status.json` in the `finally` block (line 47) once the loop exits (success/cancelled/timed-out/failed/crash).
- Polls every 10 seconds (`[Threading.Tasks.Task]::Delay(10000).GetAwaiter().GetResult()`, line 44) — correct async-then-block pattern per `AGENTS.md`.
- Hardcoded 58-minute overall deadline (`$deadline=[DateTimeOffset]::UtcNow.AddMinutes(58)`, line 34); exceeding it sets `State='Timeout'` with an explicit note that "the remote run may still be active; it was not cancelled" (line 42) — i.e. a timeout here never attempts to cancel the actual GitHub run, consistent with its read-only, non-mutating design goal.
- Calls `exit 1` (line 48) on any terminal state other than `'Success'`.

## Findings

- Missing input validation: none of the four parameters are `[Parameter(Mandatory)]` (line 15) despite all being required; an omitted `-RunId` defaults to `0` (the `[long]` type default) and an omitted `-Repository` defaults to `$null`/empty, both of which would only surface as a `gh api` failure deep inside `Read-QuietGitHubJson` (`'GitHubStatusUnavailable'`, line 29) rather than an immediate, clear parameter-binding error naming the actual missing value.
- Security: the `--jq` projections used (lines 36–37: `'{status,conclusion,html_url,head_sha,run_started_at}'` and `'.jobs | map({id,name,status,conclusion,started_at,completed_at,runner_name})'`) are hardcoded, narrow, and allowlisted — a deliberate, good practice that avoids ever capturing or persisting broader run/job metadata (e.g. log URLs, secrets-adjacent fields) than strictly needed for the monitor, consistent with the script's own stated secrets-minimization goal.
- `Read-QuietGitHubJson` (lines 17–31) caps accumulated stdout at 128 KiB (`if($s.Json.Length+$e.Text.Length -gt 131072){throw 'RemoteStatusTooLarge'}`, line 28) — a sensible defensive bound against an unexpectedly huge API response, though it throws mid-accumulation rather than truncating, meaning a legitimately large (but valid) job list for a very wide matrix run could hard-fail this script entirely rather than degrade gracefully (e.g. by paginating further or just reporting job count without full detail). With `per_page=100` already capping jobs per page and no pagination loop for `>100` jobs (line 37), a run with more than 100 jobs would silently only ever see the first 100 — this is a real, if narrow, scalability gap (no `page=2` follow-up request).
- DESIGN: the `-jq` projection and polling pattern duplicate the general shape of "poll a status, write to status.json" seen in `Invoke-ContainerWorker.ps1`/`Invoke-ContainerColdStartWorker.ps1`'s own polling loops, but each implements its own ad hoc loop rather than sharing a common "poll until terminal" helper — a DRY opportunity across the worker family, not a bug in this file specifically.
- No companion Pester test found for `Invoke-GitHubRunWorker.ps1`.
- The 58-minute fixed deadline (line 34) is not parameterized; a legitimately longer-running matrix (e.g. a full release qualification across many platforms) exceeding 58 minutes would be reported as `'Timeout'` by this monitor even though the actual GitHub run might still succeed — since the script explicitly avoids cancelling the real run on timeout (good), the main cost of this hardcoded value is just a potentially premature/misleading local "Timeout" status for a run that later succeeds remotely, with no way to extend the budget from the call site.

## Verdict

Fit for purpose and notably careful about secrets/data minimization (no token handling, narrow jq projections, bounded buffer). The two concrete gaps worth prioritizing are: missing pagination beyond 100 jobs (line 37) for workflows with larger matrices, and the non-configurable 58-minute deadline (line 34) that can produce a false "Timeout" for legitimately longer-running remote workflows.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Read-only GitHub polling worker, with durable success/failure/cancellation/timeout reports.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
