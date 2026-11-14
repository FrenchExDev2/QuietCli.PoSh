# Sync-GitHubWorkflowsReadme.ps1

## Purpose and usage

Checks or regenerates docs/ci/github/README.md and generated job/dependency blocks in script-<workflow-basename>.md.

```powershell
./scripts/Sync-GitHubWorkflowsReadme.ps1
./scripts/Sync-GitHubWorkflowsReadme.ps1 -Apply -WhatIf
./scripts/Sync-GitHubWorkflowsReadme.ps1 -Apply -Confirm
```

WorkspaceRoot defaults to the repository root. Default mode is read-only and fails on stale content. Apply writes only generated blocks and the index, guarded per destination by ShouldProcess. It never creates missing authored workflow docs or updates their workflow-source-sha256 receipts. Review the corresponding doc and set its receipt to the actual Get-FileHash SHA-256 before regeneration. Required authored sections: Purpose, Triggers, Scripts and effects, Validation and limits.

## Parser prerequisite

WorkflowDocumentation calls Ensure-QuietResource to verify and, if necessary, selectively restore the pinned YamlDotNet payload through ShouldProcess. No preceding GitHub step is required. WhatIf performs no restoration and cannot parse with a missing dependency. An incompatible loaded assembly requires a fresh process.

## Dependencies and side effects

Uses WorkflowDocumentation.ps1 and its checksum-pinned restored YamlDotNet resource. Apply writes UTF-8/LF Markdown only. It validates every document before starting writes. WhatIf reports pending generated writes; no directory/file, Git mutation, build or publication is created.

## Critical review

- scripts/Sync-GitHubWorkflowsReadme.ps1:21 blocks unreviewed source drift before regeneration; Apply cannot silently requalify a changed workflow.
- The generated graph/table compares exactly against parsed YAML. Authored semantics still require review; the gate does not prove workflow correctness or render the diagram graphically.
- AutomationContracts.Tests.ps1 covers no-write preview, regeneration, literal dependency edges and graph/receipt/heading/index failures.

## Verdict

Regenerable structural documentation with separate authored review receipts, used by local/commit/GitHub checks.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [WorkflowDocumentation.psm1](lib/WorkflowDocumentation.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Checks workflow documentation receipts, generated job graphs and the regenerable GitHub index.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
