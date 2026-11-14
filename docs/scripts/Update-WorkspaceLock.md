# Update-WorkspaceLock.ps1

## Purpose

Refresh repositories.lock.json with source identities, project dependencies and the actual
SDK/runtime source pins, without committing or pushing.

## Usage and parameters

```powershell
./scripts/Update-WorkspaceLock.ps1 -WhatIf
./scripts/Update-WorkspaceLock.ps1 -Confirm
```

WorkspaceRoot defaults to this checkout. WhatIf returns before computing/writing the
prospective lock. The SDK label follows global.json; the runtime label follows the engine
project's unique net11.0 RuntimeFrameworkVersion property.

## Dependencies and effects

Uses Common.ps1, SourceIdentity.ps1 and WorkspaceProjects.ps1. Approved execution reads
source/dependency metadata and atomically rewrites the repository lock. Git metadata
queries are read-only. Portable SDK directories and generated pin/lock backups are
excluded from source/build identities, with tracked/untracked source selection preserved.

## Findings

- scripts/Update-WorkspaceLock.ps1:8 guards the whole operation. SDK/runtime labels are
  read from their source pins rather than duplicated RC string constants.
- The unique runtime-property check fails closed if the engine declaration becomes
  ambiguous. It does not validate a future SDK/runtime combination or build products.
- Source identities describe content, not qualification. Binaries require their own
  source-bound manifests and execution evidence.
- DotNetLocks.Tests.ps1 generates varied SDK/runtime source pairs and independently asserts
  matching lock labels. The same suite checks that portable SDK payloads/backups do not
  enter source identities.

## Verdict

Required metadata refresh before a checkpoint commit. It neither builds nor qualifies
the selected SDK/runtime and performs no publication.

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Updates project hashes without committing, pushing or trying to pin a repository to its own future commit.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
