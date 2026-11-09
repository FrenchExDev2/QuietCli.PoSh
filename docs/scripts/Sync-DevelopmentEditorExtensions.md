# Sync-DevelopmentEditorExtensions.ps1

## Purpose

Keeps a developer's VS Code (Stable or Insiders) extension set reproducible across machines by
treating a repository-tracked JSON file (default `build/vscode-extensions.json`) as the single source
of truth for "which extensions this project's contributors should have installed". It solves the
"works on my machine because I happened to install extension X" problem for a development workstation.
It is invoked by a human directly (`./scripts/Sync-DevelopmentEditorExtensions.ps1 -Insiders -Export` /
`-Update`) and by `Install-DevelopmentWorkstation.ps1` / the workstation-setup path referenced from
`lib/DevelopmentWorkstation.psm1`, which pass an `-AdditionalExtension` list for workstation-specific
required extensions. `docs/README-development-editor-extensions.md` documents the human workflow.

## Usage

```
[CmdletBinding(SupportsShouldProcess,DefaultParameterSetName='Sync')]
param(
    [switch]$Insiders,
    [Parameter(Mandatory,ParameterSetName='Export')][switch]$Export,
    [Parameter(ParameterSetName='Sync')][switch]$Update,
    [string]$Path=(Join-Path (Split-Path $PSScriptRoot -Parent) 'build/vscode-extensions.json'),
    [string]$EditorPath,
    [Parameter(ParameterSetName='Sync')][string[]]$AdditionalExtension=@()
)
```

- `Insiders` (switch, optional) — selects the VS Code Insiders channel instead of Stable (default).
- `Export` (switch, mandatory in the `Export` parameter set) — captures the selected editor's current
  installed extensions into `Path` instead of installing anything.
- `Update` (switch, optional, `Sync` parameter set) — forces `--install-extension ID --force` for every
  listed extension (ensures latest), instead of only installing missing ones.
- `Path` (string, optional) — inventory JSON path. Defaults to `build/vscode-extensions.json` at the
  repository root.
- `EditorPath` (string, optional) — explicit `Code.exe` / `Code - Insiders.exe` / Linux `code`/
  `code-insiders` path, bypassing auto-detection.
- `AdditionalExtension` (string array, optional, `Sync` parameter set, default `@()`) — extra required
  extension IDs to ensure beyond the ones listed in `Path` (used by workstation setup).

Examples (from the doc comment):

```powershell
./scripts/Sync-DevelopmentEditorExtensions.ps1 -Insiders -Export
./scripts/Sync-DevelopmentEditorExtensions.ps1 -Insiders -Update -WhatIf
```

## Dependencies

- Imports `lib/EditorExtensions.psm1` (line 36), which itself dot-sources `Ci.Process.ps1` for
  `Invoke-CiProcess`.
- Shells out to the VS Code / VS Code Insiders CLI (`Code.exe`/`code`, or the discovered
  `resources/app/out/cli.js` via a Node/Electron re-exec on Windows) for `--list-extensions
  --show-versions`, `--install-extension`, `--version`.
- Filesystem assumptions: reads/writes the extension registry under
  `$HOME/.vscode(-insiders)/extensions/extensions.json` for pre-release metadata
  (`EditorExtensions.psm1` line 136) and the inventory file at `Path`.
- Environment: temporarily sets/restores `ELECTRON_RUN_AS_NODE` and `VSCODE_DEV` on Windows
  (`EditorExtensions.psm1` lines 63-76) to run the Electron app as a plain Node CLI.

## Side effects

- `-Export`: writes the inventory JSON file at `Path` (new content fully replaces old, via a temp file
  + atomic rename in `Export-EditorExtensionManifest`). Starts the editor CLI process to list
  extensions and query its version.
- Default (`Sync`, no `-Update`): starts the editor CLI to list installed extensions, then for each
  manifest/`AdditionalExtension` entry not yet installed, runs `--install-extension` (a real install,
  mutating the user's editor extension state) — gated by `ShouldProcess`/`-WhatIf`.
- `-Update`: same as above but forces `--install-extension ID --force` for every listed extension,
  regardless of whether it's already installed, with `--pre-release` when the manifest marks it so.
- `-WhatIf`: starts no editor process at all (`$cli` is a stub object when `$WhatIfPreference` is set,
  line 37) and writes no file — matches the doc comment's claim.
- Throws (propagating a `EditorExtensionSynchronizationFailed` error) if any extension install failed
  (lines 44), aggregating per-extension errors into the message.

## Findings

- No bugs found in the parameter-set / `-WhatIf` short-circuit logic (line 37) — the stub `$cli` object
  correctly prevents any editor process from starting during `-WhatIf`, matching the documented
  contract.
- DESIGN: Version pinning is effectively absent for `-Update`/default-install — `Sync-EditorExtensionManifest`
  (in `EditorExtensions.psm1`) installs with `--install-extension ID --force`, which always pulls the
  *marketplace's current* version for that ID, not the `InstalledVersion` recorded in the manifest. So
  the "repository-tracked exact versions" promise implied by the exported manifest (`InstalledVersion`
  per entry) is not actually honored on replay — syncing a teammate's machine from the manifest gives
  them whatever is latest on the marketplace that day, not the exact version that was exported. This
  may be intentional ("ensure latest" per the `.DESCRIPTION`), but it means the manifest's
  `InstalledVersion` field is write-only observability, never used to pin a specific version on sync —
  worth calling out explicitly in the script's own documentation since it is easy to assume otherwise.
- CONVENTION: `EditorExtensions.psm1` uses synchronous `Get-Content`/`[IO.File]::WriteAllTextAsync(...).GetAwaiter().GetResult()`
  inconsistently — `Read-EditorExtensionManifest` (line 108) uses plain synchronous `Get-Content -Raw`,
  while `Export-EditorExtensionManifest` (line 152) uses the async-then-block pattern. Not a bug, but
  an inconsistency against the "always prefer async, even in sync PowerShell use
  `.GetAwaiter().GetResult()`" rule — the read path should match the write path's pattern.
- Security note: `EditorPath`/`Path` are not validated against path traversal or symlink redirection
  before being passed to `Test-Path`/`Join-Path`/the CLI process start (`Resolve-DevelopmentEditorCli`,
  `EditorExtensions.psm1` lines 14-50). This is a low-severity concern since the parameters are
  developer-supplied on a trusted local machine, not attacker input, but note it is strictly weaker
  than the path-safety checks applied elsewhere in this scripts folder (e.g.
  `Test-WorkspacePackage.ps1`'s `Assert-PackageRelativePath`).
- Testability: `FrenchExDev2.QuietCli.Core.Tests.PoSh\EditorExtensions.Tests.ps1` exists and exercises
  the `lib/EditorExtensions.psm1` functions (`ConvertFrom-EditorExtensionList`,
  `Read-EditorExtensionManifest`, etc. — confirmed by grep match). This gives reasonable unit coverage
  of the manifest parsing/validation logic. However, `Sync-DevelopmentEditorExtensions.ps1` itself (the
  top-level script, its parameter sets, and its `-WhatIf` short-circuit) has no dedicated test —
  coverage stops at the library module boundary.

## Verdict

The script is fit for purpose as a developer-convenience tool and its `-WhatIf` safety is correctly
implemented; the most important thing to fix or at least document clearly is that `-Update`/default
sync does not actually pin to the `InstalledVersion` recorded in the manifest — it always installs
"force latest" from the marketplace, so the manifest is not a true version-reproducibility mechanism
today.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
