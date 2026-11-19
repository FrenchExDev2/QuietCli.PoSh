# Build-Workspace.ps1

<!-- script-source:begin -->
Source file: [`Build-Workspace.ps1`](../../scripts/Build-Workspace.ps1)
<!-- script-source:end -->

## Scoped CI execution

Suite selects the test module and transitive RequiredModules closure. A scoped owned solution contains its projects; undeclared ProjectReferences fail before compilation. All preserves the complete solution. Incremental compilation reuses valid MSBuild outputs; portable publications remain --no-build. Matrix calls publish only their tested RuntimeIdentifier; packaging retains every required RID. WhatIf creates no scoped solution.

`ReuseVerifiedBuild` always restores that complete selected solution before returning verified
cached distributions or narrowing compilation to stale/unpublished projects. Binary cache archives
do not contain `obj/project.assets.json`; downstream offline container staging needs those assets
to find the restored dependency closure. A cache hit therefore skips compilation and publication,
while restore still runs with vulnerability auditing enabled. It never restores unselected companions.
The layout regression covers an empty intermediate tree, complete reuse, documentation-only
compilation beside cached products, restore failure and an omitted-restore mutant.

## Purpose and usage

Compiles `Quietly.slnx` once in Release by default, then prepares the portable distributions declared by the discovered packages, without tests or registry publication. Both local launchers and GitHub workflows use this same entry point.

```powershell
# Rebuild every C# project in Quietly.slnx, without preparing distributions.
./scripts/Build-Workspace.ps1 -SolutionOnly
# Local portable build; all six net11.0 distributions remain embedded.
./scripts/Build-Workspace.ps1 -Configuration Release
# GitHub matrix row: precompile the RID actually tested.
./scripts/Build-Workspace.ps1 -Suite Core -Configuration Release -RuntimeIdentifier linux-musl-arm64 -ReadyToRun -ReadyToRunRuntimeIdentifier linux-musl-arm64
# Windows x64 packaging runner: precompile every release RID.
. ./scripts/lib/RuntimeTargets.psm1
./scripts/Build-Workspace.ps1 -Configuration Release -ReadyToRun -ReadyToRunRuntimeIdentifier @((Get-QuietRuntimeTargets $PWD.Path).Rid)
```

`WorkspaceRoot` defaults to the repository root; `Configuration` accepts Release/Debug. `RuntimeIdentifier` selects embedded net11.0 distributions (all six by default). `ReadyToRun` enables Crossgen2 for `ReadyToRunRuntimeIdentifier`, defaulting to `LocalRuntimeIdentifier`, itself the actual host RID. A precompiled target must also be in `RuntimeIdentifier`. Supplying targets without the switch fails before compilation.

`SolutionOnly` builds the selected solution and its declared target frameworks with incremental MSBuild reuse. The solution groups the three production packages under `src` and all `*.Tests.PoSh` companions under `test`; pure PowerShell packages appear as solution files. Repository-wide `Directory.Build.props` enables `TreatWarningsAsErrors=true` for direct project builds and solution builds alike. This mode requires no PTY publication receipts, does not update `lib/` distributions or their manifests, and rejects runtime-publication options. Standard `-WhatIf` returns before any build, restore or filesystem effect.

## Outputs and dependencies

All distributions are prepared through [WorkspacePublication](lib/WorkspacePublication.md)
in a fresh staging directory before replacing their files by rename. This also permits
rebuilding while an existing PowerShell session uses a published assembly on Windows.
That session keeps its previous assembly until restarted. Locked previous files are
retained under `.quiet-previous-<id>` with a warning, rather than blocking dotnet's copy
step. Failed publication leaves existing files intact; promotion errors restore replaced
files. Concurrent builds/imports into the same output remain unsupported.

Requires the pinned SDK/runtime packs, Common.ps1, valid PTY receipts and NuGet restore availability. Commands use Ci.Process.ps1. Portable net10.0 and net11.0 outputs remain at `lib/inprocess` and `lib/engine`. ReadyToRun net10.0 outputs live at `lib/inprocess/<rid>`; corresponding net11.0 outputs at `lib/engine/<rid>`. Other net11.0 distributions stay IL. Portable manifests list only this build's selected slots, so stale directories cannot silently override a later portable build. Existing generated directories are retained; no source, profile or registry is changed.

Every manifest binds source and binary hashes. ReadyToRun receipts require the CLR native header and RTR signature; Linux architecture checks account for the native OS override in the PE machine field. Protocol.ps1 selects a slot for the actual CLR and RID, otherwise portable IL.

`Get-QuietWorkspaceBuildProjects` supplies `Package`, `Project`, `TargetFramework` and `Output` from each manifest's inert `PrivateData.QuietCli.BuildProjects` declaration. Before compilation, the script checks that every declared project belongs to the solution and snapshots its compiler inputs. The solution builds every target framework, including tooling projects that have no packaged output. Each declared portable output is then prepared with `dotnet publish --no-build` (which also disables restore), and its integrity receipt is written only after success. No common solution `-o` directory mixes project outputs. A failed solution build prevents all distribution preparation.

RID/ReadyToRun engine publications remain separate compilations because their architecture and Crossgen2 settings differ from portable builds. This is the only remaining compilation by project in the shared build. Adding a compiled consumer requires adding its project to the solution and declaring its outputs; neither this script nor the local/GitHub launchers needs another project list. See [the catalogue contract](../README-workspace-projects.md#compiled-distributions).

## Critical review

- The build rejects targets outside the published set. The two target frameworks are deliberately separate outputs; a Windows R2R assembly is never placed in the universal portable slot.
- Targeted publications record verified ReadyToRun output. Header presence establishes format, not complete AOT execution or a performance improvement.
- `ReadyToRun.Tests.ps1` covers all 64 target subsets, 1,152 routing properties, malformed manifests/images and two routing mutants, plus one solution build per invocation, declared no-build portable publications, no-effect preview, SolutionOnly and fail-fast behavior. `WorkspaceProjects.Tests.ps1` verifies new consumer declarations, generated outputs, malformed declarations and three targeted catalogue mutants. Actual twelve-publication compilation and a Linux Docker import are separate integration evidence.
- Crossgen2 host support matters: Linux matrix jobs precompile their Linux RID; the Windows x64 packaging runner builds all six. Arbitrary cross-OS compilation is not assumed. See the official [.NET R2R restrictions](https://learn.microsoft.com/en-us/dotnet/core/deploying/ready-to-run#cross-platformarchitecture-restrictions).

## Verdict

ReadyToRun is enabled explicitly by GitHub qualification and packaging. The manual A/B workflow keeps its IL baseline and separate candidate; its timings do not gate develop delivery.



<!-- script-contract:begin -->
## Execution contract

Purpose: Builds the solution and prepares declared distributions; does not run tests or publish packages.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/Build-Workspace.ps1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
