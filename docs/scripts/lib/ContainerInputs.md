# ContainerInputs.psm1

<!-- script-source:begin -->
Source file: [`lib/ContainerInputs.psm1`](../../../scripts/lib/ContainerInputs.psm1)
<!-- script-source:end -->

## Library boundary

Located at `scripts/lib/ContainerInputs.psm1`. Load with `Import-Module ([IO.Path]::Combine($root,'scripts/lib/ContainerInputs.psm1')) -DisableNameChecking -ErrorAction Stop`. Import defines functions and explicit dependencies without running business operations. Paths use `System.IO.Path`. Effects remain owned by the calling operation and its preview contract.

Explicit export surface:

```powershell
Export-ModuleMember -Function 'Copy-QuietContainerInputs'
```


`Copy-QuietContainerInputs -WorkspaceRoot $root -Destination $stage` prepares the explicit inputs
used by `Invoke-ContainerWorker.ps1`. It copies scripts, build metadata, documentation, GitHub
definitions, discovered projects and built module resources. Root Markdown documents and the
named SDK/package/build inputs are included; `.env`, arbitrary root JSON files, Git internals,
intermediate `bin`/`obj` directories and old reports are excluded. The optional `-ContainerRuntime`
selection, or the source checkout's runtime key when omitted, creates a fresh staged `.env` containing
only `QUIET_CONTAINER_RUNTIME`. Unrelated private assignments are never copied. The caller forwards
its effective runtime explicitly; `-NativeOnly` omits this dotenv preparation.

Root build inputs explicitly include `Quietly.slnx` and `Directory.Build.props`, preserving the same solution inventory and warning-as-error policy in local and GitHub container staging. The container-input regression asserts both files are copied, while private root files remain excluded.

Existing `src/<Group>/scripts` directories for discovered solution groups are copied with their relative paths. The Git reference tests use the same companion generator on the host and in the staged Linux checkout.

Grouped solutions and all source `.props`, `.targets` and `NuGet.Config` files retain their relative
paths, including inherited policies between a companion and its module directories and shared imports.
Generated directories remain excluded by the source enumerator.

For ordinary companion suites, the helper reads the host's existing `project.assets.json` files
and copies only their restored package directories into `artifacts/nuget-cache`. The container sets
`NUGET_PACKAGES=/workspace/artifacts/nuget-cache`, allowing mutation builds without guest network
access. Preparation does not download, restore or build; a referenced package missing from the
restored host cache is an error. NuGet extraction paths must contain exactly a package ID and version;
rooted paths, separators in either component and traversal are rejected.

The host build restores its selected solution even when every distribution is reused from a binary
cache, and before narrowing compilation to an unpublished documentation project. This materializes
the assets that staging consumes on cold runners; restored binaries alone do not supply package metadata.

Package copies include hidden files with `-Force`, particularly NuGet's `.nupkg.metadata`
extraction marker. Both the restored source and staged package must contain that marker;
an incomplete cache fails before container creation. Missing the marker on Linux causes NuGet
to attempt another download even when the package's assemblies were copied.

`-NativeOnly` selects the independent C/PTY campaign inputs and omits modules and NuGet packages.
`-WhatIf` returns before creating directories or copying inputs; `-Confirm` uses standard PowerShell
confirmation. The executable caller guards the overall operation and delegates its approved copy.

The focused Tooling case `GitHub CI container inputs include docs and restored packages without secrets
or path escapes` uses small filesystem fixtures, including absent-destination preview, a hidden
extraction-marker hash check, rejection of an incomplete package and hostile package paths.
It starts no container and performs no network operation.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Selects existing script directories owned by discovered solution groups.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/lib/ContainerInputs.psm1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
