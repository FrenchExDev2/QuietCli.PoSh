<p align="center">
  <img src="./icons/logo.png" alt="QuietCli logo" width="150px" />
</p>

# QuietCli

QuietCli is a streaming native-command engine for PowerShell Core 7.6+, designed for AI agents and developer tooling. A C# engine runs native processes while caller-local callbacks turn their output into business data. Callers can inspect that data directly or deliver a bounded JSON/YAML representation.

Explicit Recall capture preserves native evidence for inspection and offline analyzer development. Durable recording lets work continue in another session, after a reboot or an interrupted recording, without running the original command again.

The Core development manifest declares **0.2.0-preview** (`ModuleVersion='0.2.0'`, `PSData.Prerelease='preview'`). Source-checkout features and package availability are separate: building or testing does not publish a release.

## Start with the local Core module

Use PowerShell Core 7.6+ and import the manifest from this repository:

```powershell
Import-Module ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1

# Count received stdout bytes without retaining their content.
$r = quiet -AsObject -C analysis -StdoutMode Bytes -Data @{ Bytes = 0L } -Output {
    param($event, $runtime)
    if ($event.Stream -eq 'stdout') {
        $runtime.Data.Bytes += $event.ByteCount
    }
} executable arguments

# Inspect execution and source completeness before using the business result.
$r.Outcome
$r.Execution
$r.Completeness

# Produce a bounded delivery and inspect measured volumes.
$json = ConvertTo-QuietJson $r -MaxOutputBytes 4096
Get-QuietCliGain -C analysis
```

Replace `executable arguments` with the intended native command. Facade options precede the executable; native arguments follow it. For an exact argument vector, use `-FilePath` and `-ArgumentList`. Use `-WorkingDirectory` to select the native working directory and `-C` to label the measurement context.

A built module needs no SDK to import or run. Import does not compile C# or start the engine. If binaries are missing or stale, build with `./scripts/Build-Workspace.ps1`, then start a fresh PowerShell process before importing rebuilt assemblies. Build inputs are pinned in `global.json` and the project configuration. Keep modules with overlapping public command names in separate sessions.

See the [Core module README](FrenchExDev2.QuietCli.Core.PoSh/README.md) and [package installation and publication](docs/PSGallery.md) for detailed setup.

## Streaming and callbacks

Without an explicit capture option, stdout/stderr are read once, counted, dispatched through bounded transient buffers and released. No cumulative raw capture, output spool or content history is created. Native queues are bounded to 16 blocks of 16 KiB per invocation. Incremental UTF-8 decoding and delimiter framing run in C#; unfinished records are bounded by `MaxRecordBytes`. Invalid or incomplete UTF-8 and oversized records fail explicitly.

`-Output` receives `(event, runtime)` and must emit no incidental pipeline output. Store required business information in `runtime.Data`; use `[void]` for methods whose return values should be discarded. `-Complete` receives the runtime and returns at most one business value. Use the unary comma to return an array as one value. If it returns no value, the existing `Data` is preserved.

Without explicit callbacks, command execution requires a documented compatible registered handler. Unsupported commands are rejected before business execution. `-SaveRecall` also permits direct recording without a parser.

Collection, retention, decoding, business analysis and delivery are separate responsibilities. `-AsObject` returns a local envelope without enumerating, serializing or transferring `Data` to the engine. Inspect `Outcome`, `Execution`, `Completeness` and errors alongside the business data. JSON/YAML delivery applies item, structural and encoded-byte budgets; a delivery projection can select only the information needed by the consumer.

Nested native calls from callbacks have their own results and retain visible failures. Children inherit the measurement context, but do not implicitly inherit Recall retention or recording. After an analyzer failure, native drainage continues and `Complete` can finalize partial business data.

## Capture once and analyze again

### In-memory evidence

```powershell
$r = quiet -AsObject -Recall -RecallMaxBytes '90KiB' -StdoutMode Bytes -Output {} executable arguments

$analysis = Invoke-QuietRecall -InputObject $r -Data @{ Bytes = 0L } -Output {
    param($event, $runtime)
    $runtime.Data.Bytes += $event.ByteCount
}
```

