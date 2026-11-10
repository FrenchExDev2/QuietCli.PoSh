# SourceIdentity.ps1

## Purpose and usage

Common.ps1 loads deterministic source/binary identity helpers. `Get-QuietWorkspaceIdentity -WorkspaceRoot <root> -IncludeBinaries` verifies current source associations and output hashes. `Write-QuietBuildManifest` records project, configuration, RID, architecture, sources and direct binary files. Optional `-ReadyToRun` requires a real native R2R header; `-ReadyToRunTargets <rids>` declares selected child slots in portable manifests. `Test-QuietBuildManifest` rejects stale or modified output.

## Dependencies and side effects

Depends on WorkspaceProjects.ps1, RuntimeTargets.ps1 and Write-WorkspaceJson from Common.ps1. Reads source/compiled files; read-only Git metadata calls use Ci.Process.ps1. Only Write-QuietBuildManifest writes its output manifest. Source enumeration prunes generated output and rejects links. No publication, repository mutation or build is implicit.

## Critical review

- `scripts/SourceIdentity.ps1:81` compares source snapshots before recording a build. ReadyToRun format verification precedes the receipt; a flag alone cannot qualify IL as precompiled output.
- `scripts/SourceIdentity.ps1:112` rechecks hashes and RID architecture, including Linux R2R machine encoding. Older manifests without R2R fields remain portable-compatible.
- `scripts/SourceIdentity.ps1:155` includes selected net10.0 RID slots as well as portable builds and embedded net11.0 publications. Inactive stale net10.0 slots are not treated as current qualification evidence.
- Hashes bind observed bytes to source inputs; they are not signatures or evidence that an unexecuted platform passed tests. The final Gallery package is rebuilt on Windows after source-revision matrix qualification.

## Verdict

One source/binary identity contract serves local tests, GitHub tests and packaging. Full platform execution is still a separate release requirement.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Enumerates source files while pruning generated directories and rejecting filesystem links.

Boundary: **Library**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
