# Fix-WindowsDefender.psm1

<!-- script-source:begin -->
Source file: [`lib/Fix-WindowsDefender.psm1`](../../../scripts/lib/Fix-WindowsDefender.psm1)
<!-- script-source:end -->

Exports `Invoke-QuietScriptFixWindowsDefender` for
[Fix-WindowsDefender.ps1](../Fix-WindowsDefender.md). Importing the module
defines the command without contacting Defender.

```powershell
Import-Module ./scripts/lib/Fix-WindowsDefender.psm1 -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptFixWindowsDefender -WhatIf
```

## Review and verdict

The [path selection](../../../scripts/lib/Fix-WindowsDefender.psm1#L13-L31) checks the
fixed repository, .NET, package-cache and VS Code Insiders paths literally and
only submits the ones it finds. It skips profile-relative candidates when their
environment variable is empty. The [add operation](../../../scripts/lib/Fix-WindowsDefender.psm1#L33-L40)
submits these paths, the fixed development process names and the `vhdx` extension together
through `Add-MpPreference`. It adds to the existing preferences. Exclusions reduce
scanning coverage. A failed readback can follow a successful write.

[Unit tests](../../../test/scripts/unit/lib/Fix-WindowsDefender.Tests.ps1) verify the
defaults, path selection, returned lists, write failure and preview using PowerShell doubles.

<!-- script-contract:begin -->
## Execution contract

Purpose: Adds the development path, process and extension exclusions and returns the active lists.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
