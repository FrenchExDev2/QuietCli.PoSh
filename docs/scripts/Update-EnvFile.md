# Update-EnvFile.ps1

<!-- script-source:begin -->
Source file: [`Update-EnvFile.ps1`](../../scripts/Update-EnvFile.ps1)
<!-- script-source:end -->

Reads or edits one key through [EnvFile.ps1](lib/EnvFile.md). `-Path` defaults to the checkout's `.env`;
`-Key` is mandatory and case-sensitive. Supplying `-Value` selects write mode; otherwise `-Read`
reads only the selected value. Read mode is explicit value output, so choose which key to display.
Write results contain metadata without values.

```powershell
./scripts/Update-EnvFile.ps1 -Key QUIET_CONTAINER_RUNTIME -Value podman -WhatIf
./scripts/Update-EnvFile.ps1 -Key QUIET_CONTAINER_RUNTIME -Value podman
./scripts/Update-EnvFile.ps1 -Key QUIET_CONTAINER_RUNTIME -Read
```

`-WhatIf` and `-Confirm` guard writes. Unrelated keys remain intact; the editor does not load them
into process environment variables. Duplicate assignments for the edited key are consolidated.
The shared library owns syntax, size, encoding and atomic-replacement behavior.

<!-- script-contract:begin -->
## Execution contract

Purpose: Reads one dotenv key or atomically updates its quoted literal value.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
