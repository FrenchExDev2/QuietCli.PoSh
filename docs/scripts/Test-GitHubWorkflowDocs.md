# Test-GitHubWorkflowDocs.ps1

## Purpose and usage

Read-only RaC entry point: ./scripts/Test-GitHubWorkflowDocs.ps1 [-WorkspaceRoot <root>]. Calls Sync-GitHubWorkflowsReadme.ps1 without Apply. Missing matching docs, stale source receipts, absent required sections or generated graph/index drift are blocking errors.

## Parser prerequisite

WorkflowDocumentation calls Ensure-QuietResource to verify and, if necessary, selectively restore the pinned YamlDotNet payload through ShouldProcess. No preceding GitHub step is required. WhatIf performs no restoration and cannot parse with a missing dependency. An incompatible loaded assembly requires a fresh process.

## Dependencies and side effects

Uses the generator and WorkflowDocumentation.ps1. Documentation comparison performs no writes and runs no workflow. Guarded parser preparation may write the missing resource/cache; the hash-bound policy exception documents this delegated boundary, and ambient WhatIf propagates to preparation.

## Critical review

- scripts/Test-GitHubWorkflowDocs.ps1:11 delegates rather than duplicating contract logic.
- The generator's malformed/drift fixtures supply the business assertions; Invoke-WorkspaceChecks integration verifies selection and explicit skip reporting.
- Currency and structural correspondence are checked; semantic completeness, graphical rendering and actual hosted execution are separate evidence.

## Verdict

One blocking check shared by GitHub automation and both Commit-Workspace tree modes.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Read-only workflow documentation gate; fails for missing, stale or inconsistent contracts.

Boundary: **ReadOnly**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
