# Sync-ScriptsReadme.psm1

<!-- script-source:begin -->
Source file: [`lib/Sync-ScriptsReadme.psm1`](../../../scripts/lib/Sync-ScriptsReadme.psm1)
<!-- script-source:end -->

Implements [Sync-ScriptsReadme.ps1](../Sync-ScriptsReadme.md). Exports only "Invoke-QuietScriptSyncScriptsReadme". Imported without name checking; import defines the command without running the operation.

# Sync-ScriptsReadme.ps1

## Purpose

Check that every PowerShell script and run profile under `scripts/` has a mirrored Markdown document with a link to its source. Generate the navigable index. [Scripts documentation index](../README.md)

Source links split the relative file path using the host directory separator, escape each segment, and join the segments with `/` for Markdown.

## Usage

```powershell
./scripts/Sync-ScriptsReadme.ps1
./scripts/Sync-ScriptsReadme.ps1 -Apply -WhatIf
./scripts/Sync-ScriptsReadme.ps1 -Apply
```

- `-ScriptsPath` selects the source directory scanned recursively for `*.ps1`, `*.psm1` and `*.profile.psd1`.
- `-DocsPath` selects the mirrored documentation root and generated `README.md` destination.
- `-Apply` synchronizes stale source links, converts mirrored documentation to LF and regenerates the index once all script documents exist.
- `-WhatIf` and `-Confirm` preview or approve each write.

Default mode reports `ScriptsDocsMissing` for missing docs, `ScriptsDocSourceLinksStale` for missing or stale links, `ScriptsDocLineEndingsStale` for mirrored documents containing CR and `ScriptsReadmeNonCompliant` for a stale index, including one with CRLF. Malformed marker pairs report `ScriptsDocSourceBlockInvalid`. The result includes `Path`, `State`, `DocumentedScriptCount`, `SourceLinksToSync` and `LineEndingsToSync`. The last two fields count affected mirrored documents.

## Dependencies and side effects

Uses PowerShell filesystem commands, path operations and asynchronous UTF-8 file I/O. No native
process, engine, download or Git mutation is involved. Approved `-Apply` writes the index and the managed source link in each affected document with LF line endings. The index uses the shared credits formatter. [Sync-DocsCredits.psm1](Sync-DocsCredits.md)

`Commit-Workspace.ps1` calls this gate before committing. Under `-NoAll`, it checks a temporary
export of staged sources and documents; unstaged files are outside that snapshot's scope.

## Findings

- `scripts/lib/Sync-ScriptsReadme.psm1:72` derives the link from each document's own directory, including nested libraries and run profiles. It refreshes exactly one managed block per doc and rejects ambiguous markers before writing.
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

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Documentation gate: checks or writes docs/scripts/README.md, the table of contents that links every script under scripts/ to its documentation file.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
