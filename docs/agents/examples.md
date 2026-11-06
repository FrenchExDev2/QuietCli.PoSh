# Extended QuietCli examples: gains, Recall, evidence transfer

Repository-only guide. It continues the four examples of [AGENTS.md](AGENTS.md) and reuses their
variables (`$repository`, `$commitOutput`, `$commitComplete`, `$recent`). `AgentInstructions.Tests.ps1`
runs the examples of `AGENTS.md`, then these, in order, against a disposable Git repository. Adding,
removing or reordering a `quiet-example` block here is a change to that test's expected set.

## Projection

A projection narrows what is delivered; it does not change the original source or the native result.
`$reviewProjection` was supplied to the original `quiet` call in `AGENTS.md`.

<!-- quiet-example: projection -->
```powershell
# Objective: Keep full commit objects local and expose only identifiers and subjects.
# The release-review call supplied -Projection $reviewProjection before execution.

$reviewJson = FrenchExDev2.QuietCli.Core.PoSh\ConvertTo-QuietJson $recent -MaxItems 5 -MaxOutputBytes 4096
```

`-MaxItems` bounds each presented container; `-MaxOutputBytes` bounds the final UTF-8 envelope.
Neither reduces the underlying object or refreshes the repository state. Do not serialize the
envelope with a general-purpose serializer. `quiet -AsJson` and `quiet -AsYaml` execute the native
command anew; convert the retained object instead. QuietCli JSON is already compact:
`ConvertTo-QuietJson` and `Out-QuietResult` take no `-Compress`, while `Get-QuietCliGain -AsJson` does.

## Measure the gain

<!-- quiet-example: gain -->
```powershell
# Objective: Compare measured business-source volume with actual deliveries for this context.
$gain = Get-QuietCliGain -C release-review
$gainObject = Get-QuietCliGain -C release-review -AsObject
$gainYaml = Get-QuietCliGain -C release-review -AsYaml
$gainJson = Get-QuietCliGain -C release-review -AsJson
$gainCompactJson = Get-QuietCliGain -C release-review -AsJson -Compress
```

Object output is the default; JSON is indented unless `-Compress` is given, and `-Compress` requires
`-AsJson`. `-Days`, `-From`, `-To`, `-SessionId`, `-GroupBy` and `-MaxEvents` select the scope.
Native source bytes are deduplicated; deliveries have their own measured bytes. `ReductionBytes`
stays unknown when a measurement or the source/analysis completeness is missing. Native tokens are
unknown. Byte savings are neither a token count nor an API bill. Repeated identical representations
reuse a delivery identity (`AlreadyDelivered`). Reusing `$recent` avoids Git work but keeps an old
observation: observe again when freshness matters.

## Capture once in memory, then change the analysis with Recall

