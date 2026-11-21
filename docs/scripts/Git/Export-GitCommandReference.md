# Export-GitCommandReference.ps1

Source: [Git companion entry point](../../../src/Git/scripts/Export-GitCommandReference.ps1).

From the repository root:

```powershell
./src/Git/scripts/Export-GitCommandReference.ps1 -WhatIf
./src/Git/scripts/Export-GitCommandReference.ps1
./src/Git/scripts/Export-GitCommandReference.ps1 -Check
```

The entry point reads the Git source and [form guidance](../../../src/Git/scripts/GitCommandReference.json) through the [renderer](lib/GitCommandReference.md). It writes the [tracked reference](../../README-git-command-reference.md) in UTF-8 without BOM and with LF line endings. It returns without writing when the bytes already match. A changed document is replaced via a temporary file in the destination directory.

`-OutputPath` accepts another Markdown path in an existing directory. Its content and links use the tracked document's location as their base. `-Check` reads and fails with `GitCommandReferenceStale` when that destination is absent or outdated. The generator requires PowerShell 7.6+ and the source files. It imports no product module and starts no Git process.

When a handler or its input changes, review its forms, fields and limitations before regenerating. The Git companion checks the tracked page and exercises preview, generation and invalid inputs. Those checks cover documentation drift and generator behavior.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
