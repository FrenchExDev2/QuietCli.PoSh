# QuietCli Core

**Run native tools from PowerShell and turn their output into structured results, without collecting a terminal transcript first.**
Start an executable with an argument vector, observe stdout and stderr through callbacks, and keep the business state your script needs.
Inspect the result locally, deliver a bounded JSON/YAML view, or retain evidence explicitly and analyze it again without rerunning the command.
Useful for developer scripts, inventories, build automation, diagnostics and agent tooling; no AI service or Git provider is required.

## Why QuietCli Core?

| Approach | A good fit when… | What you still own |
| --- | --- | --- |
| Raw native output | A person will inspect it, or the tool already provides suitable structured output. | Parsing, error handling and any retention policy needed by downstream scripts. |
| `& tool args \| Out-String` | You want a convenient formatted string and its size is acceptable. | This form materializes text; it does not supply an analysis/completeness contract. PowerShell can also stream without `Out-String`. |
| `Start-Process` | Launching, process control or file redirection is the main requirement. | Streaming analysis, business state and result/delivery contracts. |
| RTK | Existing command filters meet your need for compact output. | Check supported forms and semantics; RTK and Core solve overlapping, not identical, problems. |
| QuietCli Core | You want caller-local analysis, execution metadata, explicit completeness and bounded delivery together. | The meaning and correctness of your callbacks or provider, plus their tests. |

Core does not make a small native JSON response better automatically. It adds execution and analysis controls when your script needs them.
See the [RTK comparison and measurements](QUIET_VS_RTK_MEASURES.md); byte reduction is not proof of token or financial savings.

## Requirements and installation

- **PowerShell Core 7.6+**, as declared by the module manifest; Windows PowerShell 5.1 is not supported.
- Development identity: **0.2.0-preview** (`ModuleVersion = 0.2.0`, prerelease label `preview`).
- Distribution targets: Windows and Linux glibc/musl, each x64 and ARM64. A target is not a qualification claim.
- Default `Auto` hosting selects integrated `net10.0` on a .NET 10 PowerShell CLR, or `net11.0` on CLR 11+.
- Optional `Process` hosting requires **.NET runtime 11.0.0-rc.3.26522.148**. A built module does not need an SDK.
- Source builds require **.NET SDK 11.0.100-rc.3.26522.148**, pinned with roll-forward disabled in `global.json`.
- Install the native executables you call separately. The quickstart assumes `pwsh` is available on `PATH`.

### From this checkout

From the repository root, build missing or stale binaries using the actual workspace entry point:

```powershell
./scripts/Build-Workspace.ps1
```

This workspace script also builds test and Git companion projects; using Core does not require importing those modules.
Then start a fresh PowerShell 7.6+ process before importing rebuilt assemblies. Import itself does not compile C#.
<!-- TODO Jean: Provide a documented Core-only build entry point; the current workspace build includes companion projects. -->

### From PowerShell Gallery, when this preview is published

```powershell
Install-PSResource -Name FrenchExDev2.QuietCli.Core.PoSh -Version '0.2.0-preview' -Prerelease -Repository PSGallery -Scope CurrentUser
Import-Module FrenchExDev2.QuietCli.Core.PoSh
```

The historical stable package is not evidence that this development preview is available. See [package installation](docs/PSGallery.md).
<!-- TODO Jean: Verify publication of 0.2.0-preview before presenting the Gallery command as an available installation path. -->

## Quickstart: Core alone, one native command

From a built checkout, these nine lines count stdout bytes from `pwsh -v`; no business provider is needed.
For a Gallery installation, replace the first line with `Import-Module FrenchExDev2.QuietCli.Core.PoSh`.

```powershell
Import-Module ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1
$countStdout = { param($event, $runtime) if ($event.Stream -eq 'stdout') { $runtime.Data.Bytes += $event.ByteCount } }
$r = quiet -AsObject -C version -StdoutMode Bytes -Data @{ Bytes = 0L } `
    -Output $countStdout -Complete { param($runtime) [pscustomobject]@{ Bytes = $runtime.Data.Bytes } } pwsh -v
$r.Outcome
$r.Execution.Native.ExitCode
$r.Completeness
$r.Data
ConvertTo-QuietYaml $r -MaxOutputBytes 4096
```

`quiet` is the alias of `Invoke-QuietCli`. **QuietCli options precede the executable**; arguments after it belong to the native tool.
For an explicit argument vector, use `-FilePath pwsh -ArgumentList @('-v')` instead of the positional `pwsh -v` suffix.
The default Pipe transport starts the executable without an intermediary shell. It does not interpret pipes or redirection in native arguments.
If you deliberately run a shell or interpreter, that executable's parsing rules still apply. Windows PTY uses ConPTY command-line construction.

### Illustrative example — YAML excerpt, not captured output

The byte count varies with the invoked version and platform. `Bytes` is business data defined by the callback above.
Only a subset of the real delivery fields is shown; identities and measurements have been omitted, not renamed.

```yaml
SchemaVersion: 1
Outcome: Success
Data:
  Bytes: 17
