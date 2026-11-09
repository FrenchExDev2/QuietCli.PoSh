# Invoke-RemoteWorkflow.ps1

## Purpose

A thin, explicit wrapper around the `gh` (GitHub CLI) command for dispatching or checking the status of a GitHub Actions workflow in a named repository. It solves the problem of ad hoc `gh` invocations scattered through developer muscle-memory by giving the monorepo one canonical, parameter-validated entry point for "run this workflow on that ref" or "show me recent runs." No other script in `scripts/` references `Invoke-RemoteWorkflow.ps1` (confirmed by search), so it is a standalone operator/developer tool, not part of the automated CI chain — it is the kind of thing a human (or an agent under instruction) runs manually to kick off or inspect a remote run, complementing `Watch-GitHubRun.ps1` for following one afterward.

## Usage

Parameters:
- `Repository` (`string`, **mandatory**, validated against `^[\w.-]+/[\w.-]+$`) — GitHub `owner/repository`.
- `Workflow` (`string`, optional, default `'ci.yml'`) — workflow filename.
- `Ref` (`string`, optional) — required only when dispatching (not `-Status`); the script throws `ExplicitRefRequired` if dispatching without it.
- `Status` (`switch`, optional) — lists recent runs instead of dispatching.
- `WorkspaceRoot` (`string`, optional, default: parent of `$PSScriptRoot`) — QuietCli2 root, passed through to `Invoke-WorkspaceNative` as the working directory.

Examples:
```powershell
./scripts/Invoke-RemoteWorkflow.ps1 -Repository FrenchExDev/FrenchExDev_i2 -Status
./scripts/Invoke-RemoteWorkflow.ps1 -Repository FrenchExDev/FrenchExDev_i2 -Workflow ci.yml -Ref main
```

## Dependencies

- Dot-sources `Common.ps1` (line 18) for `Invoke-WorkspaceNative`.
- Shells out to `gh` (the GitHub CLI) — `gh run list ...` for status (line 19) or `gh workflow run ...` for dispatch (line 20).
- Assumes `gh` is installed, on `PATH`, and already authenticated (no auth/login handling in this script); if `gh` is missing or unauthenticated, the failure surfaces only through `Invoke-WorkspaceNative`'s generic "Workspace operation failed" exception.
- Network dependency: both code paths contact GitHub's API via `gh`.

## Side effects

- Dispatching a workflow run (`gh workflow run`) is a genuine, remote, stateful side effect — it starts a GitHub Actions run in the named repository and ref. This is irreversible from this script's perspective (no "undo"/cancel is offered here).
- No local filesystem writes beyond whatever `Invoke-WorkspaceNative`'s optional `-LogPath` would do (not used here, since no `LogPath` is passed through).
- No git state mutation locally.

## Findings

- DESIGN: The script has no way to pass GitHub workflow *inputs* (`gh workflow run` supports `-f key=value` / `--json`), nor any way to select among multiple same-named workflow runs, nor to poll/wait for completion (that's `Watch-GitHubRun.ps1`'s job, but there is no cross-reference or hint in this script's docstring pointing a caller there) — a user who dispatches here has no built-in way to then watch the run without separately discovering `Watch-GitHubRun.ps1`.
- CONVENTION: No explicit confirmation/`-WhatIf` support (`[CmdletBinding()]` alone, no `SupportsShouldProcess`) before an action that remotely starts a CI pipeline — unlike `Invoke-RunProfile.ps1`, which wraps its own run in `$PSCmdlet.ShouldProcess`. Starting a real GitHub Actions run (consuming minutes/compute, potentially deploying something) seems at least as consequential as running a local profile, so the asymmetry is a design smell.
- Testability: No Pester test found referencing `Invoke-RemoteWorkflow`. Because its logic is a two-branch dispatch to `Invoke-WorkspaceNative`, the only testable surface without mocking `gh`/network is the parameter validation (`Repository` regex, the `ExplicitRefRequired` throw) — none of which is exercised by any existing test.
- No input validation on `Workflow` (free-form string passed straight to `gh`) — low risk since `gh` itself will reject a bad filename, but it is inconsistent with the strict regex validation applied to `Repository`.
- No secrets are handled directly in this script — `gh`'s own token storage is relied upon, which is appropriate and not itself a finding.

## Verdict

The script is simple, readable, and does what its name says, but it lacks any confirmation gate before a consequential remote action and has zero test coverage of its own parameter logic. Highest-priority fix: add `SupportsShouldProcess`/`ShouldProcess` around the dispatch branch so an accidental or scripted invocation cannot silently kick off a real CI run.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
