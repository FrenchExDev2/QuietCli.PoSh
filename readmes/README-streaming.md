# Streaming, callbacks and results

[Back to the QuietCli overview](../README.md)

How `quiet` consumes native output and how callbacks turn it into business data. Related: [Recall](README-recall.md), [Measurements](README-measurements.md), [Core module README](../src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/README.md).

Without an explicit capture option, stdout/stderr are read once, counted, dispatched through bounded transient buffers and released. No cumulative raw capture, output spool or content history is created. Native queues are bounded to 16 blocks of 16 KiB per invocation. Incremental UTF-8 decoding and delimiter framing run in C#; unfinished records are bounded by `MaxRecordBytes`. Invalid or incomplete UTF-8 and oversized records fail explicitly.

`-Output`, `-StdOut` and `-StdErr` receive `(event, runtime)`. Each event goes to `-Output` first and then to its matching stream callback when supplied. PTY delivers merged `terminal` events through `-Output`. The callbacks share text decoding, framing and byte-mode behavior. Store required business information in `runtime.Data` and use `[void]` to discard method return values.

`-Complete` receives the runtime and returns at most one business value. Use the unary comma to return an array as one value. If it returns no value, the existing `Data` is preserved. All callbacks can read the same `$runtime.Mode` and `$runtime.ArgvString`. The latter shows the supplied executable and native arguments, with quoting that preserves their boundaries.

`$runtime.IsRecall` is a read-only Boolean. It is true during offline replay and false during a live invocation, including one that records with `-Recall` or `-SaveRecall`.

Without explicit callbacks, command execution requires a documented compatible registered handler. Unsupported commands are rejected before business execution. `-SaveRecall` also permits direct recording without a parser.

## Callback factories for companions

A handler registered with `Register-QuietHandler` can expose `CallbackFactory` alongside the existing `Execute` contract. Core selects the handler using its binary, version and match rules, then calls the factory with the caller's runtime. The factory returns a hashtable containing `Arguments` (the exact native argument vector) and `Options` (native input, stream and analysis options such as `Data`, `Output` and `Complete`). Core uses the resolved executable and runs the prepared request once. PowerShell invokes the scriptblocks, including closures, in the caller's runspace.

An optional `Finish` scriptblock receives the completed Core result and returns the business value. Without it, the handler result uses the native call's `Data`. Optional `Cleanup` releases factory-owned state even when validation, execution or finalization fails. A factory can also return `@{ Data = $value }` for a classified answer that requires no business process, or yield no value to delegate the form to its existing `Execute` handler. Explicit caller analysis callbacks still take the direct execution path.

A registered `ProbeFactory` returns `Arguments` and `Options` for version detection. Set `Options.Role = 'Probe'` and supply a `Complete` callback that returns the observed version. Core runs the probe, caches the successful version and passes it to `TestVersion` and `Match`. A legacy `Probe` callback can still provide the version directly.

A companion that needs an intermediate result can pass `@{ Arguments = $arguments; Options = $options }` to `$runtime.InvokeCompanionCommand(...)`. A factory can use it for discovery before returning the main command, and `Finish` can use it for follow-up commands selected from the main result. The call uses the resolved executable and defaults to the parent working directory and environment. The companion supplies the stream or completion scriptblocks. Core returns the complete local child result, including `Data`, `Execution` and `Completeness`. Each child contributes its sources and failures to the same parent invocation.

Collection, retention, decoding, business analysis and delivery are separate responsibilities. `-AsObject` returns a local envelope without enumerating, serializing or transferring `Data` to the engine. Inspect `Outcome`, `Execution`, `Completeness` and errors alongside the business data. JSON/YAML delivery applies item, structural and encoded-byte budgets; a delivery projection can select only the information needed by the consumer.

Nested native calls from callbacks have their own results and retain visible failures. Children inherit the measurement context, but do not implicitly inherit Recall retention or recording. After an analyzer failure, native drainage continues and `Complete` can finalize partial business data.

