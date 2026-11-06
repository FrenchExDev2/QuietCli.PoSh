# Streaming, callbacks and results

[Back to the QuietCli overview](README.md)

How `quiet` consumes native output and how callbacks turn it into business data. Related: [Recall](README-recall.md), [Measurements](README-measurements.md), [Core module README](FrenchExDev2.QuietCli.Core.PoSh/README.md).

Without an explicit capture option, stdout/stderr are read once, counted, dispatched through bounded transient buffers and released. No cumulative raw capture, output spool or content history is created. Native queues are bounded to 16 blocks of 16 KiB per invocation. Incremental UTF-8 decoding and delimiter framing run in C#; unfinished records are bounded by `MaxRecordBytes`. Invalid or incomplete UTF-8 and oversized records fail explicitly.

`-Output` receives `(event, runtime)` and must emit no incidental pipeline output. Store required business information in `runtime.Data`; use `[void]` for methods whose return values should be discarded. `-Complete` receives the runtime and returns at most one business value. Use the unary comma to return an array as one value. If it returns no value, the existing `Data` is preserved.

Without explicit callbacks, command execution requires a documented compatible registered handler. Unsupported commands are rejected before business execution. `-SaveRecall` also permits direct recording without a parser.

Collection, retention, decoding, business analysis and delivery are separate responsibilities. `-AsObject` returns a local envelope without enumerating, serializing or transferring `Data` to the engine. Inspect `Outcome`, `Execution`, `Completeness` and errors alongside the business data. JSON/YAML delivery applies item, structural and encoded-byte budgets; a delivery projection can select only the information needed by the consumer.

Nested native calls from callbacks have their own results and retain visible failures. Children inherit the measurement context, but do not implicitly inherit Recall retention or recording. After an analyzer failure, native drainage continues and `Complete` can finalize partial business data.

## Anatomy of a result

`-AsObject` returns a local envelope. Check it before trusting `Data`:

| Field | Question it answers | Typical values |
| --- | --- | --- |
| `Outcome` | Did the invocation do its job? | `Success`; `Failed` (the native command exited with a non-success code); `Unsupported` (no handler and no callbacks, so nothing ran) |
| `Execution` | What happened to the native process? | Native exit code, timing, `EffectStatus`, `State`, issues |
| `Completeness.Source` | Was the native output fully read? | `True`, or `False` when drainage was interrupted |
| `Completeness.Analysis` | Did the analyzer see every record and finish? | `True`, or `False` after a callback failure |
| `Error` | Which structured error codes were raised? | Empty on success; for example `HandlerNotFound` |
| `Data` | The business result built by your callbacks or a handler | Whatever `-Complete` returned |

A zero exit code does not prove a complete analysis. Use this guard before consuming `Data`:

```powershell
if ($r.Outcome -ne 'Success' -or !$r.Completeness.Source -or !$r.Completeness.Analysis -or $r.Error.Count) {
    throw 'IncompleteResult'
}
```

The [agent failure table](docs/agents/AGENTS.md) lists what to do for each non-success observation.

## Callback pitfalls

- **Options precede the executable.** `quiet -AsObject -C label git status`: QuietCli options first, native arguments after, verbatim. For an exact argument vector use `-FilePath` and `-ArgumentList`.
- **Emit nothing from `-Output`.** Incidental pipeline output is an error. Discard method return values with `[void]`.
- **Return one value from `-Complete`.** Use the unary comma (`,$array`) to return an array as a single value.
- **Frame records explicitly.** Set `-RecordDelimiter` (for example `` "`n" ``) for line-oriented tools; unfinished records are bounded by `MaxRecordBytes`.
- **Fail on unknown records.** Throw instead of guessing; an analyzer failure is reported through `Completeness.Analysis`.
- **Callbacks must cooperate with cancellation.** A timeout stops the native process, but cannot forcibly interrupt a blocked PowerShell callback.

## Reusable scripts

`quiet -Script ./Tool.ps1 ...` writes a readable call definition instead of running it. See the [Core module README](FrenchExDev2.QuietCli.Core.PoSh/README.md#reusable-scripts-and-business-factories) for the rules and limits.
