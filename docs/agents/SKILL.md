---
name: quiet-cli
description: Use QuietCli Core to turn native output into business objects, deliver bounded JSON or YAML, measure gains and reanalyze Recall evidence.
---
# Use QuietCli, from a first object to durable evidence

Read [AGENTS.md](AGENTS.md). The examples use Core only and Git's documented native formats.
They operate on an existing repository with at least one commit. Read installed Git help or
its official format documentation before adapting these parsers to another command or format.

## 1. Initialize the project and keep objects in PowerShell

```powershell
# Objective: Load Core and identify the existing repository to inspect.
Import-Module FrenchExDev2.QuietCli.Core.PoSh -ErrorAction Stop
$repository = (Get-Location).Path
$installation = Add-QuietAgentInstruction -Path $repository -Agents
```

Instruction installation copies the production documents into `.skills` and updates only the
managed reference block in the project's `AGENTS.md`. `-WhatIf` previews changes;
`-DocumentDirectory` selects another copy directory. This command returns file metadata and
does not execute a native process, edit a profile or register a native skill.

Use **`-AsObject` by default in agent workflows**, assign the result and decide locally what
to expose. The examples always make this choice explicit. This is a usage convention:
a root `quiet` call without a format flag currently returns JSON; nested calls default to
objects. `Get-QuietCliGain` and `Invoke-QuietRecall` return objects by default.
`-Recall` and `-SaveRecall` require explicit `-AsObject` even when the intent seems obvious.

An object result is an envelope: `Data` contains the business object, while `Outcome`,
`Execution`, `Completeness` and `Error` describe the evidence supporting it. `-AsObject` does
not enumerate, serialize or transfer business data to the engine to measure its size.

## 2. Produce one business fact: the number of reachable commits

Instead of delivering the text `157`, give the consumer a named, typed fact. Parse the one
stdout record in `-Output`; produce the final business object in `-Complete`.

