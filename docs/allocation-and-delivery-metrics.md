# Allocation costs and actual delivery gains

QuietCli reports two different quantities. Native-output reduction compares actual UTF-8 delivery bytes with associated native business-source bytes. Managed allocation costs describe memory allocated while executing the caller-local invocation and its `Complete` callback. Allocations are not retained object size, serialized output size, token savings or a percentage reduction against stdout/stderr.

## Caller-thread allocation intervals

Both integrated and isolated hosting use the compatible caller-local C# `AllocationMeter`. It samples `GC.GetAllocatedBytesForCurrentThread()` without forcing collection, traversing `Data`, evaluating business getters or serializing an object. `Complete` may return an entirely new `[pscustomobject]`, an existing reference, an array or a lazy object; measurement preserves that behavior.

```powershell
$r = quiet -AsObject -C analysis -Complete {
    param($runtime)
    [pscustomobject]@{ Count = 42; Buffer = [byte[]]::new(65536) }
} executable arguments

$r.Measurement.Allocation
$r.Measurement.CompleteAllocation
Get-QuietCliGain -C analysis -AsObject
```

`Measurement.Allocation` starts after compatible helper loading, before runtime construction. It ends after constructing and freezing the final result envelope, before saving its own telemetry, releasing the native session and serializing a delivery. Facade argument parsing and business arguments created before the call are outside this interval. It includes allocations on the calling thread for callbacks, adapters, temporary values and nested synchronous invocations. Background C# workers, native processes and caller consumption after return are outside its scope. Cold JIT/initialization and instrumentation overhead can affect individual samples; this is an observed interval rather than an object-size estimate.

`Measurement.CompleteAllocation` starts immediately before the `Complete` dispatch and ends in `finally`, including failed callbacks. It includes callback invocation, result adaptation, temporary objects and any new business value. It is null if no `Complete` callback ran. These bytes are already included in the invocation interval: never add the two counters. A root interval similarly includes nested synchronous invocations on its calling thread.

Each sample contains `AllocatedBytes`, `StartThreadId`, `EndThreadId` and `Status`. A changed thread gives `Status = ThreadChanged` and `AllocatedBytes = null`, never zero. All four fields are persisted in the SQLite row under `Allocation` or `CompleteAllocation`, for invocation events and any later delivery event. This explains unknown sizes at row level, independently of the aggregate report.

The application does not change the caller's runspace, apartment state or synchronization context for measurement. PowerShell calls the engine using `.GetAwaiter().GetResult()` and executes callbacks on its caller runspace; async engine work can use other threads. Matching endpoint IDs delimit this caller-thread measurement, not allocation attribution for work spawned on other threads.

## SQLite and reports

The PowerShell facade supplies explicit identity and metadata references. `MeasurementTelemetry` projects execution fields and diagnostic codes in caller-local C#, never accepting `Result.Data`. The shared C# `MeasurementStore` validates closed records and serializes only their metadata to SQLite on its private sequential worker. `QUIETCLI2_TRACKING=0` disables persistence, while caller-local allocation and delivery measurements remain available.

`Get-QuietCliGain` aggregates metadata in C#. `RootInvocationAllocatedBytes` is known only when every selected root has a measured sample and the report is complete. `AllocationMeasuredRoots` exposes coverage; historical rows without samples remain unknown. Root-only aggregation avoids adding child samples a second time.

`RootCompleteAllocatedBytes` sums the selected root `Complete` samples only when at least one exists, every such sample is measured and the report is complete. `RootCompleteAllocationSamples` and `RootCompleteAllocationMeasuredSamples` expose that coverage. Historical rows cannot prove whether a callback ran. `AllocationThreadChangedRoots` and `RootCompleteAllocationThreadChanges` explicitly explain thread-change gaps. `AllocationScope` states the calling-thread and inclusive accounting rules.

For example, inspect persisted rows without confusing delivery copies with new allocation intervals:

```sql
SELECT id,
       json_extract(payload, '$.Allocation.Status') AS allocation_status,
       json_extract(payload, '$.Allocation.AllocatedBytes') AS allocation_bytes,
       json_extract(payload, '$.Allocation.StartThreadId') AS start_thread,
       json_extract(payload, '$.Allocation.EndThreadId') AS end_thread,
       json_extract(payload, '$.CompleteAllocation.Status') AS complete_status
FROM quiet2_events
WHERE kind = 'invocation';
```

## Serialization-only reduction

An `AsObject` invocation persists native counters and allocation costs but has no delivered byte size or output reduction. A later `Out-QuietResult` or `ConvertTo-QuietJson` measures its actual JSON/YAML bytes and emits a delivery snapshot. Generic PowerShell or third-party serialization outside these functions is not tracked.

