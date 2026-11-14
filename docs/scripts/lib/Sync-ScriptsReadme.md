# Sync-ScriptsReadme.psm1

Implements [Sync-ScriptsReadme.ps1](../Sync-ScriptsReadme.md). Exports only "Invoke-QuietScriptSyncScriptsReadme". Imported without name checking; import defines the command without running the operation.

# Sync-ScriptsReadme.ps1

## Purpose

Check that every PowerShell script under `scripts/` has a mirrored Markdown document, and generate
the navigable [scripts index](../README.md). This includes `Sync-ScriptsReadme.ps1` and this document.
The gate never invents missing script documentation.

## Usage

```powershell
./scripts/Sync-ScriptsReadme.ps1
./scripts/Sync-ScriptsReadme.ps1 -Apply -WhatIf
./scripts/Sync-ScriptsReadme.ps1 -Apply
```

- `-ScriptsPath`: source directory scanned recursively for `*.ps1` and `*.psm1`.
- `-DocsPath`: mirrored documentation root and destination of the generated `README.md`.
- `-Apply`: regenerate a missing or stale index once all script documents exist.
- `-WhatIf` / `-Confirm`: preview or approve the generated index write.

Default mode writes nothing. Missing script documentation throws `ScriptsDocsMissing` in every
mode. A missing or stale index throws `ScriptsReadmeNonCompliant` unless `-Apply` actually fixes it.
The report includes `Path`, `State` and `DocumentedScriptCount`.

## Dependencies and side effects

Uses PowerShell filesystem commands, path operations and asynchronous UTF-8 file I/O. No native
process, engine, download or Git mutation is involved. Approved `-Apply` only writes the generated
`docs/scripts/README.md`, with LF line endings and its mandatory credits footer.

`Commit-Workspace.ps1` calls this gate before committing. Under `-NoAll`, it checks a temporary
export of staged sources and documents; unstaged files are outside that snapshot's scope.

## Findings

- **Missing document fixed:** this file supplies the generator's previously missing mirrored doc,
  following the same rule as every other script.
- **Scope consistency fixed:** `scripts/lib/Sync-ScriptsReadme.psm1` previously excluded its own physical
  `$PSCommandPath`. Running it against another directory, such as a prepared-index snapshot,
  included the copied generator unexpectedly. Enumeration now includes every script consistently,
  so both locations require this doc and produce the same index entries.
- **Regression fixture:** `FrenchExDev2.QuietCli.Core.Tests.PoSh/CommitWorkspace.Tests.ps1:43` copies
  the real generator and this document into disposable repositories. Prepared-index properties
  therefore exercise a source tree containing the gate itself, rather than just a placeholder.
- **Coverage boundary:** the existing commit properties, malformed staged locks and targeted
  mutations cover gate wiring and snapshot consistency. Exhaustive cross-drive/edge-path and
  empty-script-directory generator qualification remains separate work.

## Verdict

The generator is documented and indexed by the same rule it enforces. Check and apply modes keep
their existing side-effect boundary; working-tree and staged-snapshot checks use one script set.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Documentation gate: checks or writes docs/scripts/README.md, the table of contents that links every script under scripts/ to its documentation file.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