`-Recall` retains at most **16 MiB** of native bytes by default. `-RecallMaxBytes` accepts positive integral bytes, an integral size with `B`, `KiB`, `MiB` or `GiB`, or `All`, case insensitive. `All` removes the configured memory ceiling; process memory remains the practical limit. Objects and indexes add memory overhead beyond retained payload bytes.

`-RecallPolicy Head|Tail|HeadAndTail` selects retention. `Head` is the default; `HeadAndTail` divides the budget equally and gives an odd extra byte to the head. `All` requires `Head`. Capture options are validated before execution and require explicit `-Recall -AsObject`.

Reaching the memory budget does not stop execution, drainage or the current analyzer. Recall distinguishes received, retained and omitted bytes, missing ranges and source drainage. A fully retained prefix of an interrupted execution is still incomplete source evidence.

### Durable recording and later sessions

```powershell
$r = quiet -AsObject -SaveRecall -RecallName 'build-investigation' executable arguments
$id = $r.Recall.RecallId

# In this or a later session, locate the saved capture.
Get-QuietSavedRecall -RecallName 'build-*'

# Use new callbacks without launching the original executable.
$analysis = quiet -AsObject -RecallId $id -StdoutMode Bytes -Data @{ Bytes = 0L } -Output {
    param($event, $runtime)
    $runtime.Data.Bytes += $event.ByteCount
} -Complete {
    param($runtime)
    @{ TotalBytes = $runtime.Data.Bytes }
}
$json = ConvertTo-QuietJson $analysis -MaxOutputBytes 4096
```

`-SaveRecall -AsObject` writes all received output to a durable streaming journal, independently of the memory retention budget. Combined with `-Recall`, the returned `Recall` exposes the disk view and `Recall.MemoryCapture` exposes the bounded memory view. `RecallId` is the immutable capture identity; `RecallName` is an optional nonunique searchable label.

The default store is `%LOCALAPPDATA%/QuietCli2/recalls` on Windows and the platform local-data directory on Unix. Set `QUIETCLI2_RECALL_ROOT` or supply `-RecallRoot` to select another store. There is no automatic expiry or deletion. Recorded output may contain sensitive business content; retention is an explicit caller choice.

Each capture uses a versioned JSON manifest and a checksummed binary journal. Recording uses bounded buffers and 64-bit offsets; there is no 4 GiB content ceiling. Completed journals replay through streaming cursors. Interrupted recordings recover complete checksum-valid frames and remain marked as incomplete. `DurableBytes` identifies the last confirmed filesystem checkpoint; it is not a guarantee against every hardware or power failure. Save errors remain explicit while native drainage continues.

Capture includes stdout/stderr or the merged PTY terminal stream; stdin is excluded. Sequences preserve the order observed by QuietCli and each stream's byte offsets. They do not establish the exact order of writes across independent pipes. Public snapshots protect retained buffers from mutation.

### Replay and byte references

Each replay creates a fresh analysis runtime and preserves the original result. Supply fresh `Data` and `State` for independent analyses. Replace `Output`, `Complete` and the delivery `Projection`; optionally override `StdoutMode`, `StderrMode`, `RecordDelimiter` and `MaxRecordBytes`. Native controls, probes, automatic handler selection and nested QuietCli execution are unavailable during replay. Stored evidence contains no executable callbacks.

Captures with omitted ranges are rejected by default. `-AllowPartial` permits explicit partial analysis and resets decoding/framing at each gap, preventing separate fragments from becoming a fabricated record. Reanalysis is not counted as a new native source or as additional native-output savings.

```powershell
$view = Get-QuietRecall $r -Stream stderr -Offset 0 -ByteCount 100 -MaxItems 20 -MaxOutputBytes 4096
$reference = New-QuietRecallReference $r -Stream stderr -Offset 0 -ByteCount 12
$context = Get-QuietRecall $r -Reference $reference -Context 1
```