## Read execution metadata in `-Complete`

QuietCli runs `-Complete` after draining the output and before building the result envelope. The callback can read the final native execution snapshot in a live call, or the recorded source status in a Recall replay.

| Value | Live invocation | Recall replay |
| --- | --- | --- |
| Command and arguments | `$runtime.ArgvString` | `$runtime.ArgvString` |
| Observed exit code | `$runtime.Execution.ExitCode` | `$runtime.Recall.SourceStatus.ExitCode` |
| Code requested through `.Exit(int)` | `$runtime.Execution.RequestedExitCode` | Unavailable |
| Replay flag | `$runtime.IsRecall` is `$false` | `$runtime.IsRecall` is `$true` |

The observed exit code can be `$null` if it was unavailable or the capture did not record it. `ArgvString` can also be `$null` when the capture has no command text. After the call returns, `$result.ExitCode` exposes the observed or recorded code directly.

Use the same completion callback for a live capture and a replay.

```powershell
$complete = {
    param($runtime)

    $exitCode = if ($runtime.IsRecall) {
        $runtime.Recall.SourceStatus.ExitCode
    } else {
        $runtime.Execution.ExitCode
    }

    [pscustomobject]@{
        Command = $runtime.ArgvString
        ExitCode = $exitCode
        IsRecall = $runtime.IsRecall
    }
}

$live = quiet -AsObject -Recall -Complete $complete git --version
$replay = Invoke-QuietRecall -InputObject $live -Complete $complete
$live.Data
$replay.Data
```

## Stop a running child from a callback

Call `$runtime.Exit(0)` from `-Output`, `-StdOut` or `-StdErr` when the native command has produced enough information. QuietCli terminates the owned process tree, drains pending output and runs `-Complete` once. The callback can keep running after the call returns.

The first stop request applies while the child is running. If the child has already exited, QuietCli uses its natural status. When the stop request applies, QuietCli compares `RequestedExitCode` with `-SuccessExitCodes` to determine `Outcome`, and `Completeness.Source` is false. The system-reported `ExitCode` remains available and can differ from `RequestedExitCode`. If you share an output callback with Recall, check `!$runtime.IsRecall` before calling `.Exit()`.

## Invocation modes

| Mode | Delivery | Dashboard |
| --- | --- | --- |
| `Agent` | JSON by default, YAML with `-AsYaml` | Off by default |
| `User` | YAML by default | On by default |
| `Script` | PowerShell object by default | Off by default |

Direct calls at an interactive PowerShell console prompt choose `User` when `-Mode` is omitted.
Scripts, nested calls and non-interactive calls choose `Script`. Use `-Mode Agent` to receive a bounded
JSON or YAML delivery. Explicit format switches take precedence in `User` and `Script`. To collect
Recall evidence, supply `-AsObject` explicitly in `Script` or `User` mode.

```powershell
quiet -Mode Agent -Data @{ Version = '' } -StdOut {
    param($event, $runtime)
    $runtime.Data.Version += $event.Text
} -Complete {
    param($runtime)
    @{ Version = $runtime.Data.Version.Trim(); Command = $runtime.ArgvString }
} dotnet --version
```

## Anatomy of a result

`-AsObject` returns a local envelope. Check it before trusting `Data`:

| Field | Question it answers | Typical values |
| --- | --- | --- |
| `Outcome` | Did the invocation do its job? | `Success`; `Failed` (for example, a non-success exit code or failed analysis); `Unsupported` (no compatible handler for the requested business command; a version probe may have run) |
| `ExitCode` | Which exit status did the system report? | Integer, or `null` when no single native exit was observed |
| `RequestedExitCode` | Which status did the callback supply to stop the child? | Integer for an applied stop request, otherwise `null` |
| `Execution` | What happened to the native process? | Native exit code, timing, `EffectStatus`, `State`, issues |
| `Completeness.Source` | Was the native output fully read? | `True`, or `False` when drainage was interrupted |
| `Completeness.Analysis` | Did the analyzer see every record and finish? | `True`, or `False` after a callback failure |
| `Error` | Which structured error codes were raised? | Empty on success; for example `HandlerNotFound` |
| `Data` | The business result built by your callbacks or a handler | Whatever `-Complete` returned |
| `Events` | Optional business-event snapshot | Present only with `-CollectEvents`; ordered values passed to `$runtime.Emit(...)` |

