# Fix-WindowsDefender.ps1

<!-- script-source:begin -->
Source file: [`Fix-WindowsDefender.ps1`](../../scripts/Fix-WindowsDefender.ps1)
<!-- script-source:end -->

Adds Microsoft Defender Antivirus exclusions for the workspace's Windows development
tools. It adds existing paths from the development defaults, the configured process
names and the `vhdx` extension.

```powershell
./scripts/Fix-WindowsDefender.ps1 -WhatIf
./scripts/Fix-WindowsDefender.ps1 -Confirm
```

Use PowerShell 7.6 or later on Windows, with Microsoft Defender Antivirus and its
PowerShell commands available. Apply the change from an elevated session. `-WhatIf`
previews the operation without checking paths or contacting Defender. After applying,
the script reports the active path, process and extension exclusion lists.

## Review and verdict

The entry point delegates to [Fix-WindowsDefender.psm1](lib/Fix-WindowsDefender.md), which
documents the fixed defaults and the effect on scanning. Local or managed Defender
policy can prevent the change. The
[entry-point tests](../../test/scripts/integration/entrypoints/WindowsSettings.Tests.ps1)
exercise the preview in a child PowerShell process with blocked Defender access.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Adds the workspace's development exclusions to Microsoft Defender Antivirus.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
