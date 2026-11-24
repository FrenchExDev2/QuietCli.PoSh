# Enable-WindowsLongPaths.ps1

<!-- script-source:begin -->
Source file: [`Enable-WindowsLongPaths.ps1`](../../scripts/Enable-WindowsLongPaths.ps1)
<!-- script-source:end -->

Enables long paths for compatible Windows applications by setting the machine-wide
`LongPathsEnabled` registry value to the DWORD `1`.

```powershell
./scripts/Enable-WindowsLongPaths.ps1 -WhatIf
./scripts/Enable-WindowsLongPaths.ps1 -Confirm
```

Use PowerShell 7.6 or later on Windows. Applying the change requires an elevated session
with access to the Registry provider. `-WhatIf` previews the operation without accessing
the registry. A successful run emits the updated registry property and then its value.

## Review and verdict

The entry point delegates to [Enable-WindowsLongPaths.psm1](lib/Enable-WindowsLongPaths.md).
The setting is machine-wide. Applications must opt in to Windows long-path support,
and running applications may need to restart for the new value to take effect.
The [entry-point tests](../../test/scripts/integration/entrypoints/WindowsSettings.Tests.ps1)
exercise the preview in a child PowerShell process with blocked registry access.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Enables long paths for Windows applications that opt in to long-path support.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
