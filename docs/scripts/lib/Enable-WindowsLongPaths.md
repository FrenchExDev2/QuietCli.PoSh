# Enable-WindowsLongPaths.psm1

<!-- script-source:begin -->
Source file: [`lib/Enable-WindowsLongPaths.psm1`](../../../scripts/lib/Enable-WindowsLongPaths.psm1)
<!-- script-source:end -->

Exports `Invoke-QuietScriptEnableWindowsLongPaths` for
[Enable-WindowsLongPaths.ps1](../Enable-WindowsLongPaths.md). Importing the module
defines the command without accessing the registry.

```powershell
Import-Module ./scripts/lib/Enable-WindowsLongPaths.psm1 -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptEnableWindowsLongPaths -WhatIf
```

## Review and verdict

The [guarded operation](../../../scripts/lib/Enable-WindowsLongPaths.psm1#L11-L16) uses
the Windows Registry provider. It writes a DWORD at
`HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled`, then reads it back
after a successful write. An error terminates execution. A readback error can leave
the setting applied.

[Unit tests](../../../test/scripts/unit/lib/Enable-WindowsLongPaths.Tests.ps1) verify the
key, value and type, readback, write failure and preview using PowerShell doubles.

<!-- script-contract:begin -->
## Execution contract

Purpose: Writes the machine-wide LongPathsEnabled DWORD and reads it back.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
