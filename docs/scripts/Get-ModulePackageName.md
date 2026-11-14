# Get-ModulePackageName.ps1

## Purpose and usage

Read a `.psm1` without importing it and infer its package name using this repository's matching `.psm1`/`.psd1` filename convention. A sibling manifest, when present, must agree with that filename through `RootModule` and its optional `PrivateData.QuietCli.PackageName` declaration. Arbitrary PowerShell code cannot establish a unique Gallery name by itself; a standalone file returns a candidate name with `HasManifest=false`.

```powershell
./scripts/Get-ModulePackageName.ps1 -Path ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psm1
# FrenchExDev2.QuietCli.Core.PoSh

./scripts/Get-ModulePackageName.ps1 -Path ./FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psm1 -RequireManifest -AsObject
```

`-AsObject` returns Name, complete Version, GUID, ModulePath, ManifestPath, HasManifest, declared Publishable and Dependencies. `-RequireManifest` rejects a standalone script module. Default output is the name string. `-WhatIf` previews the read and returns before importing the helper or reading files.

## Dependencies and effects

Uses [ModulePackage](lib/ModulePackage.md) and PowerShell's parser. No product module import, native command, compilation, network request, file mutation, tagging or publication occurs. An existing Gallery entry is neither queried nor created.

## Critical review and verdict

`scripts/Get-ModulePackageName.ps1` guards its operation with ShouldProcess. The shared helper parses UTF-8 source and reads only a literal manifest hashtable. Contradictory names, malformed source, invalid UTF-8 and executable manifests fail explicitly. The Gallery identity tests cover Core/Git/Vagrant and an unrelated module name, standalone reads, full metadata, dependency preservation, no-write preview and a module-body execution sentinel. This validates identity inference, not module qualification or remote Gallery availability.

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [ModulePackage.psm1](lib/ModulePackage.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Reads the package name from a .psm1 filename and checks its optional sibling manifest without importing code.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
