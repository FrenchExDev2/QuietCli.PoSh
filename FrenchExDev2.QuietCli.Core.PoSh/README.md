<p align="center">
  <img src="./../icons/logo.png" alt="Requirement-As-Code logo" width="150px" />
</p>

# FrenchExDev2.QuietCli.Core.PoSh

## Production agent instructions

After installation, use `Add-QuietAgentInstruction -Path ./project -Agents` to copy the
[production instructions](../docs/agents/AGENTS.md) and their skill guide into the project's
`.skills` directory and add a managed reference in its `AGENTS.md`. Existing rules outside
that block are preserved. `-WhatIf` previews changes. `Get-QuietAgentInstruction` reads the
distributed rules without creating files or starting the engine. These commands return text
or file metadata rather than native execution envelopes. See the [Codex guide](../docs/agents/codex.md)
and [progressive Core workflows](../docs/agents/SKILL.md).

PowerShell Core 7.6+ facade for the C# .NET 10 / .NET 11 RC engine, with integrated or isolated hosting. Sources live under `engine/`; compatible integrated assemblies and isolated publications are selected from `lib/`. No SDK is required to import or use a built module.

Import reads the integer protocol specification through asynchronous host .NET file I/O and `System.Text.Json`, with the existing version and frame-size bounds. Source paths and alias creation also use host APIs, so import does not autoload the Management or Utility cmdlet modules. Engine initialization remains lazy. The companion's focused `Import` suite measures fresh-process loading; `RealStatus` checks direct callbacks on explicitly selected real repositories without the Git companion.

The same C# sources also build for `net10.0` under `lib/inprocess`. Set YAML `engine.hosting: InProcess` before starting the engine to host it directly in PowerShell 7.6. `Stop-QuietEngine` closes the current session before a mode change. The .NET 11 assembly is loaded only when the actual PowerShell CLR is .NET 11 or later. `Auto` is the default hosting mode; it selects a compatible integrated build. `Get-QuietEngine` reports `Mode`, actual runtime, process identity and real pipe counters (zero in direct mode). Native reads and input/lifecycle controls use direct objects and byte arrays. Startup and telemetry use closed local metadata operations. Only internal raw queries and rejected-request diagnostics retain transport JSON; persisted SQLite metadata still uses its validated JSON representation. `DirectRequests` and `MetadataJsonRequests` count the selected request paths; their sum is `Requests`. These counters describe dispatch, while the protocol byte counters measure actual pipe traffic. Business Data and callbacks remain caller-local.

`New-QuietByteRecordFramer` provides bounded compiled byte framing without IPC; Git uses it even with the isolated host. Loading is lazy and verifies the integrated build compatible with the actual CLR. Start a new PowerShell process after rebuilding a loaded assembly. Direct hosting shares the host's failure boundary: disposal cancels owned native processes, but cannot forcibly kill or unload code inside PowerShell. Keep `Process` when that isolation is required. See [hosting measurements](../docs/performance-and-hosting.md).

`TextStreamState` handles strict incremental UTF-8 decoding and delimiter framing locally, without IPC. `Get-QuietCliGain` delegates safe telemetry aggregation to the SQLite worker and receives only counters and aggregate group pages. Caller callbacks and business objects stay in PowerShell. See [the second migration pass](../docs/powershell-csharp-boundaries.md).

The six publications under `lib/engine/<RID>` target Windows x64/ARM64 and Linux glibc/musl x64/ARM64, with `PlatformTarget` set to x64 or ARM64 and a native apphost of the same architecture. The facade selects PowerShell's actual RID. The build verifies the PE assembly and the PE or ELF apphost without loading the engine assembly into the host. The corresponding .NET 11 RC runtime is still required; no NativeAOT compilation is involved. The portable build remains reserved for references and tests.

PSGallery packages also include SQLite and the static PTY bridges for the four Linux RIDs. The engine copies the verified bridge into its private executable directory; it does not modify a module installed as read-only. Imports remain inert.

See [configuration and unique tokenized deliveries](../docs/configuration.md) for `~/.quietcli/config.yaml`, `QUIETCLI_CONFIG_DIRECTORY`, the four configuration cmdlets, `o200k_base` defaults, `AlreadyDelivered` and encoding-specific SQLite measurements.

## Contract

Opt-in [Recall capture and offline analysis](../docs/recall.md) retains native bytes only with explicit `-Recall -AsObject`. `-RecallMaxBytes` accepts integral bytes, IEC sizes or `All`; `-RecallPolicy` selects `Head`, `Tail` or `HeadAndTail`. `Invoke-QuietRecall` reuses decoding without executing a process. `-SaveRecall` writes a durable journal during execution; `-RecallName`, `Get-QuietSavedRecall` and `quiet -RecallId` support later sessions with new callbacks and delivery projections. Default export is a streaming working directory; `-Zip -Compress 0..9` explicitly selects measured ZIP64 transport. Evidence remains excluded from ordinary deliveries and SQLite. The no-retention statements below describe the default streaming path.

