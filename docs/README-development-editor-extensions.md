# Development editor extensions

[Workstation setup](../README-development-workstation.md) · [Documentation index](README.md)

The repository snapshot [build/vscode-extensions.json](../build/vscode-extensions.json) contains the
37 user extensions exported from VS Code Insiders, including observed versions and six prerelease
preferences. It contains identifiers and release preferences, not settings, credentials, machine paths
or extension binaries. Refreshing the snapshot can change these counts.

## Export the installed inventory

Run from the QuietCli repository in PowerShell 7.6+:

```powershell
# Preview only: no editor process starts and no file is written.
./scripts/Sync-DevelopmentEditorExtensions.ps1 -Insiders -Export -WhatIf

# Refresh the repository snapshot from Insiders.
./scripts/Sync-DevelopmentEditorExtensions.ps1 -Insiders -Export

# Export from Stable, or save to a different file.
./scripts/Sync-DevelopmentEditorExtensions.ps1 -Export -Path ./build/stable-extensions.json
```

Export executes `code-insiders --list-extensions --show-versions` (or `code` for Stable), then
copies the result into a sorted UTF-8/LF JSON snapshot. Versions are observations, not installation
pins. The selected channel's local extension metadata supplies prerelease preferences when present.
The CLI's default profile is used; this is not an export of remote SSH/WSL/container extension hosts,
other profiles, disabled/enabled states or VS Code's bundled extensions. Empty or malformed inventories
are rejected before replacing the previous snapshot.

## Install or update the saved inventory

```powershell
# Stable: install only missing listed extensions.
./scripts/Sync-DevelopmentEditorExtensions.ps1

# Insiders: preview installation/update of every listed extension.
./scripts/Sync-DevelopmentEditorExtensions.ps1 -Insiders -Update -WhatIf

# Insiders: ensure the latest version of each listed extension.
./scripts/Sync-DevelopmentEditorExtensions.ps1 -Insiders -Update
```

`-Update` runs `--install-extension publisher.name --force` for every saved identifier. Entries that
prefer prereleases also receive `--pre-release`. This updates only the saved set and any explicit
`-AdditionalExtension` IDs; it does not run the broader `--update-extensions` command or uninstall
unlisted extensions. The installed CLI documents these options through `code-insiders --help`.

The returned report contains one result per extension. Failures are collected, reported with their
identifiers and then cause the script to throw. Private/local VSIX extensions, withdrawn Marketplace
entries, license requirements and platform-specific incompatibilities remain explicit failures:
install the corresponding trusted VSIX separately or select an adapted inventory with `-Path`.
No VSIX package or license is copied by export. Installation and update require Marketplace access.

`-EditorPath` selects an explicit native editor executable. On Windows the script uses `Code.exe` or
`Code - Insiders.exe` with its CLI JavaScript entrypoint and temporary Electron variables, restoring
those variables afterward. Both classic and version-directory layouts are supported. No CMD wrapper
is executed and no editor window is requested. On Linux, use the native `code` or `code-insiders` CLI
as the normal desktop user. Alpine uses the external editor described by the workstation guide.

## Workstation integration

```powershell
./scripts/Install-DevelopmentWorkstation.ps1 -Insiders
# Use a different saved inventory if needed:
./scripts/Install-DevelopmentWorkstation.ps1 -ExtensionManifest ./build/stable-extensions.json
```

After installing/resolving the selected editor, workstation setup invokes the same extension script
with `-Update`. It combines the snapshot with its minimum PowerShell/C#/remote-development set.
`-SkipEditor` excludes this phase. The workstation's `-WhatIf` and `-CheckOnly` do not synchronize
extensions or rewrite the snapshot. Stable is the default; `-Insiders` selects Insiders for all actions.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
