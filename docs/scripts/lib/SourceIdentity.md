# SourceIdentity.psm1

## Library boundary

Located at `scripts/lib/SourceIdentity.psm1`. Load with `Import-Module ([IO.Path]::Combine($root,'scripts/lib/SourceIdentity.psm1')) -DisableNameChecking -ErrorAction Stop`. Import defines functions and explicit dependencies without running business operations. Paths use `System.IO.Path`. Effects remain owned by the calling operation and its preview contract.

Explicit export surface:

```powershell
Export-ModuleMember -Function 'Get-QuietBinaryInputs','Get-QuietManifestDigest','Get-QuietPeMachine','Get-QuietSourceFiles','Get-QuietWorkspaceBuildProjects','Get-QuietWorkspaceBuildSelection','Get-QuietWorkspaceDotNetHost','Get-QuietWorkspaceIdentity','Get-QuietWorkspacePackages','Get-QuietWorkspaceProjects','Get-QuietWorkspaceSuiteNames','Get-QuietWorkspaceSuiteSelection','Get-QuietWorkspaceTestSuites','New-QuietWorkspaceSuiteParameter','Read-QuietRepositoryValue','Test-QuietBuildManifest','Write-QuietBuildManifest'
```


## Scoped CI execution

Suite limits binary verification to the selected build closure; source drift still covers the checkout. Git reads pass command-local safe.directory for the exact checkout root, handling job-container ownership without a global configuration change. .cache is pruned before hashing large intermediate Docker caches.

## Purpose and usage

Common.ps1 loads deterministic source/binary identity helpers. `Get-QuietWorkspaceIdentity -WorkspaceRoot <root> -IncludeBinaries` verifies current source associations and output hashes. `Write-QuietBuildManifest` records project, configuration, RID, architecture, sources and direct binary files. Optional `-ReadyToRun` requires a real native R2R header; `-ReadyToRunTargets <rids>` declares selected child slots in portable manifests. `Test-QuietBuildManifest` rejects stale or modified output.

Portable distributions are supplied by `Get-QuietWorkspaceBuildProjects`, including both recall-tool frameworks and future declared consumers. Compiler inputs recursively follow explicit `ProjectReference` edges and linked `Compile Include` directories within the workspace. `Directory.Build.props` participates when present, so a changed warning policy invalidates existing receipts. DTDs, workspace escapes and dynamic/wildcard explicit include expressions fail. Core's RID publications remain separately verified. The catalogue companion regression includes a synthetic Packer dependency graph and a changed build-policy hash.

## Dependencies and side effects

Depends on WorkspaceProjects.ps1, RuntimeTargets.ps1 and Write-WorkspaceJson from Common.ps1. Reads source/compiled files; read-only Git metadata calls use Ci.Process.ps1. Only Write-QuietBuildManifest writes its output manifest. Source enumeration prunes generated output and rejects links. No publication, repository mutation or build is implicit.
The `.profilers` tool cache is generated input, excluded from source enumeration and repository LF
checks. Pinned third-party profiler files retain their original bytes and are not normalized as source.

## Critical review

- `scripts/lib/SourceIdentity.psm1:84` compares source snapshots before recording a build. ReadyToRun format verification precedes the receipt; a flag alone cannot qualify IL as precompiled output.
- `scripts/lib/SourceIdentity.psm1:115` rechecks hashes and RID architecture, including Linux R2R machine encoding. Older manifests without R2R fields remain portable-compatible.
- `scripts/lib/SourceIdentity.psm1:158` includes selected net10.0 RID slots as well as portable builds and embedded net11.0 publications. Inactive stale net10.0 slots are not treated as current qualification evidence.
- Hashes bind observed bytes to source inputs; they are not signatures or evidence that an unexecuted platform passed tests. The final Gallery package is rebuilt on Windows after source-revision matrix qualification.

## Verdict

One source/binary identity contract serves local tests, GitHub tests and packaging. Full platform execution is still a separate release requirement.

Internal source snapshots are generated evidence, not a committed workspace lock.
Get-QuietWorkspaceIdentity records the available Git revision and committed tree plus Dirty
and the digest of actual tracked/non-ignored untracked source content. A dirty checkout's tree
is its committed baseline; its source digest identifies the observed changes. Missing Git
metadata leaves revision/tree null and preserves the explicit transport-origin receipt.
External resources retain their dedicated pinned manifests. See
[source identity](../../README-source-identity.md). The commit integration campaign asserts
that an uncommitted edit changes the digest without changing the committed revision/tree.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

## Portable toolchain and backup boundary

scripts/SourceIdentity.psm1 prunes .dotnet before traversal and hashing, and excludes the
generated .json/.csproj/.props backup names produced by SDK/runtime/CI updaters. These local
payloads do not become compiler inputs or staged-snapshot source identities. The Locks suite
checks both exclusions with owned fixtures; ordinary source files continue to participate.

<!-- script-contract:begin -->
## Execution contract

Purpose: Enumerates source files while pruning generated directories and rejecting filesystem links.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

## Explicit library dependencies

Imports WorkspaceJson and BinaryHeaders directly; Common reuses the same writer and re-exports the PE reader. Ci.Process and RuntimeTargets are also explicit module dependencies for repository metadata and publication verification. These dependencies define commands without loading the product or performing business operations.

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/lib/SourceIdentity.psm1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