All invocation observations remain visible in `BusinessBytesObserved`, `AuxiliaryBytesObserved`, `Invocations` and `Roots`. Gain uses only actual root business deliveries and their associated source snapshots: `SerializedBusinessBytesObserved - RootDeliveryBytes`. Independent object-only roots neither inflate nor invalidate this comparison. Source/analysis incompleteness, missing source counters or delivery sizes, or a truncated report make the reduction unknown. Auxiliary root deliveries and nested deliveries do not enter the business comparison.

The report counts each unique native source once, and every selected actual root delivery once. Repeated serialization therefore adds delivery bytes without duplicating the native baseline; negative reductions are valid. `RootDeliveries`, `SerializedRoots` and `UnserializedRoots` expose business-root coverage; the general `Roots` counter also includes auxiliary invocations. A delayed delivery can be compared even if its original invocation predates the report window, because delivery rows contain their own source/completeness snapshot. Old incomplete delivery rows cannot establish a gain.

## Explicit process-wide diagnostics

`Get-QuietEngine -IncludeAllocations` additionally samples cumulative managed allocation counters for the PowerShell caller and the engine. This opt-in path includes C# background workers. It adds no process-counter sampling to ordinary invocations or ordinary `Get-QuietEngine` calls. Each sample identifies its PID, timestamp, process-wide scope, precision and exclusion of native allocations. The default approximate counter avoids the substantial overhead of the precise variant; `-IncludeAllocations -Precise` explicitly selects that cost for controlled benchmarks.

With integrated hosting the caller and engine are the same process: `Allocations.SharedProcess` is true and both labels refer to the same sample. Never add them. With isolated hosting they have different PIDs and must be compared over independent before/after intervals; reject an interval if either PID changes. Process deltas include other concurrent work, sampling and control overhead. They cannot be attributed exclusively to one callback or subtracted from caller-thread intervals to claim an exact worker cost. These diagnostics are returned explicitly and saved in benchmark reports, not attached to every invocation's SQLite row or included in gain.

```powershell
$before = Get-QuietEngine -IncludeAllocations -Precise
# Run the controlled workload without serializing business Data for measurement.
$after = Get-QuietEngine -IncludeAllocations -Precise
$after.Allocations
```

See the official [GC process-counter documentation](https://learn.microsoft.com/en-us/dotnet/api/system.gc.gettotalallocatedbytes?view=net-10.0) for precision overhead and the exclusion of native allocations. STA controls COM apartment behavior; it does not change these process-counter semantics or pin async continuations. QuietCli does not change apartment state or runspace thread options to collect metrics.

## Focused validation

Run `FrenchExDev2.QuietCli.Core.Tests.PoSh/tools/Invoke-TelemetryQualification.ps1 -Mutation` after the documented workspace build. It uses the shared visible resizing monitor, stores reports outside the checkout and preserves every source mutant and result. The C# baseline covers 256 generated allocation intervals, 256 mixed invocation/delivery scenarios and 512 malformed allocation records with deterministic seeds. SQLite assertions verify persisted thread-change explanations. PowerShell checks new `Complete` objects with 64 KiB, 256 KiB and 1 MiB buffers, business getters that must not run, callback failure, repeated JSON/YAML deliveries and both hosting modes. Six warm process-allocation benchmark samples retain caller/engine PIDs, precision, shared-process identity, native bytes, durations and separate invocation/Complete intervals. The eleven source mutants target counter deltas, thread guards, stable stopping, serialization scope, unknown-size/completeness gates, source totals, thread-change reporting, allocation schema validation, explicit process precision and background-thread inclusion. This bounded catalogue is not exhaustive mutation coverage; local Windows results do not qualify unexecuted platforms.

Five additional PowerShell source mutants check invocation sampling, `Complete` sampling, SQLite persistence, shared-process identity and local delivery reduction against independent observable assertions. Mutants run against owned module copies in fresh processes. The unmodified PowerShell baseline must pass; a missing structured result, crash, invalid source mutation or timeout is an infrastructure failure rather than a killed mutant.

On 6 November 2026, an isolated tree containing the task changes over the existing committed baseline passed all 115 companion scenarios on Windows x64 (48 Core and 67 Git), including 34 nested C# assertions. The independent allocation/gain campaign detected all 16 targeted source mutants. PowerShell used .NET 10 integrated hosting and the pinned .NET 11 isolated engine. Existing concurrent changes to performance reporting and CI were excluded from this isolated validation; these results do not qualify those changes, other platforms or a publication matrix.
