# Compiled framing and direct engine hosting

The engine targets both `net10.0` and `net11.0`. PowerShell 7.6 uses .NET 10, so the verified .NET 10 assembly can run in its process. A newer target cannot be made compatible with an older CLR merely by loading it into an assembly load context. The .NET 11 server remains available as an explicitly selected isolated host. The default `Auto` mode selects integrated hosting from the actual CLR: net10.0 on .NET 10, net11.0 on .NET 11 and later. This includes PowerShell Preview without guessing from its executable name or version string.

## What moved

- Git record delimiter scanning, fragmented-record buffering, byte copying and size checks now run in `ByteRecordFramer`, loaded locally from the compatible build (`lib/inprocess` for .NET 10 or `lib/engine` for .NET 11). This removes the PowerShell loop over every byte. It preserves empty records, non-UTF-8 bytes, delimiter boundaries and unterminated final records. Only the unfinished record is retained; no cumulative output capture is introduced.
- `EngineSession` owns the shared dispatcher, native invocations, SQLite worker and terminal bridge for both hosting modes. There is one implementation of execution semantics.
- Direct native reads pass fixed-shape C# metadata and a transient byte array straight to PowerShell. They perform no pipe exchange, framing, JSON encoding or JSON decoding. Input, EOF, cancellation, resize and release also use direct typed calls with fixed replies. Startup and telemetry also use closed local operations. Internal raw queries and rejection diagnostics retain bounded JSON; SQLite persistence remains explicit. No business object is transferred.

The facade retains caller callbacks, interaction, nested invocation coordination and business object delivery. Moving those objects through the isolated engine would create serialization, copy and identity costs. Rewriting these portions needs a separate contract preserving scriptblock and object identity semantics.

## Select a host

```powershell
# Objective: Close the owned session, then use the compatible engine without pipe IPC.
Stop-QuietEngine
$env:QUIETCLI2_ENGINE_MODE='InProcess'
Get-QuietEngine

# Objective: Select the isolated .NET 11 server for the next session.
Stop-QuietEngine
$env:QUIETCLI2_ENGINE_MODE='Process'
```

Both modes keep business Data in PowerShell. Imports remain inert. The compiled framer is lazy and independent of host selection. Native programs remain separate owned processes even when the engine runs locally.

Direct hosting has a shared failure boundary. A request timeout stops the caller's wait and schedules session disposal; it does not forcibly interrupt an arbitrary blocked managed/native operation in PowerShell. Disposal serializes behind the active request and then cancels owned processes. Hard isolation and independent engine termination require the `Process` host. An assembly already loaded in PowerShell cannot be replaced in place; restart PowerShell after rebuilding it.

## Reproduce measurements

`FrenchExDev2.QuietCli.Core.Tests.PoSh/Performance.Tests.ps1` is part of the existing Core suite. Run `scripts/Build-Workspace.ps1`, then `scripts/Invoke-WorkspaceCi.ps1 -SkipBuild -Suite All`. The launcher opens the required visible monitor and persists `summary.json` under its run directory. `Suites[].Performance` contains only counters and timing samples.

Framing uses identical 1 MiB synthetic inputs, 16 KiB blocks and record widths of 64 and 8,192 bytes. Three samples per implementation alternate order after helper warmup. The baseline reproduces the former scan/buffer/copy loop with a constant delimiter; neither side includes a real Git parser callback. This is a local mechanism comparison, not a Git throughput guarantee.

Hosting uses the same independent fixture to emit 8 MiB, with 16 KiB blocks and a no-op byte callback. Three warm samples per mode include producer startup, drainage, back-pressure, callback dispatch and metadata processing. Native elapsed time overlaps these costs and must not be subtracted to claim pure IPC latency. Runtime differences (.NET 10 versus .NET 11 RC), scheduling, JIT and host load also affect the comparison. Startup samples load a session after the helper assembly is already loaded; they are not fresh-PowerShell startup timings.

Direct mode reports zero `ProtocolInputBytes` and `ProtocolOutputBytes`; these counters describe actual pipe traffic, not an estimate of local object allocation. Request counts remain available in both modes. `DirectRequests` counts direct native reads/controls; `MetadataJsonRequests` counts requests encoded as metadata JSON. Their sum equals `Requests`, including valid rejected replies; a direct rejection may still encode its bounded diagnostic response. `BuildRuntimeIdentifier=portable` describes the AnyCPU .NET 10 build; `RuntimeIdentifier` describes the actual host architecture.

The first local experiment retained JSON for direct native reads and was slower than the isolated host on the 8 MiB fixture. That result motivated the direct read API. Compare final reports rather than assuming that eliminating a process boundary alone makes the complete workload faster.

## Remaining candidates

The [second pass](powershell-csharp-boundaries.md) moves generic text framing and telemetry aggregation to C#. Typed input/lifecycle and metadata operations, caller-local metadata freezing, standard YAML emission and probe identity construction are implemented. Git-owned argument and format parsers are also implemented in their own dual-target companion; see the [final ordered audit](audits/2026-11-05-core-then-git.md). Their priority needs measured representative workloads; moving them blindly can exchange interpreter cost for per-record IPC or business-object serialization.

Cross-platform execution and release qualification remain separate from local Windows measurements. Building all six publications establishes compilation and binary architecture, not successful execution on those six platforms.

## Integrated host CI matrix

The reusable `ci.yml` Windows matrix requires stable PowerShell 7.6.7/.NET 10 and PowerShell 7.7.0-preview.5/.NET 11, each on native x64 and ARM64 runners in integrated mode. The two stable isolated-host entries remain, for six Windows combinations. All entries contribute to the existing mandatory Windows result in the qualification gate; preview failures cannot be ignored for publication.

`build/powershell-hosts.lock.json` pins the four official ZIP archives by version, architecture and SHA-256. `Initialize-PowerShellHost.ps1` downloads and verifies each archive into a private directory, without system installation or profile changes. CI places the selected directory first on PATH. The test launcher uses its own `$PSHOME` executable so its worker cannot silently switch back to a stable host found elsewhere on PATH.

Each matrix worker verifies the exact PowerShell version, actual CLR major and native RID. Integrated entries additionally require the corresponding loaded target framework, engine PID equal to the worker PID, and zero pipe traffic. Summary artifacts retain actual host/runtime/build identities, even on failure. `HostMatrix.Tests.ps1` independently requires every integrated combination, the locked versions, retained isolation and the mandatory qualification dependency.

Official host sources: [stable release](https://github.com/PowerShell/PowerShell/releases/tag/v7.6.7), [preview release](https://github.com/PowerShell/PowerShell/releases/tag/v7.7.0-preview.5), [side-by-side ZIP installation](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows#zip-package).