<!-- quiet-example: commit-count -->
```powershell
# Objective: Count commits reachable from HEAD in the selected repository.
$countOutput = {
    param($event, $runtime)
    if ($event.Stream -ne 'stdout') { return }
    $value = 0L
    if (![long]::TryParse($event.Text.Trim(), [ref]$value) -or $value -lt 0) {
        throw 'InvalidGitCommitCount'
    }
    $runtime.Data.Value = $value
    $runtime.Data.Records++
}
$countComplete = {
    param($runtime)
    if ($runtime.Data.Records -ne 1) { throw 'ExpectedOneGitCommitCount' }
    [pscustomobject]@{ Revision = 'HEAD'; ReachableCommits = $runtime.Data.Value }
}
$count = quiet -AsObject -C history-size -WorkingDirectory $repository -RecordDelimiter "`n" -Data @{ Value = 0L; Records = 0 } -Output $countOutput -Complete $countComplete -FilePath git -ArgumentList @('rev-list', '--count', 'HEAD')
```

`-RecordDelimiter` gives the parser complete records instead of assuming native read blocks
match lines. `-Output` must emit no incidental pipeline values. Assign state to `runtime.Data`
and use `[void]` when calling a method whose return value should be discarded. `-Complete`
returns at most one business value; return an array with the unary comma if needed.

Before using the fact, require complete execution and analysis:

<!-- quiet-example: check-count -->
```powershell
# Objective: Require complete evidence before using the commit count.
if ($count.Outcome -ne 'Success' -or !$count.Completeness.Source -or !$count.Completeness.Analysis -or $count.Error.Count) {
    FrenchExDev2.QuietCli.Core.PoSh\Out-QuietResult $count -MaxItems 5 -MaxOutputBytes 4096
    throw 'CommitCountIncomplete'
}
$commitCount = $count.Data.ReachableCommits
```

A zero native exit alone does not establish complete drainage or successful parsing. A failure
is not an instruction to retry. Check `Execution.Native.ExitCode` when a decision depends on
the actual native status and declare documented `-SuccessExitCodes` when zero is insufficient.

## 3. Produce structured business data: recent changes for a release review

The next analyzer turns Git records into commit objects. Its tab-separated format consists
of a full object identifier, a strict ISO author date and the subject. Splitting into at most
three fields preserves tabs inside the subject. This parser does not claim to parse arbitrary
human-readable Git output.

<!-- quiet-example: recent-commits -->
```powershell
# Objective: Build typed commit objects for a bounded release-review scope.
$commitOutput = {
    param($event, $runtime)
    if ($event.Stream -ne 'stdout') { return }
    $line = $event.Text.TrimEnd([char[]]"`r`n")
    $fields = $line.Split([char[]]@([char]9), 3, [StringSplitOptions]::None)
    if ($fields.Count -ne 3 -or $fields[0] -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
        throw 'InvalidGitReviewRecord'
    }
    [void]$runtime.Data.Commits.Add([pscustomobject]@{
        ObjectId = $fields[0]
        AuthoredAt = [DateTimeOffset]::ParseExact($fields[1], [string[]]@('yyyy-MM-ddTHH:mm:sszzz', "yyyy-MM-ddTHH:mm:ss'Z'"), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
        Subject = $fields[2]
    })
}
$commitComplete = {
    param($runtime)
    [pscustomobject]@{ Revision = 'HEAD'; ReturnedCommits = $runtime.Data.Commits.Count; Commits = $runtime.Data.Commits.ToArray() }
}
$reviewProjection = { param($data, $budget) [pscustomobject]@{ ReturnedCommits = $data.ReturnedCommits; Changes = @($data.Commits | Select-Object ObjectId, Subject) } }
$recent = quiet -AsObject -Projection $reviewProjection -C release-review -WorkingDirectory $repository -RecordDelimiter "`n" -Data @{ Commits = [Collections.Generic.List[object]]::new() } -Output $commitOutput -Complete $commitComplete -FilePath git -ArgumentList @('log', '--max-count=50', '--format=%H%x09%aI%x09%s', 'HEAD')
if ($recent.Outcome -ne 'Success' -or !$recent.Completeness.Source -or !$recent.Completeness.Analysis -or $recent.Error.Count) { throw 'ReleaseReviewIncomplete' }
```

The native limit is the explicit business scope: at most 50 reachable commits from HEAD.
`ReturnedCommits` is not a count of every commit in the repository. Business storage contains
only selected fields, not an automatic raw transcript. Create a fresh list for each execution
or replay; reusing an analyzer does not mean sharing mutable state between independent runs.

## 4. Deliver a small JSON or YAML view without executing Git again

Keep the complete local object and choose the representation needed by the next consumer.

<!-- quiet-example: bounded-deliveries -->
```powershell
# Objective: Deliver the same observed result in bounded JSON and YAML forms.
$json = FrenchExDev2.QuietCli.Core.PoSh\Out-QuietResult $recent -AsJson -MaxItems 5 -MaxOutputBytes 4096
$yaml = FrenchExDev2.QuietCli.Core.PoSh\Out-QuietResult $recent -AsYaml -MaxItems 5 -MaxOutputBytes 4096
$compactJson = FrenchExDev2.QuietCli.Core.PoSh\ConvertTo-QuietJson $recent -MaxItems 5 -MaxOutputBytes 4096
```

`-MaxItems` bounds each presented container; `-MaxOutputBytes` bounds the final UTF-8 envelope.
These limits do not reduce the underlying business object or refresh the repository state.
A representation can omit items or fall back to a smaller envelope: inspect `Truncation` in
that delivery. Do not assume every local field appears in a bounded representation.

`quiet -AsJson` and `quiet -AsYaml` select immediate formatted output for an execution. Replacing
`-AsObject` with one of those flags executes the native command anew. To avoid that extra work,
convert the retained object as above. Formats are mutually exclusive.

QuietCli result JSON is already compact. `ConvertTo-QuietJson` and `Out-QuietResult` do not
accept a JSON `-Compress` switch. `Get-QuietCliGain -AsJson -Compress` does, as shown below;
Recall's numeric `-Compress` is an archive compression level and has a different purpose.

For a narrower business view, select it explicitly at delivery time:

<!-- quiet-example: projection -->
```powershell
# Objective: Keep full commit objects local and expose only identifiers and subjects.
# The release-review call supplied -Projection $reviewProjection before execution.

$reviewJson = FrenchExDev2.QuietCli.Core.PoSh\ConvertTo-QuietJson $recent -MaxItems 5 -MaxOutputBytes 4096
```

The release-review example supplies `-Projection` in the original `quiet` call.
Do not edit execution/completeness snapshots or serialize the envelope with a general-purpose
serializer. A projection changes delivery content, not the original source or the native result.

## 5. Measure the gain rather than infer it from -AsObject

<!-- quiet-example: gain -->
```powershell
# Objective: Compare measured business-source volume with actual deliveries for this context.
$gain = Get-QuietCliGain -C release-review
$gainObject = Get-QuietCliGain -C release-review -AsObject
$gainYaml = Get-QuietCliGain -C release-review -AsYaml
$gainJson = Get-QuietCliGain -C release-review -AsJson
$gainCompactJson = Get-QuietCliGain -C release-review -AsJson -Compress
```

For this report, object output is the default, JSON is indented unless `-Compress` is supplied,
and `-Compress` requires `-AsJson`. Formatting the gain report does not itself create delivery
telemetry or inflate the measured gain. `-Days`, `-From`, `-To`, `-SessionId`, `-GroupBy` and
`-MaxEvents` select the measurement scope; without date filters, the report covers all history.

Check report completeness and scope before comparing totals. Native source bytes are deduplicated;
actual deliveries have their own measured bytes. `ReductionBytes` stays unknown when required
measurements or source/analysis completeness are missing. Object-only execution does not establish
serialized delivery savings. Native tokens are unknown: tokenization measures only final delivered
text, identifying its encoding. Byte savings are not a model-independent token count or API bill.
Repeated identical representations reuse a delivery identity; `AlreadyDelivered` reports this.

Persistent PowerShell can also save profile/module startup and retain objects between agent calls.
That is a different gain from reducing output. Reusing `$recent` avoids Git work but preserves an
old observation; execute a new observation when repository freshness matters.

## 6. Capture once in memory, then change the business analysis with Recall

Ordinary streaming does not retain native output. Decide before execution to use `-Recall`
when another analysis of the same evidence may be needed:

<!-- quiet-example: capture -->
```powershell
# Objective: Keep bounded native evidence while producing the first release-review object.
$capture = quiet -AsObject -Recall -RecallMaxBytes '1MiB' -RecallPolicy Head -C release-review -WorkingDirectory $repository -RecordDelimiter "`n" -Data @{ Commits = [Collections.Generic.List[object]]::new() } -Output $commitOutput -Complete $commitComplete -FilePath git -ArgumentList @('log', '--max-count=50', '--format=%H%x09%aI%x09%s', 'HEAD')
if ($capture.Outcome -ne 'Success' -or !$capture.Completeness.Source -or !$capture.Completeness.Analysis) { throw 'ReleaseCaptureIncomplete' }
```

This is one new native observation, with both analysis and explicit evidence retention. The
memory budget counts native bytes; indexes and objects consume additional memory. `Head`,
`Tail` and `HeadAndTail` choose the retained ranges. `All` removes the configured byte ceiling
and requires `Head`. Hitting a retention limit does not stop native execution or analysis.

Replay with the same parser and a new final business decision, without executing Git:

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

This subject-based rule selects review candidates; it does not establish whether a change is
actually breaking. Recall replays bytes through new callbacks with fresh state. It does not
execute stored code or rerun the original command. Memory capture disappears with its process.

Missing retained ranges require explicit `-AllowPartial`; partial analysis must not be presented
as complete evidence. Decoder/framer resets at gaps prevent joining unrelated fragments into
fabricated records. For byte-level inspection, use `Get-QuietRecall` with explicit stream,
offset, byte count, item and output budgets; use `New-QuietRecallReference` for stable evidence ranges.

## 7. Save evidence for another process or another session

Use `-SaveRecall` during execution when persistence is required. It writes the journal as
output arrives; it does not rely on retaining everything in RAM:

<!-- quiet-example: durable -->
```powershell
# Objective: Record release-review evidence in an explicitly selected persistent workspace directory.
$recallRoot = Join-Path $repository '.quietcli-evidence'
$recorded = quiet -AsObject -SaveRecall -RecallRoot $recallRoot -RecallName release-review -C release-review -WorkingDirectory $repository -RecordDelimiter "`n" -Data @{ Commits = [Collections.Generic.List[object]]::new() } -Output $commitOutput -Complete $commitComplete -FilePath git -ArgumentList @('log', '--max-count=50', '--format=%H%x09%aI%x09%s', 'HEAD')
$recallId = $recorded.Recall.RecallId
$savedEvidence = Get-QuietSavedRecall -RecallRoot $recallRoot -RecallId $recallId
```

The directory is an explicit evidence artifact; exclude it from source publication as appropriate.
A later session needs Core, the root, the identity and newly defined analyzer callbacks; it does
not need the original `$recorded` variable or executable:

<!-- quiet-example: saved-replay -->
```powershell
# Objective: Rebuild the commit business object from a saved journal without native execution.
$restored = quiet -AsObject -RecallId $recallId -RecallRoot $recallRoot -RecordDelimiter "`n" -Data @{ Commits = [Collections.Generic.List[object]]::new() } -Output $commitOutput -Complete $commitComplete
$restoredJson = FrenchExDev2.QuietCli.Core.PoSh\ConvertTo-QuietJson $restored -MaxItems 5 -MaxOutputBytes 4096
```

Do not append `git` or native arguments to a `-RecallId` call. A name is a searchable label,
not a unique identity. Configuration `recall.root` can select the usual storage root, and
`Get-QuietSavedRecall -RecallName 'release-*'` searches it. SQLite contains measurement metadata,
not the native journal or ordinary business objects.

You can instead call `Save-QuietRecall $capture` after execution, but it can save only the
bytes still retained. It cannot recover bytes omitted by the memory budget. A finalized
journal may still describe a failed, interrupted or incomplete native source: inspect native
status, source completeness and recovery metadata before trusting the reconstructed business data.

## 8. Export evidence and choose archive compression explicitly

Working captures stay uncompressed for repeated analysis. Export a directory by default, or
request a ZIP transport explicitly:

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

Here `-Compress` is an integer level **0 through 9**, requires `-Zip`, and defaults to 6.
Zero stores without compression; nine requests the highest level, not a guaranteed size reduction.
Transport input/output bytes and ratio are measured. Small or incompressible inputs can grow.
Without `-Zip`, `Export-QuietRecall` creates a working directory; the numeric `-Compress`
parameter is not accepted for that operation. Existing export destinations are not overwritten.

Imports verify integrity and reject malformed records and unsafe archive paths. Integrity is
not author authentication. Export only the evidence that should be shared; Recall deliberately
retains native content, whereas ordinary bounded result delivery excludes it.

## Configuration and lifecycle

`QUIETCLI_CONFIG_DIRECTORY` selects the directory containing `config.yaml`.
`New-QuietCliConfiguration` creates a complete default template, and
`Import-QuietCliConfiguration` explicitly reloads it. When using ephemeral configuration,
point both telemetry and Recall storage at owned locations; changing the configuration directory
alone does not relocate the defaults. Keep hosting at `Auto` unless another mode is explicitly
required. Finish active work and stop the engine before switching database or hosting settings.

Keep the question, native execution, business analysis, object retention, formatted delivery,
Recall evidence and measured gains distinct. Preserve failures and uncertainty. No wrapper grants
permission for retries, installation, profile edits, hooks, network access or publication.
