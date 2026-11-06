# Recall: durable native evidence and offline analyzer development

Recall separates memory retention from durable recording. All content retention is explicit; ordinary streaming still creates neither a collector nor a journal. SQLite telemetry never stores native content, recall names or callback code.

## Capture once, resume later

```powershell
$r = quiet -AsObject -SaveRecall -RecallName 'build-investigation' -StdoutMode Bytes executable arguments
$id = $r.Recall.RecallId

# This can run in another PowerShell session, after reboot, without an executable argument.
$analysis = quiet -AsObject -RecallId $id -Data @{ Count = 0L } -Output {
    param($event, $runtime)
    $runtime.Data.Count += $event.ByteCount
} -Complete {
    param($runtime)
    @{ Bytes = $runtime.Data.Count }
} -Projection {
    param($data, $budget)
    @{ TotalBytes = $data.Bytes }
}
$delivery = Out-QuietResult $analysis -MaxOutputBytes 4096
```

`-SaveRecall` records during native execution, before decoding and user callbacks. It requires explicit `-AsObject`. A command without a registered handler can be recorded directly with `-SaveRecall`; it does not need a fabricated parser. Native failures and parser failures still preserve the available evidence.

`RecallId` aliases the existing immutable `CaptureId`. `RecallName` is an optional nonunique label (up to 256 UTF-16 characters), never a directory name or executable selector. Find saved evidence with:

```powershell
Get-QuietSavedRecall
Get-QuietSavedRecall -RecallName 'build-*'
Get-QuietSavedRecall -RecallId $id
```

The default root is durable user data: `%LOCALAPPDATA%/QuietCli2/recalls` on Windows and the platform local-data directory on Unix. `QUIETCLI2_RECALL_ROOT` overrides it; `-RecallRoot` explicitly selects a root for capture, lookup, import or replay. It is not a temporary report directory. There is no automatic expiry, deletion, installation or publication.

Each record uses a directory named by its canonical GUID:

```text
<RecallId>/
    manifest.json
    events.bin
    writer.lock
```

The closed version-2 JSON manifest contains only identity, label, timestamps, inert decoding settings, native status, provenance and counters. The binary journal contains sequence, stream, stream offset, observed combined offset, payload length, payload and SHA-256 over both record metadata and payload. Native reads are framed in bounded blocks; export splits unusually large memory events into at most 1 MiB frames without changing their original sequence. All offsets and byte counters are 64-bit. There is no 20,000-event or 4 GiB content ceiling.

Opening and replaying a completed journal uses bounded-memory cursors, not a whole-file load. Every replay validates record checksums, ordering and final counters as it reads. Corruption produces an explicit failed analysis with incomplete source evidence. Metadata listing never scans business output. Collection `Count`/indexed access retain their Int32 interface for compatibility; use `EventCount` and streaming enumeration for very large record counts. Indexed access on disk scans and is intended for small inspections.

## Memory and disk are independent

```powershell
$r = quiet -AsObject -Recall -RecallMaxBytes '90KiB' -Output {} executable arguments
$r = quiet -AsObject -Recall -RecallMaxBytes 92160 -Output {} executable arguments
$r = quiet -AsObject -Recall -RecallMaxBytes All -Output {} executable arguments
$r = quiet -AsObject -Recall -RecallMaxBytes 16MiB -RecallPolicy HeadAndTail -Output {} executable arguments
$r = quiet -AsObject -SaveRecall -Recall -RecallMaxBytes 90KiB -Output {} executable arguments
```

`-Recall` defaults to 16 MiB of native bytes in memory. Sizes are positive integral bytes or integral `B`, `KiB`, `MiB`, `GiB` values, case insensitive. `All` imposes no configured memory ceiling and requires `Head`; process memory remains the practical limit. Metadata and object overhead are additional.

`Head` retains the prefix; `Tail` retains the suffix. `HeadAndTail` splits the budget equally, giving an odd extra byte to the head. Reaching the memory limit does not stop the process, analysis or drainage. Without `-SaveRecall`, a crash loses the memory capture.