A zero exit code does not prove a complete analysis. Use this guard before consuming `Data`:

```powershell
if ($r.Outcome -ne 'Success' -or !$r.Completeness.Source -or !$r.Completeness.Analysis -or $r.Error.Count) {
    throw 'IncompleteResult'
}
```

The [agent failure table](../docs/agents/AGENTS.md) lists what to do for each non-success observation.

## Callback pitfalls

`-Listeners` accepts one scriptblock or an array of scriptblocks. Call `$runtime.Emit($kind, $data)` from
`-Output`, `-Complete` or a handler to invoke every listener with `(event, runtime)`
in registration order. Listener callbacks produce no pipeline output. A failing listener is disabled for
that call and adds `ListenerFailed` to `Error`; other listeners and business analysis continue. Events
are transient by default: `$runtime.Events` remains empty and the result omits `Events`.
Pass `-CollectEvents` explicitly to retain the emitted objects locally, including without listeners.
The finished result receives an array snapshot, not the mutable runtime list. Collection has no
automatic item cap, so select only the business events you need. It never records raw native output.
Nested calls have their own listeners and collection settings; collection is not inherited.
JSON/YAML deliveries include `Events` only when requested, apply `MaxItems`, and report omitted
items without altering the local array. Live listeners and UI do not require collection.

Each emission creates a `QuietCli2.Event` object with `Type = $kind` and `Data = $data`.
The type is a caller-defined string; Data can be a custom object, dictionary, array, scalar or null.
Listeners and collection receive the same envelope. Data stays local by reference, without
enumeration or serialization during emission. Read payload fields through `$event.Data`.

```powershell
# Inside an Output or Complete callback:
$runtime.Emit('Progress', [pscustomobject]@{ File = 'rapport.txt'; Percent = 75 })
# A listener receives: $event.Type == 'Progress', $event.Data.Percent == 75
```

`-UI` and `-UI:$false` override the mode's dashboard setting. The enabled dashboard provides
`$runtime.Ui.Write($event, $lane)` and `$runtime.Ui.NewLine($lane)`. `-MaxLines` selects a positive
history depth per lane when the dashboard is enabled. Call `Ui.Write` to display an emitted event.
The [Vagrant companion](../src/Vagrant/src/FrenchExDev2.QuietCli.Vagrant.PoSh/README.md)
supplies both event emission and per-machine presentation.

- **Options precede the executable.** `quiet -AsObject -C label git status`: QuietCli options first, native arguments after, verbatim. For an exact argument vector use `-FilePath` and `-ArgumentList`.
- **Emit nothing from `-Output`.** Incidental pipeline output is an error. Discard method return values with `[void]`.
- **Return one value from `-Complete`.** Use the unary comma (`,$array`) to return an array as a single value.
- **Frame records explicitly.** Set `-RecordDelimiter` (for example `` "`n" ``) for line-oriented tools; unfinished records are bounded by `MaxRecordBytes`.
- **Fail on unknown records.** Throw instead of guessing; an analyzer failure is reported through `Completeness.Analysis`.
- **Callbacks must cooperate with cancellation.** A timeout stops the native process, but cannot forcibly interrupt a blocked PowerShell callback.

## Reusable scripts

Generated native calls preserve explicit `-CollectEvents` values. Offline Recall analysis retains its separate Data/cursor contract; it does not accept this native-invocation collection option.

`quiet -Script ./Tool.ps1 ...` writes a readable call definition instead of running it. See the [Core module README](../src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/README.md#reusable-scripts-and-business-factories) for the rules and limits.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
