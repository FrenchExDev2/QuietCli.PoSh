# ContainerInputs.ps1

`Copy-QuietContainerInputs -WorkspaceRoot $root -Destination $stage` prepares the explicit inputs
used by `Invoke-ContainerWorker.ps1`. It copies scripts, build metadata, documentation, GitHub
definitions, discovered projects and built module resources. Root Markdown documents and the
named SDK/package/source locks are included; `.env`, arbitrary root JSON files, Git internals,
intermediate `bin`/`obj` directories and old reports are excluded.

For ordinary companion suites, the helper reads the host's existing `project.assets.json` files
and copies only their restored package directories into `artifacts/nuget-cache`. The container sets
`NUGET_PACKAGES=/workspace/artifacts/nuget-cache`, allowing mutation builds without guest network
access. Preparation does not download, restore or build; a referenced package missing from the
restored host cache is an error. NuGet extraction paths must contain exactly a package ID and version;
rooted paths, separators in either component and traversal are rejected.

`-NativeOnly` selects the independent C/PTY campaign inputs and omits modules and NuGet packages.
`-WhatIf` returns before creating directories or copying inputs; `-Confirm` uses standard PowerShell
confirmation. The executable caller guards the overall operation and delegates its approved copy.

The focused Core case `GitHub CI container inputs include docs and restored packages without secrets
or path escapes` uses small filesystem fixtures, including absent-destination preview and hostile
package paths. It starts no container and performs no network operation.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Stages source, documentation, built modules and restored packages for networkless companion execution.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