`Invoke-QuietCli`, aliased as `quiet`, accepts its options before the executable. `-Output` receives an event and the runtime; `-Complete` finalizes `runtime.Data`. Without these callbacks, the registry selects a documented, compatible handler. Imports remain inert.

Native streams are consumed only once. The engine retains only byte counts and bounded buffers. It creates no cumulative capture, spool or content history. Byte events have a `ByteCount` and transient `Bytes`; text framing retains only a bounded unfinished fragment. Exceeding the limit or encountering incomplete UTF-8 causes an explicit failure.

`-AsObject` returns the envelope and local object without traversing, serializing or transferring `Data` to the engine. JSON/YAML produce and measure only their actual representation, bounded by `MaxItems`, a structural limit and `MaxOutputBytes`. The most recently delivered text is available in `Deliveries[0]` with its identifier; strings from successive deliveries do not accumulate.

```powershell
# Goal: count bytes without retaining their content.
$r = quiet -AsObject -C analyse -StdoutMode Bytes -Data @{ Bytes = 0L } -Output {
    param($event, $runtime)
    $runtime.Data.Bytes += $event.ByteCount
} executable arguments
```

Do not emit output from `Output`; use `[void]` for methods that return a value. `Complete` returns zero or one value. For an array, use `,$array`. Callbacks remain in the calling process and must cooperate with cancellation.

## Reusable scripts and business factories

`-Script path.ps1` writes a readable call definition and returns its `FileInfo`.
It never starts a native process, evaluates a callback/factory or writes execution
measurements. The destination must be a new `.ps1` file in an existing directory.
At least one explicit `-Output` or `-Complete` callback is required.

```powershell
# Generate only; the executable does not need to exist yet.
$file = quiet -Script ./CountBytes.ps1 -AsObject -StdoutMode Bytes `
    -DataFactory { @{ Bytes = 0L } } `
    -Output {
        param($event, $runtime)
        if ($event.Stream -eq 'stdout') { $runtime.Data.Bytes += $event.ByteCount }
    } `
    -Complete { param($runtime) $runtime.Data } `
    -FilePath tool -ArgumentList @('--list')

# Execute later, optionally overriding the native arguments or working directory.
$result = & $file.FullName
$result = & $file.FullName -ArgumentList @('--other') -WorkingDirectory $PWD.Path
```

`-DataFactory` and `-StateFactory` also work on ordinary calls. Each receives no
arguments and must return exactly one pipeline object; `StateFactory` must return
a hashtable. Use the unary comma to return an array as one object. Factories run
once per invocation, including nested calls, before engine initialization and
native startup. Factory failures terminate the call before native execution.
`Data` conflicts with `DataFactory`; `State` conflicts with `StateFactory`.

Generated scripts require PowerShell Core 7.6+ and import Core only when it is not
already loaded. They expose `FilePath`, `ArgumentList` and `WorkingDirectory` as
parameters. The working directory defaults to the directory selected during
generation; other unspecified options use the configuration active at execution.
The script calls the module-qualified facade and recreates literal initial values
and factory-produced values on every execution.

Export supports finite primitive numbers, strings, characters, booleans, nulls,
one-dimensional primitive/object arrays, hashtables and ordered dictionaries.
Literal generation is bounded to depth 32, 10,000 nodes and 1 MiB of string
characters; the complete script is limited to 2 MiB of characters. Cycles and
unsupported objects fail before creating a file. Use factories for complex
business objects. Recall options and cancellation-token objects cannot be exported.
Callbacks and factories are preserved as PowerShell source with LF line endings.

External variables, functions, modules and closure values are not captured.
Supply dependencies explicitly in the execution environment or edit the generated
script to declare parameters/imports. Explicit values, including environment
options, are written into the script. Export does not qualify the business logic;
keep shared executable semantics and independent tests in companion modules.

The monitored development suite is
`./scripts/Invoke-WorkspaceCi.ps1 -SkipBuild -Suite Script` from the monorepo root.
It includes deterministic literal properties, malformed/boundary corpora, live
script/direct-call comparisons and targeted PowerShell source mutations. Core/All
also includes these regressions; this focused suite does not qualify a release.

## Runtime and transports

The runtime provides `Request`, `Data`, `State`, `Execution`, `Children`, identifiers and `WriteBytes`, `WriteText`, `CompleteInput`, `ReadEvent`, `Resize`, `Cancel`.

