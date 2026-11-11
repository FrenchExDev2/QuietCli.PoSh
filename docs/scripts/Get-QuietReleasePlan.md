# Get-QuietReleasePlan.ps1

`-ReadBatch -Revision <sha>` reads the triggering annotated tag, validates its optional `QuietCli-Release-Batch` JSON line, and verifies every batch tag's peeled commit on origin. It emits `is_leader` and `release_tags` in addition to the existing outputs. Only the first dependency-ordered member qualifies/publishes; followers finish after planning. Ordinary manual tags without a batch remain independent single releases. Missing/foreign remote refs fail before qualification. WhatIf makes no Git/network probe or output write.

## Purpose and usage

Resolve an explicit release tag against its owning manifest before starting release qualification or publishing prepared bytes.

```powershell
./scripts/Get-QuietReleasePlan.ps1 -Tag FrenchExDev2.QuietCli.Core.PoSh/v0.2.0-preview
./scripts/Get-QuietReleasePlan.ps1 -Tag FrenchExDev2.QuietCli.Core.PoSh/v0.2.0-preview -OutputPath ./outputs.txt -WhatIf
```

`-WorkspaceRoot` selects the source checkout. `-OutputPath` appends UTF-8/LF module, component and version outputs after dynamic business-target/version validation. Core and Git are enabled by metadata; Vagrant is disabled. WhatIf validates without writing. This script never tags, pushes, builds or publishes.

## Dependencies and effects

Imports [GalleryRelease](lib/GalleryRelease.md), which reads only the selected manifest through `Import-PowerShellDataFile`. No engine, native executable, dependency restoration or network request is needed. Output values come from a strict tag grammar; no unvalidated input is emitted as workflow commands.

## Findings and verdict

`scripts/Get-QuietReleasePlan.ps1` delegates policy to one shared resolver and guards its optional append with ShouldProcess. Exact version mismatches and disabled companion publication fail before outputs are written. The CI optimization companion case checks malformed tags, independently versioned manifests, output bytes and no-write preview. Core and Git have package preparation and validation paths; Vagrant remains disabled. This establishes local policy behavior, not hosted publication, environment tag permissions or the existence of the Gallery secret.

<!-- script-contract:begin -->
## Execution contract

Purpose: Validates a module-specific publication tag and optionally writes bounded GitHub job outputs.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
