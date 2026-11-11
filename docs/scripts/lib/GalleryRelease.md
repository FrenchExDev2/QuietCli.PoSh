# GalleryRelease.psm1

## Purpose and usage

`Resolve-QuietGalleryReleaseTag -WorkspaceRoot <checkout> -Tag <tag>` maps independent public tag namespaces to their source modules:

| Tag namespace | Owning project | Publication capability |
| --- | --- | --- |
| `QuietCli/v<version>` | Core | Public Core packaging available |
| `QuietCli.Git/v<version>` | Git | Reserved; rejected while nonpublishable or public packaging is unavailable |
| `QuietCli.Vagrant/v<version>` | Vagrant | Reserved; rejected while nonpublishable or public packaging is unavailable |

The complete tag version must match the owning manifest's `ModuleVersion` and optional `PSData.Prerelease`. Other projects may have different versions. No numeric bump, staged override or timestamp is inferred.

## Dependencies and effects

PowerShell 7.6+ and its data-file reader. Import declares/exports one function; resolution reads one manifest and returns a small plan without modifying files, importing product code or contacting GitHub/Gallery.

## Findings and verdict

`scripts/lib/GalleryRelease.psm1` rejects malformed/case-mismatched tags, newline suffixes, source-version mismatches, missing/false `Publishable` and unavailable public packaging. It deliberately retains the companions' current nonpublication boundary. Before activating those namespaces, implement public module/dependency staging, independent package validation and offline installation/import qualification. Tags and local tests do not establish platform or real-provider qualification.

<!-- script-contract:begin -->
## Execution contract

Purpose: Resolves an independently versioned release tag against its owning source manifest.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
