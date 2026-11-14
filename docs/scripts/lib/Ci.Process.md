# Ci.Process.psm1

## Library boundary

Located at `scripts/lib/Ci.Process.psm1`. Load with `Import-Module ([IO.Path]::Combine($root,'scripts/lib/Ci.Process.psm1')) -DisableNameChecking -ErrorAction Stop`. Import defines functions and explicit dependencies without running business operations. Paths use `System.IO.Path`. Effects remain owned by the calling operation and its preview contract.

Explicit export surface:

```powershell
Export-ModuleMember -Function 'ConvertTo-CiArgument','Start-CiProcess','Invoke-CiProcess'
```


## Purpose and usage

Engine-independent native process boundary for CI/build orchestration. It uses System.Diagnostics.Process and PowerShell/.NET helpers, without importing QuietCli, finding a quiet alias or relying on a product build. Interactive agent CLI analysis still uses quiet; this helper belongs to repository infrastructure.

| Function | Contract |
| --- | --- |
| ConvertTo-CiArgument | Quote one value for the PowerShell process-launch command line. |
| Invoke-CiProcess | Resolve an Application, pass the exact argument array, stream bounded UTF-8 records, enforce a deadline and return execution metadata. |
| Start-CiProcess | Start an asynchronous child with inherited streams and return its Process; caller owns observation, deadline, cleanup and disposal. |

Invoke-CiProcess accepts FilePath, ArgumentList, WorkingDirectory, TimeoutSeconds (default 600; 1–7200), OnOutput, caller State, optional InputText and MaxRecordChars (default 131072). The callback receives transient records and explicit caller state. No automatic output history/spool is created.

## Encoding and effects

Redirected stdin is UTF-8 without BOM, preserving exact credential/fixture bytes. Both output streams are decoded as UTF-8. A non-UTF-8 child must initialize/declare its own boundary; the helper does not silently reinterpret business output. Tests independently assert synthetic stdin bytes and explicitly initialize Unicode stdout/stderr fixtures.

Invoke-CiProcess starts/owns a child, streams records, reports failure/timeout and kills its still-running owned process tree on exit. A caller may explicitly retain required bounded diagnostics. Start-CiProcess captures no streams and leaves ownership with its scheduler; WhatIf starts no process. Inherited output is not a file capture.

## Critical review and verdict

`scripts/Ci.Process.psm1:1` is the shared infrastructure leaf. Exact vectors avoid shell evaluation; application resolution avoids accidental aliases/functions. Process, quoting and encoding tests exercise real children and hostile/Unicode arguments. Shared helpers remain synchronous PowerShell orchestration over asynchronous .NET I/O. Higher layers own report files, suite completeness, image identity and publication permissions; process exit success cannot replace those checks.



<!-- script-contract:begin -->
## Execution contract

Purpose: Initializes UTF-8 only when the normal profile is absent or explicitly disabled, immediately before process I/O.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

## Explicit library dependencies

UTF-8 fallback initialization is private and runs only immediately before process I/O when profiles are absent or disabled. Importing this library preserves the current terminal encoding.
