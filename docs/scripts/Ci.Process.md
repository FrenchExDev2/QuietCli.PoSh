# Ci.Process.ps1

`Invoke-CiProcess -InputText` uses UTF-8 **without a BOM** for redirected stdin. The caller's exact
credential/fixture bytes are preserved; no `EF BB BF` prefix is added. Output readers decode UTF-8,
so a child that emits another encoding must declare or initialize its own output encoding. The
helper does not silently rewrite a child's business output. Core tests include a raw stdin hex
regression with independently expected `C3A9` for the synthetic input `é`.
The stdout/stderr fixture explicitly initializes its child's console to UTF-8 without a BOM before
writing Unicode directly to those streams. Its expected bytes therefore do not depend on a developer
profile or the GitHub runner's default console code page.

## Purpose

The engine-independent, QuietCli-module-independent native process runner that every "CI tool" call in this folder is ultimately built on top of. It is the file `AGENTS.md`'s own carve-out ("CI/build orchestration retains the monorepo's engine-independent `scripts/Ci.Process.ps1` helper") refers to, which exempts `dotnet`/`git`/`podman`/etc. CI-orchestration calls from going through the `quiet` facade. It is dot-sourced transitively by at least 28 other scripts in this folder via `Common.ps1` (confirmed by search), and directly by `Bootstrap.ps1` (its entire content). Its `ConvertTo-CiArgument` quoting helper is directly unit-tested in `FrenchExDev2.QuietCli.Core.Tests.PoSh/Script.Tests.ps1` (lines 29-36), which round-trips 11 hostile argument values through a real child `pwsh` process.

## Usage

A function-definition file; always dot-sourced, never run with its own parameters.

| Function | Parameter | Type | Mandatory | Default |
|---|---|---|---|---|
| `ConvertTo-CiArgument` | `Value` | `string` (`AllowEmptyString`) | Yes | none |
| `Invoke-CiProcess` | `FilePath` | `string` | Yes | none |
| `Invoke-CiProcess` | `ArgumentList` | `string[]` | No | `@()` |
| `Invoke-CiProcess` | `WorkingDirectory` | `string` | No | `(Get-Location).Path` |
| `Invoke-CiProcess` | `TimeoutSeconds` | `int` (`ValidateRange(1,7200)`) | No | `600` |
| `Invoke-CiProcess` | `OnOutput` | `scriptblock` | No | none |
| `Invoke-CiProcess` | `State` | untyped | No | none |
| `Invoke-CiProcess` | `InputText` | `string` (`AllowEmptyString`) | No | none |
| `Invoke-CiProcess` | `MaxRecordChars` | `int` (`ValidateRange(1024,1048576)`) | No | `131072` |

```powershell
. ./scripts/Ci.Process.ps1
$result = Invoke-CiProcess -FilePath git -ArgumentList @('status','--','a file') -WorkingDirectory $repo -TimeoutSeconds 60
```

## Dependencies

- No dot-sourcing of other scripts — this is the leaf of the dependency chain.
- Uses only `System.Diagnostics.Process` and PowerShell built-ins. It runs whatever `-FilePath` the caller supplies, resolved strictly as an `Application` via `Get-Command ... -CommandType Application` (line 65), so it cannot accidentally invoke a PowerShell alias or function instead of the real executable.
- Assumes the UTF-8 console-encoding preamble (lines 2-7) runs once per process when no PowerShell profile is active.

## Side effects

- Starts and owns a child process; kills its full tree both on timeout (line 93) and in the `finally` block if still running (line 117).
- Optionally writes to the child's stdin (lines 83-87).
- Streams stdout/stderr either to the console (lines 76-77) or to the caller's `-OnOutput` callback (line 75). Never writes to a file itself — that layer is added by `Common.ps1`'s `Invoke-WorkspaceNative`.

## Findings

- Good, security-relevant: explicit executable resolution via `Get-Command ... -CommandType Application` (line 65) closes the command-injection/alias-hijack risk a bare `Start-Process $FilePath` would carry.
- Good: the async read loop (lines 91-108) uses `ReadAsync` plus `IsCompleted` polling rather than a blocking `.ReadToEnd()`, and every blocking wait in the file is expressed via `.GetAwaiter().GetResult()` (lines 76, 77, 84, 85, 96, 111) or `.WaitAsync(...)` — exactly matching the repository's own async-preference convention ("even in sync PowerShell use `.GetAwaiter().GetResult()`"), applied consistently throughout.
- DESIGN: the 5ms poll-delay busy-loop at line 108 (`[Threading.Tasks.Task]::Delay(5).GetAwaiter().GetResult()`) runs for the full lifetime of every child process this function starts — for a multi-minute `dotnet publish` or `podman build` call elsewhere in this folder, that is a long-running tight polling loop rather than a true event-driven wait (e.g. `Task.WhenAny` over the pending `ReadAsync` tasks). A minor efficiency concern, not a correctness bug.
- No validation on `-WorkingDirectory` (line 58; no `Test-Path` check) — an invalid or inaccessible directory is only caught by whatever error `ProcessStartInfo`/`Process.Start()` happens to raise (line 82), which is typically a less clear message than a dedicated "WorkingDirectory does not exist" check would give, especially since several callers (e.g. `Invoke-WorkspaceNative`) forward a caller-supplied path straight through.
- Testability: `ConvertTo-CiArgument` is well tested (`Script.Tests.ps1`), but `Invoke-CiProcess` itself has no dedicated direct test for its timeout/kill path (line 93), its stdin path (lines 83-87), or its `MaxRecordChars` overflow guards (lines 100, 104). Its correctness is currently exercised only incidentally, through every other script that calls it via `Invoke-WorkspaceNative` — integration coverage, not a focused unit test of this file's own edge cases.

## Verdict

One of the best-designed files in this set — correct async idioms throughout, deliberate executable resolution, and a tested quoting helper — but `Invoke-CiProcess`'s own edge cases (timeout-kill, stdin, oversized-record) have no direct test, which is the highest-priority gap given how many scripts depend on this file's correctness.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Quotes one value for a Start-Process argument string following the CommandLineToArgvW rules.

Boundary: **Library**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
