# Companion handler selection and diagnostics

A companion registers handlers on import. [Write a handler](README-create-git-handler.md) to see a complete registration, or use this reference to investigate a call against an installed companion.

## Inspect what is registered

Import the companion before checking the registry. For Git, inspect the session with:

```powershell
Get-Module FrenchExDev2.QuietCli.Core.PoSh, FrenchExDev2.QuietCli.Git.PoSh |
    Select-Object Name, Version, Path
Get-QuietHandler -Binary git |
    Select-Object Id, VersionRange, SupportedForms, Qualification
```

`Get-QuietHandler` reads metadata without launching the executable. `VersionRange` and `SupportedForms` describe the registration. The executable path, observed version and exact argument vector determine the match. Qualification records the tested scope separately from the inventory.

## How QuietCli selects a handler

1. Resolve the executable path. Candidate registrations use its filename; Windows drops the `.exe` extension. `-HandlerId` restricts candidates to one ID and retains the executable, version and form checks.
2. Reuse a cached probe value or run the candidate's `Probe`. It returns one version value. The cache key includes the handler ID, resolved path, file size, last-write time and explicit child environment overrides. Registrations with different IDs have different cache entries. Use a fresh session when testing a changed probe with the same ID and executable.
3. Evaluate `TestVersion` and then `Match` for each candidate. Each callback returns exactly one Boolean. A candidate without `Match` accepts every argument form once its version check passes. When a binary has separate handlers, make their accepted forms disjoint.
4. Call the single match's `Execute` with the runtime. Return the business value from this callback. A handler can run native work through a nested call with explicit analysis callbacks and preserve relevant request options there.

An explicit analysis callback (`-Output`, `-StdOut`, `-StdErr` or `-Complete`) selects direct execution, even with a companion loaded or `-HandlerId` present. A valid `-SaveRecall -AsObject` request may run directly if no handler matches, so capture can proceed without a parser. See [the Recall contract](README-recall.md#capture-once-resume-later).

## Diagnose a rejected call

Read `Outcome`, `Error`, `Execution` and both `Completeness` flags before using `Data`. Use a read-only command when checking selection and provide native arguments via `-FilePath` and `-ArgumentList` if their boundaries are in doubt.

| Observation | What to check |
| --- | --- |
| `Unsupported` with `HandlerNotFound` in phase `Resolve` | Check the loaded module and registered IDs, then the executable, version and exact command form. A rejected call can have executed a version probe. QuietCli did not invoke the requested business operation. |
| `InvocationFailed` with `AmbiguousHandler` in the message | Several registrations accepted the call. Choose the intended ID with `-HandlerId` to diagnose it. Tighten the overlapping matches if you maintain the registrations. |
| `InvocationFailed` with a probe or predicate error | Check `Error[].Message` and `Execution.Issues` for the child outcome. Check that the probe returns one value, and that each predicate emits one Boolean without extra pipeline values. |
| `HandlerAlreadyRegistered` when registering | Import once and use stable, distinct IDs. Remove the owning module or use `Unregister-QuietHandler` for a registration you created directly in the session. |
| Call succeeds with your custom callbacks and produces a different result | Direct execution used the callback projection. Omit analysis callbacks to use the registered handler for a supported form. |

See the [registry implementation](../src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/engine/Cmdlets/HandlerCommands.cs), [probe identity](../src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/engine/ProbeIdentity.cs) and [invocation routing](../src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/engine/Cmdlets/InvocationCommands.cs) for the exact checks. The [troubleshooting guide](agents/troubleshooting.md) covers execution, analysis and loading failures.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