Completeness:
  Source: true
  Analysis: true
Error: []
Truncation:
  Applied: false
  Omitted: 0
  OmittedExact: true
```

The local `-AsObject` envelope additionally exposes `Execution`, including `Execution.Native.ExitCode`; the current JSON/YAML delivery does not include `Execution`.
Use the local result when exit status or detailed execution metadata is needed. Inspect completeness and errors, not only a zero exit code:

```powershell
if ($r.Outcome -ne 'Success' -or !$r.Completeness.Source -or !$r.Completeness.Analysis -or $r.Error.Count) {
    throw 'IncompleteResult'
}
```

## The model: stream, state, result, delivery

- **Events are not inherently lines.** `-Output` receives `(event, runtime)` with `Stream` and either byte or decoded-text information.
  Use `-StdoutMode Bytes` / `-StderrMode Bytes` for bytes; set `-RecordDelimiter` to a newline (`` "`n" ``) explicitly for newline-framed text.
  Without a delimiter, Text callbacks receive decoded chunks. Encoding/framing failures are reported rather than silently accepted.
- **State stays local.** Put business values in `$runtime.Data`; `-State` supplies auxiliary state. Your callbacks decide what to retain.
  `-Output` must emit no incidental pipeline values; discard method return values with `[void]` when appropriate.
- **Completion is optional.** `-Complete { param($runtime) ... }` returns zero or one business value.
  Zero values preserve existing Data. To return an array as one value, use the unary comma. Completion can finalize partial analysis.
- **The envelope separates concerns.** `Outcome` reports the invocation outcome; `Data` is your business value; `Error` contains structured errors.
  `Execution` describes native execution and effects. `Completeness.Source` and `.Analysis` distinguish drainage from successful analysis.
  These fields do not certify the semantic correctness of your parser or make a native mutation transactional.
- **Execution and delivery have different budgets.** Native queues/read blocks and unfinished records are bounded; `-MaxRecordBytes` bounds framing.
  `-MaxItems` and `-MaxOutputBytes` bound delivered views, not arbitrary objects retained by your callback or memory used by the native process.
  Current defaults include 1 MiB unfinished records, 20 items per container and 4096 UTF-8 delivery bytes; YAML can override them.

`-AsObject` returns the local envelope without serializing Data. `-AsJson` and `-AsYaml` produce bounded deliveries directly.
`ConvertTo-QuietJson`, `ConvertTo-QuietYaml` and `Out-QuietResult` deliver an existing result without rerunning the executable.
Delivery `Truncation` is distinct from source/analysis completeness; the byte budget can replace Data with a smaller truncation envelope.

## Short recipes

Examples below assume Core is imported; Recall examples reuse `$countStdout` from the quickstart.

### Timeout and cancellation

```powershell
$cancel = [Threading.CancellationTokenSource]::new()
$cancel.CancelAfter([TimeSpan]::FromSeconds(5))
try {
    quiet -AsObject -TimeoutSeconds 30 -DrainTimeoutSeconds 2 -CancellationToken $cancel.Token -Output {} pwsh -v
} finally { $cancel.Dispose() }
```

The empty callback intentionally discards business output. `-CancellationFile` is also available: existence of the supplied path requests cancellation.
Timeout/cancellation controls native execution, but cannot forcibly interrupt an arbitrary blocked PowerShell callback; callbacks must cooperate.
Drain timeout bounds waiting for EOF after native exit. Check the returned outcome and completeness, including after interruptions.

### PTY / ConPTY

```powershell
quiet -AsObject -Transport Pty -TerminalSize @(120, 40) -StdoutMode Bytes -Output {} pwsh -v
```

PTY uses ConPTY on Windows and a native bridge on Linux. Output arrives as merged `terminal` events, not independent stdout/stderr.
It may contain ANSI control sequences and terminal-dependent formatting. Choose Pipe when separate streams or machine-readable output matter.
PTY is a transport, not a promise that every interactive application is supported. See [hosting and transports](README-hosting.md).

### Recall: capture explicitly, analyze without execution

```powershell
$recorded = quiet -AsObject -Recall -RecallMaxBytes '64KiB' -StdoutMode Bytes -Data @{ Bytes = 0L } -Output $countStdout pwsh -v
$reanalysis = Invoke-QuietRecall -InputObject $recorded -StdoutMode Bytes -Data @{ Bytes = 0L } -Output $countStdout
```

In-memory Recall defaults to 16 MiB and supports `-RecallPolicy Head`, `Tail` or `HeadAndTail`.
A retention limit does not stop native drainage or the live analyzer. Replay rejects missing ranges unless `-AllowPartial` is explicit.
Avoid `-RecallMaxBytes All` when you need a memory ceiling; payload limits do not include all object/index overhead.

For durable evidence, `-SaveRecall -AsObject` records received bytes even without a business parser:

