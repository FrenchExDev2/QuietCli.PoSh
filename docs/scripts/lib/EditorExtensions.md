# EditorExtensions.psm1 (lib)

## Purpose

Exports/synchronizes a repository-tracked inventory of VS Code (Stable or Insiders) extensions through the real editor CLI, so the exact set of extensions a contributor's editor has installed can be captured into a reviewable JSON manifest and later re-applied on another machine. It solves "which extensions does this project expect, and how do we keep a new workstation's editor in sync with that list" without baking secrets, local paths, or private settings into the manifest. It is consumed by `Sync-DevelopmentEditorExtensions.ps1` (the end-user-facing script) and by `DevelopmentWorkstation.psm1`'s `Install-DevelopmentExtensions` (line 486–497 of that module), which calls `Sync-DevelopmentEditorExtensions.ps1` rather than this module's functions directly.

## Usage

Exported functions (`Export-ModuleMember`, line 205): `Resolve-DevelopmentEditorCli`, `ConvertFrom-EditorExtensionList`, `Read-EditorExtensionManifest`, `Export-EditorExtensionManifest`, `Sync-EditorExtensionManifest`.

Key signatures:
- `Resolve-DevelopmentEditorCli [-Insiders] [-EditorPath <string>]` — locates the Stable/Insiders native executable and, on Windows, the versioned `cli.js` entry point (parsed out of the `.cmd` wrapper if not found at the default relative path); throws `EditorExecutableNotFound`/`EditorNativeExecutableRequired`/`EditorCliLayoutAmbiguous` on failure.
- `ConvertFrom-EditorExtensionList [-Lines <string[]>]` — validates `id@version` records (regex-anchored), rejects duplicates and malformed lines, caps at 4096 lines.
- `Read-EditorExtensionManifest -Path <string>` — reads and validates a saved JSON manifest (schema version 1, 4 MiB cap).
- `Export-EditorExtensionManifest -Cli <obj> -Path <string> -ShouldApply <scriptblock>` — queries the real editor and writes the manifest; throws `EditorExtensionExportEmpty` rather than overwrite a good manifest with an empty one.
- `Sync-EditorExtensionManifest -Cli <obj> -Entries <object[]> [-AdditionalExtension <string[]>] [-Update] [-ShouldApply <scriptblock>] [-Preview]` — installs/updates extensions one at a time, each gated by `$ShouldApply`.

Example:
```powershell
Import-Module ./scripts/lib/EditorExtensions.psm1
$cli = Resolve-DevelopmentEditorCli
Export-EditorExtensionManifest -Cli $cli -Path ./extensions.json -ShouldApply { $true }
```

## Dependencies

- Dot-sources `../Ci.Process.ps1` (line 3) for `Invoke-CiProcess`.
- Shells out to the real `code`/`code-insiders`/`Code.exe`/`Code - Insiders.exe` binary (and its `cli.js` on Windows) for `--list-extensions --show-versions`, `--version`, `--install-extension` (`Invoke-DevelopmentEditorCli`, lines 53–77).
- Reads `$HOME/.vscode(-insiders)/extensions/extensions.json` (the editor's own internal registry) to recover each extension's pre-release preference (lines 136–146).
- Filesystem: reads/writes the caller-supplied manifest JSON path.

## Side effects

- `Export-EditorExtensionManifest` writes (via an atomic temp-file-then-move pattern, lines 150–152) a UTF-8-without-BOM JSON manifest to the given path, replacing any existing content there.
- `Sync-EditorExtensionManifest` can install or force-update real VS Code extensions on the host — a genuine mutation of the user's editor installation, each individually gated by `$ShouldApply`.
- Starts the editor's CLI as a subprocess for every query/install call (bounded by `-TimeoutSeconds 300` in `Invoke-DevelopmentEditorCli`, line 67).
- Temporarily mutates `$env:ELECTRON_RUN_AS_NODE`/`$env:VSCODE_DEV` on Windows around each CLI call, restoring them in a `finally` block (lines 63, 66, 76).

## Findings

- No bug found after reviewing the regex-based `id@version` parsing (line 91), the Windows `.cmd`-wrapper regex fallback for locating `cli.js` (lines 39–41, which also validates the resolved path stays under the editor's own base directory before trusting it — a good defense against path traversal via a tampered wrapper script), and the atomic-write pattern in `Export-EditorExtensionManifest` — all are careful and defensively written.
- DESIGN: `Sync-EditorExtensionManifest`'s per-extension install loop (lines 183–200) calls `$ShouldApply` once per extension with a composite key `$Cli.Channel+'/'+$entry.Id` (line 187) — reasonable for fine-grained confirmation, but for a workstation with dozens of extensions this means dozens of individual confirmation prompts if the caller's `$ShouldApply` is wired to an interactive `ShouldProcess`; no batch/"confirm once for all" option exists. Not a bug, but a usability smell for the common "sync everything" case.
- CONVENTION: Line 38, `[IO.File]::ReadAllTextAsync($wrapper,[Text.Encoding]::UTF8).GetAwaiter().GetResult()` — correctly follows the async-then-block convention. The rest of the module's file I/O (`Get-Content -Raw -Encoding utf8` at lines 108, 138) uses the synchronous cmdlet instead, which is a minor inconsistency against the "always prefer async" rule, though `Get-Content` has no async PowerShell-native equivalent, so this is a soft violation at best.
- Testability: `EditorExtensions.Tests.ps1` exists under `FrenchExDev2.QuietCli.Core.Tests.PoSh/`, so dedicated test coverage exists for this module.
- Security: extension IDs/versions are strictly regex-validated before being used in any command argument (lines 91, 177), and the Windows CLI-path resolution validates the candidate path is contained within the editor's own directory (line 40) before trusting it — no injection surface found.

## Verdict

A well-defended, single-responsibility module with existing test coverage and no bugs found on close reading; the only real improvement opportunity is usability (batching per-extension confirmations) rather than correctness, so no urgent fix is required.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Resolves Stable/Insiders, including versioned Windows layouts, without executing a CMD wrapper.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

Read-only property projections use script blocks so metadata remains available during WhatIf; mutating operations retain their existing operation guards.
