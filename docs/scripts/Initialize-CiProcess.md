# Initialize-CiProcess.ps1

## Purpose and usage

```powershell
. ./scripts/Initialize-CiProcess.ps1
```

Loads the engine-independent [CI process library](lib/Ci.Process.md) into the caller's scope.
This replaces the former Bootstrap.ps1 entry point to follow Verb-Noun naming. Consumers can
import the library directly with -DisableNameChecking -ErrorAction Stop.

## Dependencies and effects

Supports standard WhatIf/Confirm before importing. It starts no process and loads no product
engine or AI aliases. The library exports ConvertTo-CiArgument, Start-CiProcess and Invoke-CiProcess.
UTF-8 fallback initialization belongs to process execution when the normal profile is absent;
importing the library alone does not change terminal encoding.

## Validation limits

Source/layout and preview gates validate this boundary. Runtime tests of process argument
handling remain in the companion; importing commands does not qualify tools they run.

<!-- script-contract:begin -->
## Execution contract

Purpose: Imports the engine-independent CI process commands without starting a process.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
