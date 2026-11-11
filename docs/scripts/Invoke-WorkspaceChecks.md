# Invoke-WorkspaceChecks.ps1

## Purpose and usage

Read-only ordered registry used by standalone checks, Commit-Workspace and scripts-docs-check.yml.

```powershell
./scripts/Invoke-WorkspaceChecks.ps1
./scripts/Invoke-WorkspaceChecks.ps1 -Check GitHubWorkflowDocs,ScriptShouldProcess
./scripts/Invoke-WorkspaceChecks.ps1 -SkipCheck Credits
```

WorkspaceRoot selects the exact working tree or exported index snapshot. Check limits the registry selection; omitted runs all. SkipCheck reports an explicit Skipped result and never a successful check. Unknown names fail. Add future checks in the single registry, without duplicating their sequence in Commit-Workspace or YAML.

## Dependencies and side effects

Registry order: TestCaseMetadata, ScriptsReadme, GitHubWorkflowDocs, ScriptShouldProcess, Resources, ScriptContracts, DocsCredits, Credits. TestCaseMetadata statically validates the complete discovered companion catalogues and their optional guards/policies without running cases or loading a product engine. Every entry checks its contract without applying documentation. Guarded parser preparation may write prerequisite resource/cache files. No lock refresh, build, stage, commit, push or publication occurs; the hash-bound policy exception documents the delegated preparation boundary. NoSyncChecks in the commit entry point retains classification and script safety; generic SkipCheck can explicitly omit either.

## Critical review

- scripts/Invoke-WorkspaceChecks.ps1:17 is the shared extension point. Compatibility No* switches in Commit-Workspace map to SkipCheck names; new generic checks run by default.
- Fails at the first failed gate, retaining its error. Skips are explicit and cannot be used as release qualification evidence.
- AutomationContracts.Tests.ps1 covers a real selected workflow gate, unknown names and skip reporting; CommitWorkspace.Tests.ps1 preserves index/WhatIf/commit-once boundaries and mutation assertions.

## Verdict

Shared check composition with explicit scope; repository mutation remains the responsibility of the guarded commit entry point.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs the shared ordered check registry used by standalone validation, GitHub and commit preparation.

Boundary: **ReadOnly**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