References identify exact retained byte ranges before decoding and fail if requested bytes are missing. Diagnostics can carry these references without duplicating output content. Query limits bound returned bytes and events; selection completeness, capture completeness and original source completeness remain distinct.

### Working directories and ZIP transport

```powershell
# Export retained evidence as an uncompressed working directory.
Export-QuietRecall $r -Path ./reproducer
$imported = Import-QuietRecall ./reproducer -MaxBytes All

# Explicit ZIP64 transport, with zlib compression level 0..9.
$transport = Export-QuietRecall $r -Path ./reproducer.zip -Zip -Compress 6 -PassThru
```

Directory export is the default for repeated replay. `-Zip` selects streaming ZIP64 transport; `-Compress` requires `-Zip`, defaults to 6 and specifies a level rather than a promised ratio. Level 0 stores without compression. Reported input/output sizes and their ratio describe archive bytes, not model tokens or financial savings.

Import validates the supported format, sizes, offsets and SHA-256 integrity with bounded allocations. It loads inert data, never arbitrary serialized types or scripts. `-MaxBytes` bounds accepted native payload; `All` permits large disk-backed evidence without loading it all into RAM. Existing destinations are not overwritten. Integrity checks do not authenticate the author.

See the [Recall contract](docs/recall.md) for checkpoint behavior, corruption handling, live-reader limits and all public APIs.

## Hosting and native transports

`Auto` hosting selects the compatible integrated C# build from the actual PowerShell CLR: `net10.0` on .NET 10 and `net11.0` on .NET 11 or later. Business callbacks, data, decoding and framing stay caller-local. Integrated native reads and lifecycle controls use direct C# calls rather than pipe IPC.

Set `QUIETCLI2_ENGINE_MODE=Process` explicitly for the isolated engine, which requires the pinned .NET 11 RC runtime. `InProcess` explicitly selects direct hosting. Set the mode before the first engine call, or use `Stop-QuietEngine` before changing it. `Get-QuietEngine` reports the actual mode, runtime, process identity and transport counters.

Distributions target Windows x64/ARM64 and Linux glibc/musl x64/ARM64. The facade selects the actual host RID and verifies packaged resources. Pipes preserve separate stdout/stderr; PTY merges output into `TerminalBytesRead`, leaving separate stream counts unknown. Windows uses ConPTY; Linux uses verified native bridges.

Integrated hosting shares PowerShell's failure boundary. Process isolation provides a separate engine boundary. A timeout stops the owned native process, but cannot forcibly interrupt an arbitrary blocked PowerShell callback. Callbacks must cooperate with cancellation. `-DrainTimeoutSeconds` bounds waiting for EOF after native exit; interrupted drainage is explicitly incomplete. Communication failures never trigger automatic command retries and can leave a mutation's effect unknown.

