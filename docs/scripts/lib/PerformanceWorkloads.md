# PerformanceWorkloads.psm1

<!-- script-source:begin -->
Source file: [`lib/PerformanceWorkloads.psm1`](../../../scripts/lib/PerformanceWorkloads.psm1)
<!-- script-source:end -->

## Purpose and usage

This module reads a Core suite summary and the profiler line evidence of one environment. It turns them into one statistics row per workload, measure and variant for [New-CorePerformanceReport.ps1](../New-CorePerformanceReport.md). The workloads are kept apart: a Git transport number is never pooled with a framing or event number.

| Workload | Measure | Evidence |
| --- | --- | --- |
| `ImportFirstCall` | Fresh-process import, import minus paired baseline, first call with a cold engine, engine startup per hosting mode | `FreshSessionImport`, `ControlledGitStatus` first calls, `EngineStartup` |
| `GitTransport` | Warm call, warm execution, warm callbacks, 8 MiB transport per hosting mode | `ControlledGitStatus` warm calls, `EngineTransport` |
| `Framing` | 1 MiB framing per implementation and record width | `RecordFraming` |
| `Metadata` | Outside execution: invocation minus execution of each warm call | `ControlledGitStatus` warm calls |
| `Events` | Emit loop, with variants `listeners=0/1/4, collect=on/off` | `EventEmission` from `Measure-QuietEventEmission` |
| Each profiled workload | Instrumented iteration | `powershell-lines.json` `Workloads[].SamplesMs` |

| Export | Contract |
| --- | --- |
| `Get-QuietPerformanceMember` | Reads one member of a JSON object or dictionary. An absent member returns nothing. |
| `Get-QuietPerformanceItems` | Returns items whose member (`Kind` by default) equals a value, compared ordinally. |
| `Get-QuietPerformanceNumbers` | Projects one member as `double[]`. An absent member is skipped. A present value that is not exactly one finite number of type `double`, `long`, `int`, `decimal` or `single` increments `Rejected`. Strings, booleans, arrays, NaN, ±∞ and an explicit null all count as rejected. |
| `New-QuietPerformanceGroup` | Returns one `{Variant, Values}` group. The variant is `-` when there is only one. |
| `Get-QuietPerformanceHumanSamples` | Returns the human `git status` samples of one kind across every controlled Git state. |
| `Get-QuietPerformanceVariantGroups` | Groups items by a computed label, in ordinal label order. |
| `Get-QuietPerformanceWorkloadCatalog` | The ordinary and explicit diagnostic measures. Each one has a phase, a source path, its limits and a `Select` block. |
| `Get-QuietPerformanceWorkloadRows` | Returns `{Rows, Rejected}`. A measure without data still yields a row with null `Statistics`, so a gap stays visible. |
| `Get-QuietPerformanceRuntimeNote` | Names each `PowerShell <version> on <CLR>` group with its RIDs and states that a difference between rows is not causal and not an OS ranking. It says so even when every environment shares one runtime. |

## Dependencies and side effects

The module imports [PerformanceStatistics.psm1](PerformanceStatistics.md). It reads only the objects it is given and writes nothing.

## Critical review and verdict

- **Selectors are bound to the evidence shape.** A renamed evidence field leaves the row empty rather than failing. This is deliberate: the report then shows `-` and the coverage overview shows a dashed gap. The unit tests pin every source path.
- **Pooled Git states.** Warm calls pool eight different repository states, so their dispersion mixes state cost with run noise. The `Limits` column says so.
- **Metadata is an upper bound.** `Outside execution` includes dispatch and projection. The metadata save is not measured separately.
- **Runtime confounding is stated, not removed.** The hosted musl leg runs PowerShell 7.6.10 on .NET 10.0.14, while the others run 7.7.0 on .NET 11.0.0. The note forbids ranking or causal readings instead of trying to correct for it.

Verdict: one catalog entry per measure keeps the extension point small, and gaps stay visible.

## Tests

- [`unit/lib/PerformanceWorkloads.Tests.ps1`](../../../test/scripts/unit/lib/PerformanceWorkloads.Tests.ps1) covers:
  - member access and the numeric type matrix, with an accounting fuzz: every present value is either kept or rejected, exactly once;
  - the catalog contract and its report order;
  - rows of a JSON-round-tripped Core fixture, including event variants, instrumented rows, empty measures and warm calls that lack one of the two timings;
  - runtime notes.
- Mutation target `PerformanceWorkloads`, `Break` 80.

<!-- script-contract:begin -->
## Execution contract

Purpose: Reads one member of a JSON object or dictionary, or returns nothing when it is absent.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

## Startup timer series

The catalogue also reads `Performance[FreshProcessStartup].Samples`: ordinary fresh-process import, first and warm short calls, plus explicit diagnostic short-call totals and eight invocation/storage phase measures. Selectors keep telemetry on/off and FirstCall/WarmCall apart; diagnostic rows carry `Instrumented=true`. A nullable timer is translated into an absent observation, never a zero or malformed numeric sample. Malformed present nonnumeric values still increment Rejected. Save round-trip is inclusive of worker phases.

Review: `Get-QuietPerformanceWorkloadCatalog` maps only declared scalar timer fields; `Get-QuietPerformanceWorkloadRows` keeps their measurement method. No business objects or files are queried. Unit fixtures check distinct first/warm and telemetry arms, missing values, generated numeric rejection and catalogue order. Verdict: diagnostic wall timers support localization, not additive CPU attribution or an OS ranking.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