<!-- quiet-example: capture -->
```powershell
# Objective: Keep bounded native evidence while producing the first release-review object.
$capture = quiet -AsObject -Recall -RecallMaxBytes '1MiB' -RecallPolicy Head -C release-review -WorkingDirectory $repository -RecordDelimiter "`n" -Data @{ Commits = [Collections.Generic.List[object]]::new() } -Output $commitOutput -Complete $commitComplete -FilePath git -ArgumentList @('log', '--max-count=50', '--format=%H%x09%aI%x09%s', 'HEAD')
if ($capture.Outcome -ne 'Success' -or !$capture.Completeness.Source -or !$capture.Completeness.Analysis) { throw 'ReleaseCaptureIncomplete' }
```

The budget counts native bytes; indexes and objects use more memory. `Head`, `Tail` and
`HeadAndTail` choose the retained ranges; `All` removes the ceiling and requires `Head`. Reaching a
limit does not stop execution or analysis.

<!-- quiet-example: replay -->
```powershell
# Objective: Identify release-review candidates from retained evidence without rerunning Git.
$review = Invoke-QuietRecall -InputObject $capture -RecordDelimiter "`n" -Data @{ Commits = [Collections.Generic.List[object]]::new() } -Output $commitOutput -Complete {
    param($runtime)
    $candidates = @($runtime.Data.Commits | Where-Object Subject -Match 'BREAKING CHANGE|^[^:]+!:')
    [pscustomobject]@{ ReviewedCommits = $runtime.Data.Commits.Count; RequiresReview = ($candidates.Count -gt 0); Candidates = $candidates }
}
if ($review.Outcome -ne 'Success' -or !$review.Completeness.Source -or !$review.Completeness.Analysis) { throw 'ReplayIncomplete' }
$reviewYaml = FrenchExDev2.QuietCli.Core.PoSh\Out-QuietResult $review -AsYaml -MaxItems 5 -MaxOutputBytes 4096
```

Recall replays bytes through new callbacks with fresh state; it runs no stored code and does not
rerun the command. The subject rule selects candidates; it does not establish that a change breaks
anything. Missing retained ranges require `-AllowPartial`, and partial analysis must not be presented
as complete. Decoders reset at gaps, so unrelated fragments are never joined into fabricated records.
For byte-level inspection use `Get-QuietRecall` with explicit stream, offset, byte, item and output
budgets, and `New-QuietRecallReference` for stable evidence ranges.

## Save evidence for another process or session

`-SaveRecall` writes the journal as output arrives instead of holding it in memory.

<!-- quiet-example: durable -->
```powershell
# Objective: Record release-review evidence in an explicitly selected persistent workspace directory.
$recallRoot = Join-Path $repository '.quietcli-evidence'
$recorded = quiet -AsObject -SaveRecall -RecallRoot $recallRoot -RecallName release-review -C release-review -WorkingDirectory $repository -RecordDelimiter "`n" -Data @{ Commits = [Collections.Generic.List[object]]::new() } -Output $commitOutput -Complete $commitComplete -FilePath git -ArgumentList @('log', '--max-count=50', '--format=%H%x09%aI%x09%s', 'HEAD')
$recallId = $recorded.Recall.RecallId
$savedEvidence = Get-QuietSavedRecall -RecallRoot $recallRoot -RecallId $recallId
```

The directory is an evidence artifact; exclude it from source publication as appropriate. A later
session needs Core, the root, the identity and newly defined callbacks. It needs neither the
original variable nor the executable:

<!-- quiet-example: saved-replay -->
```powershell
# Objective: Rebuild the commit business object from a saved journal without native execution.
$restored = quiet -AsObject -RecallId $recallId -RecallRoot $recallRoot -RecordDelimiter "`n" -Data @{ Commits = [Collections.Generic.List[object]]::new() } -Output $commitOutput -Complete $commitComplete
$restoredJson = FrenchExDev2.QuietCli.Core.PoSh\ConvertTo-QuietJson $restored -MaxItems 5 -MaxOutputBytes 4096
```

Do not append native arguments to a `-RecallId` call. A name is a searchable label, not an identity;
`Get-QuietSavedRecall -RecallName 'release-*'` searches the configured `recall.root`. `Save-QuietRecall $capture`
saves a finished capture but only the bytes still retained. A finalized journal may still describe a failed or
incomplete native source: check native status, completeness and recovery metadata before trusting rebuilt data.
SQLite holds measurement metadata only, never the journal or business objects.

## Export evidence and choose archive compression

Working captures stay uncompressed. Export a directory by default, or ask for a ZIP transport.

<!-- quiet-example: export -->
```powershell
# Objective: Export evidence for transfer and verify import into a separate owned catalog.
$transferRoot = Join-Path ([IO.Path]::GetTempPath()) ('QuietCli-transfer-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($transferRoot)
$archive = Join-Path $transferRoot 'release-review.zip'
$transport = Export-QuietRecall -InputObject $recorded -Path $archive -Zip -Compress 6 -PassThru
$importRoot = Join-Path $transferRoot 'imported'
$imported = Import-QuietRecall -Path $archive -RecallRoot $importRoot -MaxBytes All
```

`-Compress` here is an integer level 0 to 9, requires `-Zip` and defaults to 6; 0 stores without
compression and 9 asks for the highest level, not a guaranteed reduction. Small or incompressible
input can grow. Without `-Zip`, `-Compress` is rejected. Existing destinations are never overwritten.
Imports verify integrity and reject malformed records and unsafe archive paths; integrity is not
author authentication. Recall retains native content, so export only what may be shared.
