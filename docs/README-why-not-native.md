# Why `quiet` stays a PowerShell module, not a native binary

`quiet` is the alias exported for `Invoke-QuietCli`, a binary cmdlet hosted inside the `pwsh`
process (see [FrenchExDev2.QuietCli.Core.PoSh.psm1](../FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psm1)).
This note records why a standalone native (AOT or ReadyToRun) `quiet.exe`, called as an external
command instead, was rejected, and where the actual cold-start lever already lives.

## ScriptBlock parameters require in-process hosting

A `[ScriptBlock]` parameter (used by `-Output`/`-Complete` callbacks) only exists as a live object
bound to the caller's session state inside the PowerShell engine's own parameter binder. That
binding is only available to a binary cmdlet loaded via `Import-Module` into the same `pwsh`
process — exactly how `ForEach-Object`, `Where-Object` and `Register-ArgumentCompleter` work.

A true external/native executable never receives that object. PowerShell stringifies a
`ScriptBlock` argument to its source text before it reaches argv; the native process gets plain
text and cannot execute it as a closure over the caller's variables without embedding a
PowerShell engine itself — at which point it is not a "native, non-pwsh" binary any more.

## Native tab-completion still needs PowerShell-side glue

Shell completion for a true native executable (the `gh`/`kubectl`/`rustup`/`az` pattern) works by
having the exe print candidates for a given partial command line, and having a small PowerShell
script call it and feed the result back. That registration step —
`Register-ArgumentCompleter -Native -CommandName <name> -ScriptBlock { ... }` — is PowerShell's
only extensibility point for tab-completion; it cannot be replaced by anything living purely in
the native binary. Going native would not remove this PowerShell-side glue, only shrink it.

## A standalone process breaks the zero-serialization contract

`-AsObject` keeps business `Data` local to the process and never enumerates or serializes it
(see [README-configuration.md](README-configuration.md) and the root `AGENTS.md`: "Never add a
business-object serialization step to the direct read path"). That guarantee depends on `Core`
and its caller sharing one `EngineSession` inside the same CLR — the `InProcess` hosting mode
described in [README-hosting.md](../README-hosting.md).

A standalone native `quiet.exe` is always a separate process from the caller's `pwsh`. Every
result would have to cross a process boundary as text (JSON/YAML), which is precisely the
`Process`-hosting isolation path that already exists today as an explicit, opt-in mode — never
the default, because it is slower and forces serialization of business data that `InProcess`
mode keeps out of the delivery path entirely. Making native the *only* mode would regress every
caller to the slower path by default.

## PowerShell's own engine is not AOT-published

`System.Management.Automation` is not published as Native AOT; it relies on reflection-heavy,
dynamic parameter binding that AOT trimming does not support. Binary cmdlets necessarily run
hosted inside `pwsh` (or `powershell.exe`), which is itself a framework-dependent/ReadyToRun .NET
app, not an AOT one. There is no supported way to host a PowerShell binary module, with
`ScriptBlock` parameters and pipeline binding, inside a Native AOT process.

## Where the real cold-start lever already is

The engine already ships ReadyToRun builds selected by `Auto` hosting: `lib/inprocess` (net10.0,
for CLR 10) and `lib/engine` (net11.0, for CLR 11+), as documented in the root `AGENTS.md` and
[README-hosting.md](../README-hosting.md). R2R pre-JITs the module's own IL to native code without
giving up reflection or dynamic binding, so it is compatible with PowerShell's binary-module model
and is the lever actually available for reducing import/first-call latency — see
[README-readytorun_profiling.md](README-readytorun_profiling.md) for comparison methodology.
Publishing `quiet` itself as a separate Native AOT executable is not pursued, because the time it
could save on process startup is smaller than the hosting and serialization guarantees it would
cost.

## Summary

| Option | ScriptBlock callbacks | Native tab-completion | Zero-serialization `-AsObject` | Verdict |
|---|---|---|---|---|
| PowerShell binary cmdlet (current) | Native, in-process | Needs PowerShell glue (as for any command) | Yes, `InProcess` hosting | Kept |
| Standalone native/AOT `quiet.exe` | Not possible without embedding PowerShell | Still needs PowerShell glue, no benefit gained | No, forces `Process`-style serialization | Rejected |

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