`-SaveRecall` records all received output on disk without requiring `-RecallMaxBytes All`. When combined with `-Recall`, the returned `Recall` is the complete disk view and `Recall.MemoryCapture` is the separately bounded memory view, sharing the same identity. Save errors remain explicit while the native command continues draining; the result keeps the identity and available prefix instead of retrying the command.

Capture is stdout/stderr only; PTY retains the merged terminal stream. Stdin is excluded. Sequence is the order observed by QuietCli, not a reconstruction of exact writes across independent pipes. Children do not inherit recording or memory-retention options.

## Crash recovery and checkpoints

Each successful append is flushed out of the managed file buffer before the user callback. Synchronized filesystem checkpoints occur after another 4 MiB, on the next append after two seconds, and at normal completion. They flush file data and atomically replace the manifest. `DurableBytes` describes the last confirmed checkpoint; it is not a promise about hardware write caches or a filesystem surviving every power failure.

An interrupted recorder leaves a manifest in `Recording` state. An exclusive lock handle distinguishes a live writer from an abandoned lock file. Lookup reports an abandoned recording as `Interrupted`. Opening it scans with bounded memory, recovers only complete checksum-valid records and excludes an incomplete final frame. Complete corrupt frames are rejected, not silently dropped. Source completeness remains false and `Recovered` identifies the recovered view. While a writer is active, readers use its confirmed checkpoint prefix.

`State=Completed` means that the recording operation finalized; a timeout or cancelled native source can still have `SourceComplete=false`. Retained, omitted, durable and source-complete counts are separate. Recovered bytes beyond the last checkpoint are not retroactively claimed as synchronized durable bytes.

## Change the analyzer, not the native execution

```powershell
$a = Invoke-QuietRecall -RecallId $id -Output $parserV2 -Complete $completeV2
$b = Invoke-QuietRecall -InputObject $r -Output $parserV3 -Complete $completeV3
```

Each analysis receives new runtime state. Supply fresh `Data` and `State` objects for independent runs. `Output`, `Complete`, delivery `Projection`, `StdoutMode`, `StderrMode`, `RecordDelimiter` and `MaxRecordBytes` can change. A null delimiter override disables record framing. Projection remains a delivery projection, matching ordinary `quiet -AsObject` semantics.

`quiet -RecallId` is routed before executable resolution, probes or native lifecycle control. It rejects executable arguments and native input/interaction options. No command line or executable callback is saved in the journal. Loading evidence never executes persisted code. Runtime native controls and nested QuietCli execution are unavailable during replay; arbitrary caller-supplied scriptblocks remain trusted code rather than sandboxed code.

Missing retained ranges require `-AllowPartial`. At each gap, decoders and framers reset; separate fragments cannot become a fabricated record. A suffix inside UTF-8 can still fail strict decoding; use bytes to inspect it. `runtime.CurrentRecallEvent`, `CurrentRecallGap` and `Recall` expose the cursor context. A framed record spanning slices needs analyzer-maintained byte provenance. `runtime.MarkIgnored()` explicitly marks a current sequence; cursor delivery counts alone do not prove business use.

## Evidence, export and optional ZIP64

```powershell
$view = Get-QuietRecall $r -Stream stderr -Offset 0 -ByteCount 100 -MaxItems 20 -MaxOutputBytes 4096
$ref = New-QuietRecallReference $r -Stream stderr -Offset 0 -ByteCount 12
$evidence = Get-QuietRecall $r -Reference $ref -Context 1

# Save the currently retained memory evidence after execution; omitted bytes cannot be recovered.
$saved = Save-QuietRecall $r -RecallName 'reproducer'

# Default export is a working directory, not an archive.
Export-QuietRecall $r -Path ./reproducer-directory
$directoryCapture = Import-QuietRecall ./reproducer-directory -MaxBytes All

# Optional transport; zlib levels 0..9, default 6. Zero stores without compression.
$transport = Export-QuietRecall $r -Path ./reproducer.zip -Zip -Compress 9 -PassThru
$imported = Import-QuietRecall ./reproducer.zip -MaxBytes All -RecallRoot ./imported-recalls

# Live recording can also produce an adjacent transport after finalization.
$r = quiet -AsObject -SaveRecall -RecallName 'build' -Zip -Compress 6 executable arguments
$r.Recall.Transport
```