See [hosting and performance](docs/performance-and-hosting.md) and [PowerShell/C# responsibilities](docs/powershell-csharp-boundaries.md).

## Measurements and privacy

The result counts stdin bytes actually written, stdout/stderr bytes actually read, and merged terminal bytes for PTY. `Business`, `Probe`, `Observation` and `Infrastructure` roles separate sources. Aggregates deduplicate sources; context subtotals are not necessarily additive. Probes and reanalysis do not inflate business gains.

With `-AsObject`, delivery size and reduction remain unknown. JSON/YAML bytes are measured only when their representation is produced, including the delivery envelope. The latest delivered text remains local under its `DeliveryId`; successive delivery strings do not accumulate in the result.

Tokenization is off by default. Optional `-Tokenizer o200k_base` or `cl100k_base` counts the exact delivery text already produced. Native model-token counts remain unknown. Byte reduction alone establishes neither context-window use nor financial savings.

SQLite stores closed metadata, counters, relationships and structured error codes. It excludes native output, business objects, delivered text, Recall names and callback code. Explicit Recall storage is separate from telemetry and ordinary result serialization. `QUIETCLI2_DATABASE` selects the telemetry database; `QUIETCLI2_TRACKING=0` disables measurement writes. Storage errors remain distinct from business outcomes.

See [allocation and delivery metrics](docs/allocation-and-delivery-metrics.md), [Core performance qualification](FrenchExDev2.QuietCli.Core.PoSh/PERFORMANCES.md) and the [RTK comparison](QUIET_VS_RTK_MEASURES.md) for definitions, measured scope and limitations.

## Tests and qualification

Tests belong in companion projects, including independent C# assertions and PowerShell scenarios. Focused Recall tooling provides:

- `Compare-QuietRecallAnalysis`: two analyses with independent states, projected differences, diagnostics, cursor counts, durations and allocations. Delivered events alone do not prove business use; ignored events require an explicit declaration.
- `Export-QuietRecallFixture`: an exact capture and a test skeleton that fails until independent business expectations are written.
- `Reduce-QuietRecall`: a bounded event reducer driven by an explicit failure predicate, preserving failure without claiming global minimality.

From the repository root:

```powershell
./scripts/Build-Workspace.ps1
./scripts/Invoke-WorkspaceCi.ps1 -Suite All -SkipBuild

# Focused development campaigns.
./scripts/Invoke-WorkspaceCi.ps1 -Suite Recall -SkipBuild
./scripts/Invoke-WorkspaceCi.ps1 -Suite RecallMutation -SkipBuild
./scripts/Invoke-WorkspaceCi.ps1 -Suite RecallLarge -SkipBuild -TimeoutSeconds 1800
```

Local runs start a background worker and a dedicated visible PowerShell monitor. The launcher prints its reopening command; the monitor closes after saving the terminal result. `-Headless` is reserved for CI. Reports default to the system temporary directory under `QuietCli2/<workspace-id>/<category>/<run-id>`, outside the checkout. `-RunDirectory` overrides the location. CI uses its artifact upload paths. Export evidence requiring durable retention before temporary storage is cleared.

Qualification combines examples, generated properties, malformed-input fuzzing and targeted mutation campaigns. Recall covers retention policies, byte identity, mixed streams, fragmented Unicode, references, durable recovery and import integrity. `RecallLarge` uses actual 4 GiB + 1 MiB native output and checks streaming replay, ZIP64 export/import and bounded working memory; it requires twelve GiB of free disk space. Performance measurements separate ordinary streaming, capture, recording, delivery and reanalysis.

The CI matrix covers stable/.NET 10 and preview/.NET 11 hosting, Windows/Linux and x64/ARM64, with explicit native PTY qualification. Configured targets and successful local campaigns do not qualify unexecuted platforms. Missing, failed or incomplete required phases block release qualification. Reports identify the source revision, runtime, architecture, executed scenarios and remaining gaps.

## Repository and distribution

The [public repository](https://github.com/FrenchExDev2/FrenchExDev2.QuietCli.PoSh) has one root checkout. Open `QuietCli2.code-workspace` in VS Code. Shared scripts own build, package verification and dependency-aware CI; modules retain their declared package boundaries. Builds and tests do not commit, push or publish.

`New-WorkspacePackage.ps1` creates module archives and SHA-256 manifests. `Test-WorkspacePackage.ps1` verifies paths, sizes, hashes and manifests before extraction; `-TestImport` explicitly enables execution of verified package code. File integrity is distinct from author authentication. Gallery publication is manually dispatched and requires qualification of the exact delivered revision.

`New-QuietModule` generates a business module, inert catalogue, handler skeleton and companion test project. Implement probes, version policy, command selection and analysis from the executable's documentation. Its initial companion suite fails until independent business assertions are supplied. Inventory membership alone never establishes semantic support.

For repository commands, dependency rules and publication gates, read [AGENTS.md](AGENTS.md). For API details, use installed command help, the [Core README](FrenchExDev2.QuietCli.Core.PoSh/README.md) and the [Recall documentation](docs/recall.md).
