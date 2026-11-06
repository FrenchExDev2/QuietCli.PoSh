# Capture once and analyze again (Recall)

[Back to the QuietCli overview](README.md)

Opt-in capture of native evidence for inspection, offline analyzer development and work that continues in another session. Full contract: [Recall documentation](docs/recall.md). Related: [Streaming and callbacks](README-streaming.md).

## In-memory evidence

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

## Durable recording and later sessions

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

The default store is `%LOCALAPPDATA%/QuietCli2/recalls` on Windows and the platform local-data directory on Unix. Set YAML `recall.root` or supply `-RecallRoot` to select another store. There is no automatic expiry or deletion. Recorded output may contain sensitive business content; retention is an explicit caller choice.

Each capture uses a versioned JSON manifest and a checksummed binary journal. Recording uses bounded buffers and 64-bit offsets; there is no 4 GiB content ceiling. Completed journals replay through streaming cursors. Interrupted recordings recover complete checksum-valid frames and remain marked as incomplete. `DurableBytes` identifies the last confirmed filesystem checkpoint; it is not a guarantee against every hardware or power failure. Save errors remain explicit while native drainage continues.

Capture includes stdout/stderr or the merged PTY terminal stream; stdin is excluded. Sequences preserve the order observed by QuietCli and each stream's byte offsets. They do not establish the exact order of writes across independent pipes. Public snapshots protect retained buffers from mutation.

## Replay and byte references

Each replay creates a fresh analysis runtime and preserves the original result. Supply fresh `Data` and `State` for independent analyses. Replace `Output`, `Complete` and the delivery `Projection`; optionally override `StdoutMode`, `StderrMode`, `RecordDelimiter` and `MaxRecordBytes`. Native controls, probes, automatic handler selection and nested QuietCli execution are unavailable during replay. Stored evidence contains no executable callbacks.

Captures with omitted ranges are rejected by default. `-AllowPartial` permits explicit partial analysis and resets decoding/framing at each gap, preventing separate fragments from becoming a fabricated record. Reanalysis is not counted as a new native source or as additional native-output savings.

```powershell
$view = Get-QuietRecall $r -Stream stderr -Offset 0 -ByteCount 100 -MaxItems 20 -MaxOutputBytes 4096
$reference = New-QuietRecallReference $r -Stream stderr -Offset 0 -ByteCount 12
$context = Get-QuietRecall $r -Reference $reference -Context 1
```

References identify exact retained byte ranges before decoding and fail if requested bytes are missing. Diagnostics can carry these references without duplicating output content. Query limits bound returned bytes and events; selection completeness, capture completeness and original source completeness remain distinct.

## Working directories and ZIP transport

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
