<p align="center">
  <img src="../icons/logo.png" alt="QuietCli logo" width="150px" />
</p>

# QuietCli Core

**The `QuietCli` PowerShell module provides Core, the foundation of the QuietCli ecosystem.** It provides the PowerShell entry point `quiet`, the C# process engine, streaming callbacks, typed execution results and bounded deliveries. Use it directly to turn native output into business data, or as the dependency of a companion module that supplies reusable command handlers.

[QuietCli overview](../README.md) · [Documentation index](../docs/README.md) · [Local checkout, build and first command](#local-checkout-and-first-command)

## What Core provides

- **Native execution:** process startup, streamed stdout/stderr, stdin, cancellation, timeouts and terminal transports.
- **Business callbacks:** `-Output` accumulates caller-local data; `-Complete` returns the business result.
- **Business events:** `$runtime.Emit(...)` collects ordered `Events` and notifies per-call `-Listeners`; `-UI` exposes explicit live presentation lanes.
- **Explicit results:** `Outcome`, `Execution`, `Completeness` and errors distinguish success from incomplete or failed work.
- **Controlled delivery:** local objects with `-AsObject`, or bounded JSON/YAML views with measured delivery sizes.
- **Reusable analysis:** script generation, handler registration, companion-module scaffolding and opt-in Recall evidence.
- **Configuration and measurements:** YAML settings and SQLite metadata/counters, with business output excluded from telemetry.

Command-specific parsing belongs in callbacks or companion modules. Core does not automatically supply business semantics for every executable.

## Requirements

| Item | Requirement |
| --- | --- |
| PowerShell | Core 7.6 or later |
| Platforms | Windows x64/ARM64; Linux glibc or musl x64/ARM64 |
| Default hosting | `Auto`: compatible integrated .NET 10 or .NET 11+ build |
| Isolated hosting | `Process` requires the pinned .NET 11 RC runtime for the selected architecture |
| Native tools | Install the executables you intend to invoke separately |

A built module needs no SDK to import or use. Import does not compile C#, start the engine or run a native command. Distributed targets and executed qualification are separate; see [tests and qualification](../README-qualification.md).

## Installation

The public module and Gallery package are named `QuietCli`. `FrenchExDev2.QuietCli.Core.PoSh` is the internal source project name.

### From PowerShell Gallery

```powershell
Install-PSResource -Name QuietCli -Prerelease -Repository PSGallery -Scope CurrentUser
Import-Module QuietCli -ErrorAction Stop
```

`-Prerelease` includes available previews; omit it for stable releases only. See [package installation](../docs/README-PSGallery.md) for availability and runtime details.

### Local checkout and first command

Use PowerShell Core 7.6+, Git and the exact .NET SDK pinned in `global.json` (currently `11.0.100-rc.3.26522.148`). Build before importing the local modules. Close sessions that already loaded this checkout's assemblies before rebuilding.

**1. Check out and build.**

The commands start in a parent directory of your choice and clone the whole monorepo into `$HOME/src/QuietCli`. For an existing checkout, set `$checkout` to its root and skip the clone. Git performs this initial bootstrap before local `quiet` is available; the build script uses the engine-independent process helper.

```powershell
$checkout = Join-Path $HOME 'src/QuietCli'
New-Item -ItemType Directory -Path (Split-Path $checkout -Parent) -Force | Out-Null
git clone --branch develop https://github.com/FrenchExDev2/FrenchExDev2.QuietCli.PoSh.git $checkout
if ($LASTEXITCODE -ne 0) { throw 'CheckoutFailed' }
Set-Location $checkout
./scripts/Initialize-Workspace.ps1 -Restore
./scripts/Build-Workspace.ps1
```

All paths are relative to the monorepo root. `-Restore` verifies the committed source lock; on an intentionally edited checkout, `./scripts/Initialize-Workspace.ps1` without `-Restore` refreshes the local lock. A successful build creates the compiled engine and companion binaries; it does not publish or install a Gallery package.

**2. Import and run in a fresh session.**

**Open a new PowerShell Core 7.6+ session with its normal profile**, then paste the following block. Reassigning `$checkout` makes the new session independent of variables from the build session.

```powershell
$checkout = Join-Path $HOME 'src/QuietCli'
Set-Location $checkout
Import-Module ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1 -ErrorAction Stop
Get-Alias quiet

$r = quiet -AsObject -C sdk-version -WorkingDirectory (Get-Location).Path `
    -RecordDelimiter "`n" -Data @{ Version = $null; Records = 0 } `
    -Output {
        param($event, $runtime)
        if ($event.Stream -eq 'stdout') {
            $runtime.Data.Version = $event.Text.Trim()
            $runtime.Data.Records++
        }
    } `
    -Complete {
        param($runtime)
        if ($runtime.Data.Records -ne 1) { throw 'ExpectedOneSdkVersion' }
        [pscustomobject]@{ SdkVersion = $runtime.Data.Version }
    } `
    dotnet --version
if ($r.Outcome -ne 'Success' -or !$r.Completeness.Source -or !$r.Completeness.Analysis -or $r.Error.Count) {
    throw 'IncompleteSdkVersion'
}
Out-QuietResult $r -AsYaml -MaxItems 5 -MaxOutputBytes 4096
```

YAML excerpt; invocation IDs and other envelope metadata are omitted. The version shown is the SDK selected in this checkout. `-Output` reads one native record; `-Complete` creates `{ SdkVersion }`. `-AsObject` keeps that result local, and `Out-QuietResult -AsYaml` formats the same result without executing `dotnet` again.

```yaml
"Outcome": "Success"
"Context": "sdk-version"
"Data":
  "SdkVersion": "11.0.100-rc.3.26522.148"
"Completeness":
  "Source": true
  "Analysis": true
```

The source manifest above loads the local Core project. The public Gallery module is named `QuietCli`; its installation uses `Install-PSResource -Name QuietCli` and `Import-Module QuietCli`.

## First use

This standalone example uses the installed `QuietCli` module. The local checkout recipe above runs the same contract with the source manifest. `dotnet` must be installed.

```powershell
Import-Module QuietCli -ErrorAction Stop

$r = quiet -AsObject -C sdk-version -WorkingDirectory (Get-Location).Path `
    -RecordDelimiter "`n" -Data @{ Version = $null; Records = 0 } `
    -Output {
        param($event, $runtime)
        if ($event.Stream -eq 'stdout') {
            $runtime.Data.Version = $event.Text.Trim()
            $runtime.Data.Records++
        }
    } `
    -Complete {
        param($runtime)
        if ($runtime.Data.Records -ne 1) { throw 'ExpectedOneSdkVersion' }
        [pscustomobject]@{ SdkVersion = $runtime.Data.Version }
    } `
    dotnet --version
if ($r.Outcome -ne 'Success' -or !$r.Completeness.Source -or !$r.Completeness.Analysis -or $r.Error.Count) {
    throw 'IncompleteSdkVersion'
}
Out-QuietResult $r -AsYaml -MaxItems 5 -MaxOutputBytes 4096
```

YAML excerpt; invocation IDs and other envelope metadata are omitted. The version shown is the SDK selected in this checkout. `-Output` reads one native record; `-Complete` creates `{ SdkVersion }`. `-AsObject` keeps that result local, and `Out-QuietResult -AsYaml` formats the same result without executing `dotnet` again.

```yaml
"Outcome": "Success"
"Context": "sdk-version"
"Data":
  "SdkVersion": "11.0.100-rc.3.26522.148"
"Completeness":
  "Source": true
  "Analysis": true
```

The native version line becomes a typed object with one `SdkVersion` property. `Outcome`, `Completeness` and errors describe whether that object can be trusted. See [streaming, callbacks and results](../README-streaming.md).

## Contract

`Invoke-QuietCli`, aliased as `quiet`, uses explicit callbacks or a documented compatible registered handler. Unsupported commands without either are rejected before business execution; explicit `-SaveRecall` can also record without an analyzer.

`-Output` receives an event and the runtime. Keep required business data in `runtime.Data` and emit no incidental pipeline output; discard method return values with `[void]`. `-Complete` receives the runtime and returns zero or one value; use `,$array` for an array as one value. Callbacks remain in PowerShell and must cooperate with cancellation.

Native streams are consumed once through bounded buffers. Without explicit Recall capture/recording, there is no cumulative raw capture, spool or content history. Byte events expose transient `Bytes` and `ByteCount`; strict incremental UTF-8 decoding and delimiter framing reject invalid input, incomplete characters and oversized records.

`-AsObject` returns the envelope without traversing, serializing or transferring business `Data` to the engine. `ConvertTo-QuietJson`, `ConvertTo-QuietYaml` and `Out-QuietResult` apply item, structural and encoded-byte budgets. `Deliveries[0]` contains the most recent delivered text and identifier; successive delivery strings do not accumulate. See [streaming, callbacks and results](../README-streaming.md).

## Hosting, runtime and transports

`Auto` selects the integrated `lib/inprocess` net10.0 build on CLR 10 and the compatible net11.0 build on CLR 11+. Never load the .NET 11 assembly into CLR 10. YAML `engine.hosting` selects `Auto`, `InProcess` or isolated `Process`; close the owned session with `Stop-QuietEngine` before changing modes. `Get-QuietEngine` reports the actual mode, runtime, process identity and transport counters.

Integrated hosting keeps native reads, lifecycle controls, callbacks and business data in the caller, without pipe IPC. It shares PowerShell's failure boundary: disposal cancels owned native processes but cannot forcibly unload or terminate code inside the host. `Process` provides engine-process isolation. `New-QuietByteRecordFramer` supplies bounded compiled byte framing locally in either mode; `TextStreamState` handles strict incremental text decoding and framing.

The six architecture-specific publications under `lib/engine/<RID>` serve isolated execution. Their PE/ELF apphosts and assemblies match the selected architecture. Packages include SQLite and static Linux PTY bridges; the engine verifies and copies its Linux bridge into a private executable directory, leaving the installed module unchanged. These are framework-dependent builds, not NativeAOT.

The callback runtime exposes `Request`, `Data`, `State`, `Execution`, `Children`, identifiers and `WriteBytes`, `WriteText`, `CompleteInput`, `ReadEvent`, `Resize`, `Cancel`. Pipes distinguish stdout/stderr; PTY merges output into `TerminalBytesRead`, with separate stream counts unknown. Windows uses ConPTY; Linux uses the verified bridge. Ending terminal input is not a pipe half-close.

Nested calls inherit the measurement context and return an object by default; their failures remain visible even when results are assigned. `quiet -C name` does not change later independent calls. See [hosting and native transports](../README-hosting.md).

## Live dashboard (`-UI` / `-MaxLines`)

`-UI` renders a live, lane-based dashboard of the call's `Emit`/`Output` events via [Spectre.Console](https://spectreconsole.net/); `-MaxLines` sets the per-lane tail depth (default `1`) and requires `-UI`. Each lane is keyed by a business-chosen string (for example a machine name in a multi-target companion module); the default, unkeyed lane renders without a redundant `[key]` prefix, and an event's own `Machine`-shaped property is likewise omitted from a line when it already matches its lane's key. A lane always shows its latest line even when the caller never calls `NewLine` on it.

`Spectre.Console` is a Central Package Management dependency declared in `Directory.Packages.props` (no `Version=` on the `<PackageReference>` in the engine's `.csproj`, per the repository's CPM convention). A render failure is caught, logged once via the same failure-reporting path as other engine failures, and permanently disables further rendering for that call without propagating the exception to the caller or the native process. Nested `-UI` calls in the same process cannot share one live terminal session: the inner call's surface construction detects the conflict and falls back to a plain append-only renderer instead of a live-redrawing one.

The live viewport remeasures its width and height on each draw, even when lane data has not changed.
It clips paths and messages at Unicode text-element boundaries, strips terminal controls, compacts
the project/task heading in narrow windows and reduces visible lane history to the available height.
These presentation limits do not truncate the invocation's collected business events.

## Configuration

Settings live in `~/.quietcli/config.yaml`; `QUIETCLI_CONFIG_DIRECTORY` is the sole product configuration environment override. Use `New-QuietCliConfiguration`, `Test-QuietCliConfiguration`, `Get-QuietCliConfiguration` and `Import-QuietCliConfiguration` to manage them explicitly.

Explicit invocation options override the session YAML snapshot, then built-in defaults. See the [configuration contract](../docs/README-configuration.md) for the schema, reload behavior, unique delivery identities, `AlreadyDelivered` and encoding-specific token measurements.

## Recall

Explicit `-Recall -AsObject` retains bounded in-memory native evidence. `-RecallMaxBytes` accepts integral bytes, IEC sizes or `All`; `-RecallPolicy` selects `Head`, `Tail` or `HeadAndTail`. `Invoke-QuietRecall` analyzes retained evidence without executing the native command again.

`-SaveRecall` writes a durable journal during execution. `-RecallName`, `Get-QuietSavedRecall` and `quiet -RecallId` support later sessions with new callbacks and projections. Default export is a streaming working directory; explicit `-Zip -Compress 0..9` selects ZIP64 transport. Evidence stays outside ordinary deliveries and SQLite. See [Recall usage](../README-recall.md) and the [full contract](../docs/README-recall.md).

## Reusable scripts and business factories

`-Script path.ps1` writes a readable call definition and returns its `FileInfo`.
It never starts a native process, evaluates a callback/factory or writes execution
measurements. The destination must be a new `.ps1` file in an existing directory.
At least one explicit `-Output` or `-Complete` callback is required.

```powershell
Import-Module QuietCli -ErrorAction Stop

# Generation writes a new definition and does not execute dotnet.
$file = quiet -Script ./CountBytes.ps1 -AsObject -StdoutMode Bytes -StderrMode Bytes -DataFactory { @{ Bytes = 0L } } -Output {
    param($event, $runtime)
    if ($event.Stream -eq 'stdout') { $runtime.Data.Bytes += $event.ByteCount }
} -Complete { param($runtime) $runtime.Data } -FilePath dotnet -ArgumentList @('--list-sdks')

$result = & $file.FullName
if ($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis -or $result.Error.Count) { throw 'IncompleteByteCount' }
Out-QuietResult $result -AsYaml -MaxItems 5 -MaxOutputBytes 4096

# Reuse the same byte-counting contract with different native arguments.
$infoResult = & $file.FullName -ArgumentList @('--info') -WorkingDirectory $PWD.Path
if ($infoResult.Outcome -ne 'Success' -or !$infoResult.Completeness.Source -or !$infoResult.Completeness.Analysis -or $infoResult.Error.Count) { throw 'IncompleteByteCount' }
Out-QuietResult $infoResult -AsYaml -MaxItems 5 -MaxOutputBytes 4096
```

Each execution returns `{ Bytes }`: the total stdout bytes seen by that call's callbacks. Generation itself returns a `FileInfo`. Example YAML excerpts measured on one Windows x64 host; byte counts vary with installed SDKs and native output.

`--list-sdks`:

```yaml
"Outcome": "Success"
"Data":
  "Bytes": 95
```

`--info`:

```yaml
"Outcome": "Success"
"Data":
  "Bytes": 3687
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

## Measurements

`Get-QuietCliGain` returns a `PSCustomObject` by default (`-AsObject` remains supported). Use `-AsYaml` or `-AsJson` to format the report; `-AsJson -Compress` selects compact JSON. `-Compress` is only valid with `-AsJson`, and output formats are mutually exclusive. Reading or formatting this report never creates invocation or delivery telemetry and does not contribute to measured delivery gains.

Without `-From`, `-To` or `-Days`, the report selects all history. Omitted or null boundaries remain null in the report and do not restrict that side of the time range. `-Days 7` explicitly selects a trailing seven-day window ending at `-To`, or now when omitted. An explicit `-From` overrides `-Days`. `-MaxEvents` still limits the scan; `Complete=false` means the selected history was not fully scanned.

`ReductionBytes` compares deduplicated business sources associated with actual root deliveries against the bytes of every corresponding delivery. It stays null when the scan, source/analysis completeness or required byte measurements do not support that comparison. `Complete=true` describes scan completeness, not source completeness. Object-only calls do not establish delivery savings. `NativeTokens` remains null because native output is not tokenized; optional tokenization counts only actual delivered text. Missing allocation samples also leave the aggregate allocation total null rather than treating missing measurements as zero.

`Get-QuietCliGain` reads all contexts by default. `-C nom`, `-Generic`, `-SessionId`, `-From`, `-To` filter the report. Unique sources are deduplicated; unknown reductions remain null. Auxiliary roles do not inflate business gains.

Native token counts remain unknown. Exact tokenization applies to the final delivered text. The default is `o200k_base`; use `-Tokenizer cl100k_base` or `off` to override it.

SQLite stores only metadata and counters. `telemetry.database` selects the database; `telemetry.enabled: false` disables writes. Storage errors remain separate from the business result.

## Limits, integrity and privacy

`-DrainTimeoutSeconds` bounds the wait for EOF after the process exits (30 s by default). A drain cutoff makes the source incomplete, even if the main process has already finished. `engine.ipcTimeoutSeconds` bounds each exchange with the engine (30 s by default, between 0.05 and 300 s). A transport failure closes the owned engine and preserves the unknown effect of an unconfirmed startup. A new independent root call may start a new engine; the interrupted call is never repeated.

The final result's `Execution` and `Completeness` are detached, read-only snapshots. Runtime transitions are validated. `Data` remains local and mutable for subsequent deliveries.

Detailed diagnostics remain local. SQLite accepts only closed DTOs, including nested properties; persisted errors contain their codes and phases, without callback messages. Older events are projected onto only the fields allowed at read time, without implicit rewriting. To explicitly purge their old fields:

```powershell
Import-Module QuietCli -ErrorAction Stop

# Goal: preview the explicit purge of the selected database without modifying history.
Repair-QuietCliMeasurementPrivacy -WhatIf

# Goal: purge old sensitive fields after explicit interactive confirmation.
Repair-QuietCliMeasurementPrivacy
```

This operation permanently modifies rows in the selected database. It does not guarantee physical erasure from backups or storage media. Imports, builds and tests never purge a user database.

`Get-QuietCliGain -MaxEvents 10000` uses cursor pagination and an IPC budget; `Complete=false` indicates a report stopped by its limit. Query errors remain distinct from transport failures.

`resources/dependencies.lock.json` links bundled resources to their versions, hashes and licenses under `third_party`. Integrity is verified before engine startup and tokenizer loading. A bundled SQLite library that is present but invalid causes an explicit failure; fallback is limited to absolute system paths. A checksum proves neither an author's identity nor the absence of known vulnerabilities.

The build produces a manifest linking C# sources, SDK, protocol and compiled files. Tests reject a stale or modified build, including with `-SkipBuild`. `protocol.json` provides the limits shared by C# and PowerShell.

For the concrete mechanics behind every rule in this section, and how a companion module could plug its own privacy/integrity policy into them, see [privacy and integrity internals](../docs/README-privacy-and-integrity-internals.md).

## Companion modules and agent integration

`Register-QuietHandler`, `Get-QuietHandler` and `Unregister-QuietHandler` manage reusable handlers. `New-QuietModule` scaffolds a companion module; executable semantics and independent assertions belong in that module and its test companion. The Git module is an example under development, with explicit coverage limits. See [companion modules](../README-modules.md).

To install agent instructions after Core is installed, use `Add-QuietAgentInstruction -Path ./project -Agents`. It copies the distributed rules/skill into the project's `.skills` directory and adds a managed reference to `AGENTS.md`, preserving existing text outside that block. `-WhatIf` previews changes; `Get-QuietAgentInstruction` reads the rules without writing files or starting the engine. These commands return text or file metadata, not native execution envelopes.

See [agent integration](../README-agents.md), the [Codex guide](../docs/agents/codex.md) and the [agent documentation index](../docs/agents/README.md).

## Tests and dependencies

Tests live in `FrenchExDev2.QuietCli.Core.Tests.PoSh`, with independent C# assertions and PowerShell scenarios. The SDK/runtime are pinned in `global.json` and the C# projects. Companion tests verify matching build inputs and binaries, including with `-SkipBuild`; supplied RIDs do not establish qualification of unexecuted platforms.

From the monorepo root, `./scripts/Invoke-WorkspaceCi.ps1 -Suite Core -SkipBuild` runs Core with the shared visible monitor. `-Suite All` also validates the dependent Git companion. Focused `Import`, `Integration`, `RealStatus`, `Script`, Recall and other suites establish only their executed scope. Property, fuzzing and targeted mutation results remain distinct from platform/release qualification.

See [tests and qualification](../README-qualification.md) for local campaigns, profiling, R2R comparisons, GitHub workflows, exclusions and report locations; [Core performance evidence](PERFORMANCES.md) defines controlled workloads and measurements.

## Further reading

| Topic | Guide |
| --- | --- |
| Product overview and first examples | [QuietCli](../README.md) |
| Callbacks, results and bounded delivery | [Streaming](../README-streaming.md) |
| Engine selection, process isolation and PTY | [Hosting](../README-hosting.md) |
| Measurements, allocation and retention | [Measurements and privacy](../README-measurements.md), [allocation metrics](../docs/README-allocation-and-delivery-metrics.md) |
| Compiled framing and PowerShell/C# responsibilities | [Hosting details](../docs/README-performance-and-hosting.md), [component boundaries](../docs/README-powershell-csharp-boundaries.md) |
| All guides, CI references and dated evidence | [Documentation index](../docs/README.md) |

## License

[MIT](LICENSE). Bundled dependencies retain their own licenses and provenance.
