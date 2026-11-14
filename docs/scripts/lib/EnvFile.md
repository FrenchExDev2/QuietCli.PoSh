# EnvFile.psm1

## Library boundary

Located at `scripts/lib/EnvFile.psm1`. Load with `Import-Module ([IO.Path]::Combine($root,'scripts/lib/EnvFile.psm1')) -DisableNameChecking -ErrorAction Stop`. Import defines functions and explicit dependencies without running business operations. Paths use `System.IO.Path`. Effects remain owned by the calling operation and its preview contract.

Explicit export surface:

```powershell
Export-ModuleMember -Function 'Read-QuietEnvText','ConvertFrom-QuietEnvLiteral','Get-QuietEnvValue','Set-QuietEnvValue'
```


Function-only library for bounded dotenv access. It does not source a shell file, expand variables,
evaluate commands, change process environment variables or enumerate unrelated values.

- `Get-QuietEnvValue -Path $path -Key KEY` returns null when the file/key is absent, and an empty
  string for an explicitly empty assignment. Keys are case-sensitive; duplicates fail.
- `Set-QuietEnvValue -Path $path -Key KEY -Value $value [-WhatIf] [-Confirm]` creates or atomically
  replaces one assignment as `KEY="value"`. It preserves unrelated lines/comments and consolidates
  duplicate assignments for that key. Output contains path/key/change metadata, never the value.

The reader accepts unquoted, single-quoted and double-quoted single-line values, optional `export`,
and trailing comments. Double quotes recognize escaped backslash and quote only; other backslashes
remain literal. `$variables` and `$(commands)` remain data. A one-MiB strict UTF-8 limit bounds input
and output; writes use UTF-8 without a BOM and LF. Multiline/NUL writes, invalid identifiers, malformed
quotes and oversized data fail. Writes reject a linked target, clean their temporary file, and use
atomic replacement. Existing unrelated values are not printed. `-WhatIf` creates no file/directory.

Use [Update-EnvFile.psm1](../Update-EnvFile.md) for command-line access and
[Initialize-CiEnvironment.ps1](../Initialize-CiEnvironment.md) for deterministic Local/GitHub presets.
The companion's dotenv campaign covers Unicode round trips, idempotence, comments, malformed
assignments, previews and both presets. Availability/precedence properties live in AutomationContracts.

<!-- script-contract:begin -->
## Execution contract

Purpose: Reads at most one MiB of strict UTF-8 dotenv text without evaluating its contents.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
