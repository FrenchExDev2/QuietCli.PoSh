# Watch-GitHubRun.ps1

## Purpose

Lets a developer or an automated qualification step observe an *already-dispatched* GitHub Actions
run to completion, in a visible window, without being able to dispatch, retry, or cancel it — the
business goal is a clean separation between "triggering CI" (owned by `Invoke-RemoteWorkflow.ps1`, per
`README-qualification.md:128`: "`Invoke-RemoteWorkflow.ps1` ... dispatches a selected workflow with
`-Ref`; `Watch-GitHubRun.ps1` monitors an existing `-RunId` without dispatching, retrying or cancelling
it") from "watching it happen." It is a human/CI-facing entry point, not something else in
`scripts/` calls programmatically; `README-qualification.md` documents it as the companion to
`Invoke-RemoteWorkflow.ps1` for the remote-qualification workflow.

## Usage

```
[CmdletBinding()]param(
    [Parameter(Mandatory)][long]$RunId,
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [ValidatePattern('^[\w.-]+/[\w.-]+$')][string]$Repository='FrenchExDev2/QuietCli.PoSh'
)
```

- `RunId` (long, mandatory) — the existing GitHub Actions run identifier to observe.
- `WorkspaceRoot` (string, optional) — QuietCli2 monorepo root; defaults to the script's parent
  directory.
- `Repository` (string, optional, validated as `owner/repo`) — GitHub repository to observe; defaults
  to `'FrenchExDev2/QuietCli.PoSh'`.

Example:

```powershell
./scripts/Watch-GitHubRun.ps1 -RunId 123456789 -Repository myorg/myrepo
```

## Dependencies

- Dot-sources `Common.ps1` (line 14), providing `Write-WorkspaceJson`, `Wait-WorkspaceWorker`, and
  transitively `Invoke-CiProcess`/`ConvertTo-CiArgument`.
- Hard platform requirement: `if(!$IsWindows){throw 'Use the Windows visible-monitor host launcher'}`
  (line 15) — this script only runs on Windows; it is not cross-platform despite the rest of the
  QuietCli2 pipeline supporting Linux RIDs.
- Launches `scripts/Invoke-GitHubRunWorker.ps1` as a *hidden* background `pwsh` process (line 19) —
  that worker is presumably the one that actually shells out to `gh` (GitHub CLI) to poll run status,
  though that file was outside this review's scope.
- Launches `scripts/Watch-Tests.ps1` as a *visible* (`-WindowStyle Normal`) `pwsh` process (line 21) —
  this is the actual monitoring window; `Watch-GitHubRun.ps1` itself does not render any table — it
  delegates 100% of the UI to `Watch-Tests.ps1` (reviewed separately).
- Relies on `Wait-WorkspaceWorker` (in `Common.ps1`) to supervise both processes, restart a crashed
  monitor window up to 3 times, enforce a hard 3600-second timeout, and persist the final
  `summary.json`/`status.json`.

## Side effects

- Creates a new run directory `artifacts/github/<RunId>-<6-hex-chars>` (lines 16-17).
- Starts two new OS processes: a hidden worker (`Invoke-GitHubRunWorker.ps1`, redirected stdout/stderr
  to log files in the run directory) and a visible monitor window (`Watch-Tests.ps1`).
- Prints a one-line "Monitor: pwsh -File ..." reopen command to the pipeline (line 22) — satisfying the
  AGENTS.md "give the user the command ... to reopen it" requirement.
- Blocks (via `Wait-WorkspaceWorker`) until the worker process exits, a 3600-second timeout elapses, or
  the monitor fails 3 times — then writes `summary.json`/`status.json` if the worker didn't already
  (that write/termination logic lives in `Common.ps1`'s `Wait-WorkspaceWorker`, reviewed there).
- Throws `"GitHub run did not succeed: $run"` (line 25) if the final recorded state isn't `Success`,
  which makes this script usable directly as a CI gate on remote-run outcome.
- No GitHub Actions mutation from this script itself — it dispatches nothing, retries nothing, cancels
  nothing, exactly as documented. (Whether the *worker* it launches, `Invoke-GitHubRunWorker.ps1`, ever
  mutates anything on the GitHub side was outside this review's scope.)

## Findings

- No bug found in the delegation/timeout/retry plumbing itself — it correctly reuses the shared
  `Wait-WorkspaceWorker` supervisor rather than reimplementing process supervision, which is good
  reuse/DRY discipline versus writing a bespoke wait loop here.
- CONVENTION (monitoring-window rules): this script fully satisfies the AGENTS.md requirement that
  "every test run started by an agent also gets a visible PowerShell Core (pwsh) monitoring window ...
  opened explicitly" (line 21, `-WindowStyle Normal`) and prints the reopen command (line 22). However,
  it hardcodes a 3600-second (1 hour) timeout (line 23) with no parameter to override it — a GitHub
  Actions run that legitimately takes longer than an hour (plausible for a full qualification matrix)
  would be killed and reported as `Timeout` purely due to this script's hardcoded value, not any real
  problem with the run. This should be a parameter, not a literal.
- DESIGN: `-RunId` as `[long]` with no additional validation beyond the type constraint — a
  negative or zero `RunId` would be accepted syntactically and only fail later, deep inside whatever
  `gh` call `Invoke-GitHubRunWorker.ps1` makes, rather than failing fast with a clear message here.
  Minor, but it's the kind of "missing input validation" the review brief calls out specifically.
- DESIGN: the actual table/UI rendering logic lives entirely in `Watch-Tests.ps1`, so this script
  itself cannot be faulted for table formatting — see that script's dedicated review for the
  UTF-8/Unicode-box/`Duration`-column findings, all of which apply transitively here since this script
  is one of `Watch-Tests.ps1`'s launchers.
- Testability gap: no Pester test references `Watch-GitHubRun.ps1` by name in either `*.Tests.PoSh`
  project (searched, no hits) — consistent with it being a remote/network-dependent, inherently
  hard-to-unit-test entry point (it needs a real dispatched GitHub run to observe). No fake/mocked
  `Invoke-GitHubRunWorker.ps1` harness was found either, so even the pure orchestration logic in this
  script (run-directory creation, the 3600s timeout, the final `Success`-vs-throw check) has no
  isolated test — it could in principle be tested by substituting a fake worker script that writes a
  deterministic `status.json`, similar to how `Package.Tests.ps1` fakes `Test-WorkspacePackage.ps1`
  inputs, but no such test exists today.
- No security concern beyond standard "this needs GitHub API access" assumptions — `Repository` is
  validated by regex against path-injection-shaped input (line 13), which is reasonable given it likely
  flows into a `gh` command inside the worker.

## Verdict

Does exactly what its name and the qualification README promise — observe without dispatching,
retrying or cancelling — and correctly reuses the shared monitor/worker-supervision infrastructure.
The most important fix is making the hardcoded 3600-second timeout (line 23) an overridable parameter,
since a legitimately long-running GitHub Actions run would otherwise be killed and misreported as a
timeout failure purely by this script's choice of constant.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Monitors one explicitly selected existing GitHub run; does not dispatch, retry or cancel it.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
