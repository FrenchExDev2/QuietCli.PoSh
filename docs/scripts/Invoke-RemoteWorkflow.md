# Invoke-RemoteWorkflow.ps1

## Purpose

Explicitly dispatch a GitHub Actions workflow on a selected remote ref, or list its ten most recent runs, through the authenticated GitHub CLI. The script never pushes local changes. See [qualification and profiling](../../README-qualification-when-where-how.md#profiling-reports-and-manual-pr-runs) for the PR procedure and [Watch-GitHubRun.ps1](Watch-GitHubRun.md) for following a run.

## Usage

Parameters:

- `Repository` (`string`, **mandatory**, validated against `^[\w.-]+/[\w.-]+$`) — GitHub `owner/repository`.
- `Workflow` (`string`, optional, default `'ci.yml'`) — workflow filename.
- `Ref` (`string`, optional) — required only when dispatching (not `-Status`); the script throws `ExplicitRefRequired` if dispatching without it.
- `Status` (`switch`, optional) — lists recent runs instead of dispatching.
- `WorkspaceRoot` (`string`, optional, default: parent of `$PSScriptRoot`) — QuietCli2 root, passed through to `Invoke-WorkspaceNative` as the working directory.

From the workspace root, after pushing the intended revision:

```powershell
./scripts/Invoke-RemoteWorkflow.ps1 -Repository FrenchExDev2/QuietCli.PoSh -Workflow ci.yml -Ref fix/develop-pr-gh-wf
./scripts/Invoke-RemoteWorkflow.ps1 -Repository FrenchExDev2/QuietCli.PoSh -Workflow quietcli2-readytorun.yml -Ref fix/develop-pr-gh-wf
./scripts/Invoke-RemoteWorkflow.ps1 -Repository FrenchExDev2/QuietCli.PoSh -Workflow quietcli2-readytorun.yml -Status
```

Replace the example ref with the pushed branch or tag to test. No `develop` fallback is applied: dispatch requires an explicit `-Ref`. The workflow must declare `workflow_dispatch` and exist on the repository's default branch; `-Ref` selects the revision to execute. See [GitHub's manual-run documentation](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).

The script exposes no workflow-input parameter; dispatch uses defaults from the selected workflow revision. The current `ci.yml` defaults to `suite=All` and `collect_performance=true`. Its `Run workflow` form in GitHub Actions allows explicit input selection. `quietcli2-readytorun.yml` declares no inputs. The two dispatches above start separate runs; an ordinary matching PR push already starts qualification, so only the second is needed to add A/B evidence to that push.

Add `-WhatIf` to preview without invoking `gh` or contacting GitHub. `-Confirm` uses the standard PowerShell confirmation prompt.

## Dependencies

- Dot-sources `Common.ps1` for the engine-independent `Invoke-WorkspaceNative` orchestration helper.
- Calls `gh run list ...` for status or `gh workflow run ...` for dispatch.
- Assumes `gh` is installed, on `PATH`, and already authenticated (no auth/login handling in this script); if `gh` is missing or unauthenticated, the failure surfaces only through `Invoke-WorkspaceNative`'s generic "Workspace operation failed" exception.
- Network dependency: both code paths contact GitHub's API via `gh`.

## Side effects

- Dispatching a workflow run (`gh workflow run`) is a genuine, remote, stateful side effect — it starts a GitHub Actions run in the named repository and ref. This is irreversible from this script's perspective (no "undo"/cancel is offered here).
- No local filesystem writes beyond whatever `Invoke-WorkspaceNative`'s optional `-LogPath` would do (not used here, since no `LogPath` is passed through).
- No git state mutation locally.

## Limits

- `-Status` lists runs for the workflow, across refs; inspect the reported branch and revision before associating evidence with a PR.
- Dispatch does not wait for completion, select a run ID or attach results to a PR comment. A manual run remains separate from the PR-triggered required checks.
- Authentication and workflow availability are checked by `gh`; the script does not log in or change repository settings.
- `SupportsShouldProcess` guards both branches before any native invocation. A successful preview is not evidence that a remote run will succeed.

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

Purpose: Explicit GitHub Actions dispatch or status through the locally configured gh CLI.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
