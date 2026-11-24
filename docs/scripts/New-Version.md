# New-Version.ps1

<!-- script-source:begin -->
Source file: [`New-Version.ps1`](../../scripts/New-Version.ps1)
<!-- script-source:end -->

## Purpose

Update the version of one or more QuietCli business modules in their source manifests.
The numeric version is stored in `ModuleVersion` and the prerelease label in
`PrivateData.PSData.Prerelease`, both in the module's `.psd1`.

## Usage

From the repository root, these three commands produce `0.2.0-preview3`, then
`0.2.0-preview4`, then stable `0.2.1`.

```powershell
./scripts/New-Version.ps1 -Version 0.2.0-preview3
./scripts/New-Version.ps1 -Bump preview
./scripts/New-Version.ps1 -Bump patch
```

Use `-Module` with aliases such as `Core,Git` or full module names. The default is
`All`, which selects every discovered business module, including Vagrant.
`-WorkspaceRoot` defaults to the checkout containing the script.

- `-Version` sets the same exact version on all selected modules. Accepts three
  numeric components and an optional Gallery prerelease label.
- `-Bump major|minor|patch` increments the selected component of each current version,
  resets lower components to zero and clears any prerelease label.
- `-Bump preview` keeps each module's numeric version and increments its local
  `preview<N>` counter. Stable versions and bare `preview` start at `preview1`.
  For other labels such as `rc1`, use `-Version` to specify the transition.
- `-WhatIf` validates and displays the plan without writing. `-Confirm` prompts once
  for the batch. Results list the previous and requested versions and whether the
  manifest was updated.

```powershell
./scripts/New-Version.ps1 -Bump preview -Module Core,Git -WhatIf
```

## Dependencies and effects

The [ModuleVersion library](lib/ModuleVersion.md) discovers source manifests and
delegates their textual edits to the same editor the release scripts use.
The operation writes only selected business module manifests. It preserves dependency
minimums, GUIDs and other metadata. Git and PowerShell Gallery are outside this operation.

## Findings

- The [manifest planning and approval](../../scripts/lib/ModuleVersion.psm1#L119)
  run before filesystem writes. Invalid versions and selectors stop the batch.
- The [preview calculation](../../scripts/lib/ModuleVersion.psm1#L20) uses the current
  source label. It does not reserve a release identity or check existing tags.
- The [file replacement logic](../../scripts/lib/ModuleVersion.psm1#L42) stages all
  updates before replacing individual manifests and attempts rollback if a later
  replacement fails. An interrupted process can leave a partial batch and backups.

## Verdict

Use this command to edit local versions. When preparing a published release, use the
[release workflow](Invoke-QuietRelease.md) to validate identities and delivery.

<!-- script-contract:begin -->
## Execution contract

Purpose: Sets or bumps the versions of QuietCli business module manifests.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