References contain identity and byte ranges without duplicating content. References fail if any requested byte is missing. Query budgets bound returned native bytes and events, with additional object overhead. Selection completeness, capture completeness and original source completeness remain distinct. Ordinary result deliveries exclude raw Recall content and retain their final encoded output budgets.

`-Compress` is a compression level, not a promised ratio, and requires `-Zip`. `Transport.InputBytes` includes manifest and binary framing; `OutputBytes` is the actual archive size. `Ratio` is archive/input bytes and can exceed one for small or incompressible evidence. No model-token or financial savings follow from it.

ZIP transport contains exactly `manifest.json` and `events.bin`, with streaming DEFLATE and ZIP64 sizes/offsets. Compression uses the platform zlib through .NET; only the fixed two-entry ZIP64 framing is encoded locally. The format follows the [ZIP specification](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT). Working captures stay uncompressed for repeated replay. ZIP export of an existing completed disk capture streams directly from it; a memory-only export uses an explicitly requested temporary staging directory.

Import bounds central-directory and manifest allocations before exposing records, rejects extra entries, traversal and links, and expands payload in bounded blocks into a new durable directory. `-MaxBytes` optionally bounds native payload; `All` permits large disk-backed data without unbounded RAM. ZIP import verifies all journal frames before publishing its manifest; opening a working directory verifies metadata first and validates frames during replay. Existing destinations are never overwritten. Integrity checks do not authenticate authors. Failed unpublished import directories are not presented as catalog entries.

## Companion qualification tools

`Compare-QuietRecallAnalysis` runs two analyses with independent state factories and returns projected differences, diagnostics, cursor counts, local durations and allocation measurements. Explicit JSON projections are compared structurally: object property order is ignored and array order remains significant. Remove intentionally variable fields in a projection.

`Export-QuietRecallFixture` exports an exact working capture and a test skeleton that fails until independent business expectations are supplied. `Reduce-QuietRecall` preserves an explicit Boolean failure predicate while removing events within time/attempt budgets. It does not claim a globally minimal result. Large-capture reduction is intended only after selecting a bounded reproducer. Transformed artifacts use a new identity, parent identity, label and fresh checksums.

```powershell
./scripts/Build-Workspace.ps1
./scripts/Invoke-WorkspaceCi.ps1 -Suite Recall -SkipBuild
./scripts/Invoke-WorkspaceCi.ps1 -Suite RecallMutation -SkipBuild
./scripts/Invoke-WorkspaceCi.ps1 -Suite RecallLarge -SkipBuild -TimeoutSeconds 1800
```

The existing visible monitor and external test-report rules apply. Properties cover memory policies, generated mixed-stream durable journals, fragmented Unicode and PowerShell bindings; fuzzing covers malformed manifests, journal frames and ZIPs. Targeted mutations cover meaningful C#/PowerShell behavior changes, not exhaustive mutation coverage. Source-free packages verify their helper binaries before loading them.

`Invoke-QuietRecallRtkComparison` accepts explicit inert command-case records and otherwise reuses `New-QuietControlledStatusFixtures` for all eight Git states. It also exercises the existing C# producer's large, mixed, Unicode and failing outputs as documented RTK passthrough controls. Fixture setup and its environment changes run in an isolated worker. The report distinguishes filter scenarios, passthrough controls, native outcomes, expected facts, observed bytes, latency and allocation gaps. It records the RTK version/hash; missing RTK is `Unavailable`, never an implicit successful comparison. RTK executes through the same QuietCli wrapper, so standalone overhead is not isolated. No general ranking, exact native token counts or financial savings are claimed.

`RecallLarge` uses actual 4 GiB + 1 MiB native output and requires twelve GiB free disk space. It verifies recording, identity-based replay without native requests, ZIP64 transport, verified import and a worker peak working set below one GiB. This is a separate bounded resource campaign, not a sparse-file simulation. Metadata reports and captured fixtures remain under its owned run directory.

Local development evidence does not qualify unexecuted platform/release matrices. Persisted captures and temporary test reports are separate resources with different lifetimes.
