# ModulePackage.psm1

## Purpose and usage

`Get-QuietModulePackageIdentity -Path <module.psm1> [-RequireManifest]` implements the shared package identity reader behind [Get-ModulePackageName](../Get-ModulePackageName.md), Gallery staging/validation and release-tag resolution. The package name follows the script-module basename; no Core/Git name mapping or short-name substitution is performed.

With a sibling `.psd1`, require one literal hashtable whose `RootModule` exactly matches the script module's filename. Preserve the manifest version, prerelease suffix, GUID, dependency declarations and publication flag. An optional `PackageName` must equal the inferred name. Without a manifest, version/policy are unknown and `HasManifest=false`; `-RequireManifest` rejects that state.

## Dependencies and effects

PowerShell 7.6+ parser and strict UTF-8 reads. Imports declare/export one function only. Source is limited to 8 MiB and the manifest to 1 MiB. AST parsing never executes module code; manifest `SafeGetValue()` rejects executable expressions. No product engine, native process, dependency restoration, network access or writes are involved.

## Critical review and verdict

`scripts/lib/ModulePackage.psm1` enforces the repository's same-basename convention. A differently named root script referenced by another manifest cannot be uniquely inferred under this contract and must be handled explicitly rather than guessed. Gallery identity tests use independent names and malicious/malformed fixtures; staged-package tests verify unchanged source bytes and installed module/dependency identity. This helper does not authorize publication or certify business behavior.

<!-- script-contract:begin -->
## Execution contract

Purpose: Reads a script module and its optional literal manifest without executing either file.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
