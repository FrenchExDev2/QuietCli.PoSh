# QuietCli: agent instructions

`quiet` runs a native command and turns its output into a caller-local business object: typed data
plus the evidence that it is complete. Source and issues: <https://github.com/FrenchExDev2/FrenchExDev2.QuietCli.PoSh>.
For any command below, use `Get-Help <command> -Full`; `Get-Command -Module FrenchExDev2.QuietCli.Core.PoSh` lists them all.

This file is the whole production contract. It is not the QuietCli repository's maintenance rules.

## Rules

1. Before executing, define the question, the business data required and the smallest useful delivery. Keep unknown measurements unknown.
2. Use PowerShell Core 7.6+ with its normal profile and UTF-8 initialization. Import `FrenchExDev2.QuietCli.Core.PoSh` once per process. Never load legacy QuietCli or OPumper modules in the same process.
3. Read the executable's help or official format documentation before writing a parser. A handler listed in the inventory is not proof that a variant or platform is supported.
4. Run native commands through `quiet`, with a registered handler or explicit `-Output` and `-Complete` callbacks. Without either, the command is rejected before it runs. CI orchestration and read-only streaming monitors keep their host's documented exceptions.
5. Set `-WorkingDirectory`. QuietCli options precede the executable; native arguments follow verbatim. Use `-FilePath` and `-ArgumentList` for exact argument vectors.
6. Keep `-AsObject` results in named variables. Before using `Data`, check `Outcome`, `Completeness.Source`, `Completeness.Analysis`, `Error` and the business scope. A zero exit code does not prove complete analysis.
7. Callbacks keep only business data in `runtime.Data`. `-Output` emits nothing to the pipeline (use `[void]`). `-Complete` returns at most one value; use the unary comma to return an array. Parsers throw on records they do not recognize instead of skipping them.
8. Deliver bounded views with `Out-QuietResult` or `ConvertTo-QuietJson`. Never dump `Internal`, callback objects or native evidence. `-AsObject` alone saves nothing on delivery.
9. Results live in the PowerShell process. Use one persistent process when the client allows it; otherwise keep each call self-contained, or use Recall to survive the process.
10. Preserve failures and incomplete evidence. Never retry automatically or repeat a mutation whose effect is unknown. A suggestion is not an authorization.
11. No installation, profile change, hook, network access, push or publication is authorized by QuietCli. Follow the host project's test and monitoring rules.
12. Run `Add-QuietAgentInstruction` only when the user asks to install these instructions; it writes files. Preview with `-WhatIf`.

## Commands

| Purpose | Commands |
| --- | --- |
| Run | `Invoke-QuietCli` (alias `quiet`) |
| Deliver | `Out-QuietResult`, `ConvertTo-QuietJson`, `ConvertTo-QuietYaml` |
| Handlers | `Register-QuietHandler`, `Get-QuietHandler`, `Unregister-QuietHandler`, `New-QuietModule`, `New-QuietByteRecordFramer` |
| Recall (evidence) | `Get-QuietRecall`, `Invoke-QuietRecall`, `New-QuietRecallReference`, `Save-QuietRecall`, `Get-QuietSavedRecall`, `Export-QuietRecall`, `Import-QuietRecall` |
| Measure | `Get-QuietCliGain`, `Repair-QuietCliMeasurementPrivacy` |
| Configuration | `Get-QuietCliConfiguration`, `Test-QuietCliConfiguration`, `New-QuietCliConfiguration`, `Import-QuietCliConfiguration` |
| Engine | `Get-QuietEngine`, `Stop-QuietEngine` |
| Instructions | `Get-QuietAgentInstruction`, `Add-QuietAgentInstruction` |

- **Recall.** Ordinary streaming keeps no native output. `-Recall -AsObject` retains bounded in-memory evidence;
  `-SaveRecall -AsObject` writes a durable journal identified by `RecallId`. `Invoke-QuietRecall` re-runs new
  callbacks over that evidence without executing the command. Partial evidence needs `-AllowPartial` and must be
  reported as partial. `-Recall` and `-SaveRecall` require explicit `-AsObject`.
- **Gains.** `Get-QuietCliGain` reports measured volumes only; native tokens and unmeasured sizes stay unknown. Byte savings are not an API bill.
- **Configuration.** `QUIETCLI_CONFIG_DIRECTORY` selects the directory holding `config.yaml`. Keep `engine.hosting` at `Auto`. A disposable configuration must also relocate the database and Recall root.
- **Handlers.** `New-QuietModule` generates a business module with its test companion. Reusable executable semantics belong there, not in ad hoc callbacks.

## Examples

Each example runs against a Git repository with at least one commit. `$repository` is its path.

One typed fact: the commits reachable from HEAD.

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

Require complete evidence before using it:

<!-- quiet-example: check-count -->
```powershell
# Objective: Require complete evidence before using the commit count.
if ($count.Outcome -ne 'Success' -or !$count.Completeness.Source -or !$count.Completeness.Analysis -or $count.Error.Count) {
    FrenchExDev2.QuietCli.Core.PoSh\Out-QuietResult $count -MaxItems 5 -MaxOutputBytes 4096
    throw 'CommitCountIncomplete'
}
$commitCount = $count.Data.ReachableCommits
```

Structured data with a delimiter, a bounded scope and a projection that limits what is delivered:

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

Deliver bounded JSON or YAML from the retained object, without running Git again. Check `Truncation` in a delivery:

<!-- quiet-example: bounded-deliveries -->
```powershell
# Objective: Deliver the same observed result in bounded JSON and YAML forms.
$json = FrenchExDev2.QuietCli.Core.PoSh\Out-QuietResult $recent -AsJson -MaxItems 5 -MaxOutputBytes 4096
$yaml = FrenchExDev2.QuietCli.Core.PoSh\Out-QuietResult $recent -AsYaml -MaxItems 5 -MaxOutputBytes 4096
$compactJson = FrenchExDev2.QuietCli.Core.PoSh\ConvertTo-QuietJson $recent -MaxItems 5 -MaxOutputBytes 4096
```

## When a result is not Success

| Observed | Meaning | Do |
| --- | --- | --- |
| `Outcome` `Unsupported`, `Error[0].Code` `HandlerNotFound` | No handler and no callbacks; nothing ran | Register a handler or supply `-Output` and `-Complete` |
| `Outcome` `Failed`, `Execution.Native.ExitCode` non-zero | The native command failed | Read its documented exit codes; declare `-SuccessExitCodes` only for documented successes |
| `Completeness.Source` or `.Analysis` false | Output not fully drained, or the analyzer did not finish | Treat `Data` as unusable; fix the parser, then observe again |
| Exception `RecallRequiresExplicitAsObject` | `-Recall` or `-SaveRecall` without `-AsObject` | Add `-AsObject` |
| Wrong module path, or binaries missing | A stale release is loaded, or the C# engine is not built | Check `(Get-Module FrenchExDev2.QuietCli.Core.PoSh).Path`; rebuild, then use a fresh process |