```powershell
$saved = quiet -AsObject -SaveRecall -RecallName version-check pwsh -v
$reanalysis = Invoke-QuietRecall -RecallId $saved.Recall.RecallId -StdoutMode Bytes -Data @{ Bytes = 0L } -Output $countStdout
```

The identifier can be reopened in a later session using the same Recall store. Replay runs new callbacks, not the original executable.
Durable recording is separate from bounded memory retention: it has no automatic expiry or disk quota. Plan cleanup and storage access.
Recorded stdout/stderr or terminal bytes may contain secrets; stdin is excluded. Recall is opt-in, not a sanitized audit log.
See [Recall](README-recall.md) for stores, queries, exports, integrity checks and partial evidence.

### Measures and YAML configuration

```powershell
Get-QuietCliGain -C version
Get-QuietCliConfiguration
Test-QuietCliConfiguration
```

Measurements separate native bytes, execution/analysis overhead and actual deliveries. `-AsObject` alone leaves delivery sizes unknown.
JSON/YAML token counts describe a selected encoding, not model-independent savings. Inspect `Measurement.StorageError` for persistence failures.
Telemetry writes are enabled by default and use SQLite metadata/counters; raw output retention belongs to explicit Recall, not measurement storage.

Configuration defaults to `~/.quietcli/config.yaml`, loaded lazily and kept as a session snapshot. An absent file uses defaults.
Explicit parameters override YAML, then built-in defaults. `QUIETCLI_CONFIG_DIRECTORY` selects the containing directory.
For example, this is a partial configuration file, not an extra argument to `quiet`:

```yaml
schemaVersion: 1
execution:
  timeoutSeconds: 60
delivery:
  maxOutputBytes: 4096
  maxItems: 20
telemetry:
  enabled: false
```

`New-QuietCliConfiguration` explicitly creates a template. After editing, validate with `Test-QuietCliConfiguration`, then apply with `Import-QuietCliConfiguration`.
Changing hosting/database while an engine is active requires an explicit `Stop-QuietEngine` before reload. See [configuration](README-configuration.md).

## Reuse a handler or build a module

Reuse callback scriptblocks directly, or package a documented provider with `Register-QuietHandler`.
Without callbacks or a compatible registered handler, a normal native call is rejected before business execution; direct durable recording is an explicit exception.
Core does not infer a parser for an arbitrary executable. Read that tool's documented machine-readable format before designing a handler.

```powershell
New-QuietModule -Name Example.Tool.PoSh -Binary tool -OutputPath ./modules
```

This command writes a module and companion test skeleton; existing destinations are rejected. Configure `Probe`, `TestVersion`, `Match` and `Execute`.
The generated handler starts unimplemented, and the initial tests fail until independent business assertions are written; generation is not qualification.
The [Git companion](FrenchExDev2.QuietCli.Git.PoSh/README.md) is an optional, in-development example, not a Core dependency at runtime.
See [companion modules](README-modules.md) and [qualification](README-qualification.md).

## Use with AI agents

An agent is one consumer of the same Core contracts, not a prerequisite. Reuse a persistent PowerShell session to amortize imports and engine startup.
Keep result objects local and deliver only the required view. Session persistence belongs to the agent/tool integration, not to launching a fresh `pwsh` for each command.
Start with [agent documentation](docs/agents/README.md) and [persistent-shell guidance](docs/agents/persistent-shell.md).
Any future rewrite hook should remain a lightweight shim; this proposal does not claim an installed transparent hook.

## Preview scope and a short Core roadmap

This is a proposal for the current **0.2.0-preview** development API, including uncommitted work; earlier packages may differ.
Core does not guarantee parser correctness, lower output size, a hard cap on callback/native-process memory, secret redaction, or support for every terminal application.
Integrated hosting shares PowerShell's failure boundary. Optional Process hosting separates the engine, not untrusted business callbacks from your session.
No blanket cross-platform qualification or compatibility guarantee follows from a configured target or a passing development test.
<!-- TODO Jean: Execute and record these Core-only examples against an identified revision and shipped package before publishing this README. -->
<!-- TODO Jean: Link the exact-revision qualification report and state the qualified OS/architecture/runtime subset. -->

Proposed milestones, not completed release claims:

| Milestone | Exit criterion |
| --- | --- |
| Stabilization | Callback/result/delivery contracts reviewed; security regressions and interruption/Recall cases checked; CI covers develop and the intended Core scope. |
| First experience | Clean-install and source-build instructions reproduced; quickstart and displayed outputs verified; errors and unsupported cases explained. |
| Qualified preview | An identified package/revision passes the declared runtime/platform matrix and required qualification campaigns; remaining limits and release blockers are published. |

## Documentation

[Streaming and results](README-streaming.md) · [Hosting / PTY](README-hosting.md) · [Recall](README-recall.md) · [Measurements](README-measurements.md)
[Configuration](README-configuration.md) · [Modules](README-modules.md) · [Development](README-development.md) · [Qualification](README-qualification.md)
<!-- TODO Jean: If adopted as README.md, retarget inbound links to existing section anchors or preserve compatible anchors. -->
