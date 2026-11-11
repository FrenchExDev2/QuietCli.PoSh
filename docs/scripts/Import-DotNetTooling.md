# Import-DotNetTooling.ps1

## Purpose

Perform the initial copy of the shared .NET tooling into this repository's entry-point,
library, companion-test and documentation layout.

## Usage and parameters

```powershell
./scripts/Import-DotNetTooling.ps1 -SourceWorkspace C:/code/FrenchExDev/FrenchExDev_i2 -WhatIf
```

SourceWorkspace explicitly selects the source workspace. DestinationRoot defaults to
this QuietCli checkout. The fixed inventory contains eleven authored source/guide files.

## Dependencies and effects

Uses PowerShell/.NET file APIs only. All source files are validated first. Approval
creates missing parent directories and copies UTF-8/LF text with initial path adaptation.
Existing destination files are always preserved, including repository-specific integration.

## Findings

- scripts/Import-DotNetTooling.ps1:39 guards every initial copy.
- This is an initial importer, not an update synchronizer: maintained copies are never
  overwritten. CI process/environment integration and mirrored critical reviews are maintained here.
- Companion layout assertions exercise preview, inventory placement and existing-file preservation
  using an owned synthetic source tree; no external monorepo is needed to run those tests.

## Verdict

Suitable for reproducible initial copying. Review and validate integrations before adopting
an imported version; importing alone does not qualify its behavior.

<!-- script-contract:begin -->
## Execution contract

Purpose: Copies the shared .NET tooling into the repository's script/library/test layout.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