The pipe transport distinguishes stdout/stderr. PTY merges output into `TerminalBytesRead`; separate counters are unknown. Windows uses ConPTY; Linux uses a bridge verified by SHA-256. Ending terminal input is not a pipe half-close.

Child calls inherit the context; they return an object by default. Their failures are retained even when their results are assigned to a variable. `quiet -C nom` does not change the context of subsequent independent calls.

## Measurements

`Get-QuietCliGain` returns a `PSCustomObject` by default (`-AsObject` remains supported). Use `-AsYaml` or `-AsJson` to format the report; `-AsJson -Compress` selects compact JSON. `-Compress` is only valid with `-AsJson`, and output formats are mutually exclusive. Reading or formatting this report never creates invocation or delivery telemetry and does not contribute to measured delivery gains.

Without `-From`, `-To` or `-Days`, the report selects all history. Omitted or null boundaries remain null in the report and do not restrict that side of the time range. `-Days 7` explicitly selects a trailing seven-day window ending at `-To`, or now when omitted. An explicit `-From` overrides `-Days`. `-MaxEvents` still limits the scan; `Complete=false` means the selected history was not fully scanned.

`ReductionBytes` compares deduplicated business sources associated with actual root deliveries against the bytes of every corresponding delivery. It stays null when the scan, source/analysis completeness or required byte measurements do not support that comparison. `Complete=true` describes scan completeness, not source completeness. Object-only calls do not establish delivery savings. `NativeTokens` remains null because native output is not tokenized; optional tokenization counts only actual delivered text. Missing allocation samples also leave the aggregate allocation total null rather than treating missing measurements as zero.

`Get-QuietCliGain` reads all contexts by default. `-C nom`, `-Generic`, `-SessionId`, `-From`, `-To` filter the report. Unique sources are deduplicated; unknown reductions remain null. Auxiliary roles do not inflate business gains.

Native token counts remain unknown. Exact tokenization applies to the final delivered text. The default is `o200k_base`; use `-Tokenizer cl100k_base` or `off` to override it.

SQLite stores only metadata and counters. `telemetry.database` selects the database; `telemetry.enabled: false` disables writes. Storage errors remain separate from the business result. No RECORD/replay.

## Tests and dependencies

The companion module is `FrenchExDev2.QuietCli.Core.Tests.PoSh`. It contains the C# test projects and PowerShell assertions. The business module does not contain tests. Native resources are distributed by RID; a RID that is not provided must not be presented as qualified.

The SDK and runtime are pinned in `global.json` and the C# project. An engine failure does not replay any operation and may leave its effect unknown.

## Limits, integrity and privacy

`-DrainTimeoutSeconds` bounds the wait for EOF after the process exits (30 s by default). A drain cutoff makes the source incomplete, even if the main process has already finished. `engine.ipcTimeoutSeconds` bounds each exchange with the engine (30 s by default, between 0.05 and 300 s). A transport failure closes the owned engine and preserves the unknown effect of an unconfirmed startup. A new independent root call may start a new engine; the interrupted call is never repeated.

The final result's `Execution` and `Completeness` are detached, read-only snapshots. Runtime transitions are validated. `Data` remains local and mutable for subsequent deliveries.

Detailed diagnostics remain local. SQLite accepts only closed DTOs, including nested properties; persisted errors contain their codes and phases, without callback messages. Older events are projected onto only the fields allowed at read time, without implicit rewriting. To explicitly purge their old fields:

```powershell
# Goal: preview the explicit purge of the selected database without modifying history.
Repair-QuietCliMeasurementPrivacy -WhatIf

# Goal: purge old sensitive fields after explicit interactive confirmation.
Repair-QuietCliMeasurementPrivacy
```

This operation permanently modifies rows in the selected database. It does not guarantee physical erasure from backups or storage media. Imports, builds and tests never purge a user database.

`Get-QuietCliGain -MaxEvents 10000` uses cursor pagination and an IPC budget; `Complete=false` indicates a report stopped by its limit. Query errors remain distinct from transport failures.

`resources/dependencies.lock.json` links bundled resources to their versions, hashes and licenses under `third_party`. Integrity is verified before engine startup and tokenizer loading. A bundled SQLite library that is present but invalid causes an explicit failure; fallback is limited to absolute system paths. A checksum proves neither an author's identity nor the absence of known vulnerabilities.

The build produces a manifest linking C# sources, SDK, protocol and compiled files. Tests reject a stale or modified build, including with `-SkipBuild`. `protocol.json` provides the limits shared by C# and PowerShell.

See [performance measurements and mandatory Core-only CI integration](PERFORMANCES.md) for historical comparisons, controlled repository states, matrix scope, artifacts and reproduction commands.
