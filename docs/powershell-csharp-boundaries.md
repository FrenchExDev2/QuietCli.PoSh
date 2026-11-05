# Second PowerShell-to-C# pass

This pass reviews production code in Core and Git after integrated .NET 10/11 hosting. File size is not a runtime-cost measurement. The changes target repeated scans and event-row transfers, with comparative samples in the companion suite.

## Moved in this pass

`TextStreamState` now owns strict incremental UTF-8 decoding and text delimiter framing. A linear prefix matcher handles delimiters split between blocks and overlapping prefixes. A mutable unfinished-record buffer replaces repeated string concatenation, suffix copies and rescans. UTF-8 byte limits still exclude a complete delimiter and include an unfinished delimiter fragment. Empty records, Unicode split across byte blocks, strict EOF validation and the final unterminated record remain explicit. Records are yielded lazily; PowerShell still invokes callbacks and preserves their local objects and failure handling.

The framer runs in the PowerShell process in both hosting modes. It adds no IPC, per-record request or business-object serialization. Chunk text, binary events and callback byte-count contracts remain unchanged.

`GainAccumulator` and the SQLite worker now classify invocation/delivery metadata, deduplicate native sources, group counters and establish aggregate completeness. The facade sends filters once and receives counters and aggregate groups. Original event rows no longer cross the facade boundary for Get-QuietCliGain. Raw query remains available for internal diagnostics and the retained performance baseline.

Large scans return small progress continuations so the normal per-exchange deadline still applies rather than timing out an entire million-event scan. Abandoned scans are canceled cooperatively between pages/records. The worker uses a read transaction for a consistent snapshot. Aggregate groups are paginated by encoded size and count; the facade assembles every group without silent truncation. Up to eight unfinished reports can be owned by a session, with cleanup after completion, failure or engine disposal.

In integrated mode these calls are direct method calls with some control JSON in memory, not IPC. In isolated mode this removes original telemetry-row transfers; small progress messages and aggregate-group pages still use IPC. Neither path sends a business object to the engine.

Two accuracy fixes accompany the extraction: an unknown root delivery size stays null, and a total reduction requires delivery identities matching the selected root identities, not merely the same count of distinct identities. Exactly reaching MaxEvents is complete only when no additional selected event exists.

## Completed follow-up and retained boundaries

- Input/lifecycle adapters are now implemented: `input`, `eof`, `cancel`, `resize` and `release` use a closed C# control operation in integrated mode, sharing the isolated dispatcher transitions. PowerShell still chunks input and drains output during back-pressure. Startup and telemetry now also have closed integrated operations; only internal raw queries and bounded rejection diagnostics retain transport JSON. SQLite storage JSON is separate. See [typed control validation](audits/2026-11-05-typed-controls.md) for duplex checks and the measured scope.
- `Contracts.ps1`: caller-local recursive freezing now runs in `CallerMetadata`; PowerShell adapts its own property bags on the caller thread. Detached read-only descendants and explicit cycle rejection are preserved. Business Data is never passed to this helper.
- Git now owns the compiled `GitArguments` and `GitRecords` companion, targeting net10.0 and net11.0. It performs token binding, strict/lossless byte decoding, porcelain-v2 and patch parsing, field grouping, history/tree/worktree mapping and ordinal ref comparison locally. Command routing, version policy, artifact ownership and caller callbacks remain PowerShell-owned. No Git grammar moved into Core.
- `Delivery.ps1`: YAML emission now uses pinned YamlDotNet 18.1.0 from a private assembly context. It receives only the normalized bounded graph; strings are explicitly quoted. Generic projection remains PowerShell-owned because getters/enumerators, dictionary comparers, cycles, omission counts and object identity are observable. AsObject remains outside projection and YAML emission.
- `Registry.ps1`: executable stat and explicit environment cache identity now use `ProbeIdentity`, with collision-safe framing and platform-aware environment names. Version predicates, format matching and probe scriptblocks stay in the registered handler. Comparative tests require one probe per 200 repeated resolutions; no additional native probe is introduced.
- `Scaffold.ps1`: infrequent template/file authoring is primarily orchestration and filesystem work. Moving it for line-count reduction alone has little demonstrated value.

## Keep the PowerShell boundary deliberate

PowerShell parameter binding, scriptblock execution on the caller runspace, interaction callbacks, nested invocation coordination and references to caller Data remain in PowerShell. Calling those callbacks from a C# background thread changes runspace and identity semantics. A lower interpreter cost does not justify that behavior change.

CI/bootstrap scripts remain engine-independent orchestration. In particular, native C qualification must run without a built product assembly. Moving Ci.Process.ps1 or native test launchers into the product engine would violate that bootstrap contract. Monitoring is a read-only PowerShell terminal UI and remains separate from product execution.

## Validation and measurements

The companion adds six independent C# assertions for UTF-8 splits, delimiter boundaries, byte limits, invalid EOF, source deduplication/root-delivery joins and exact query budgets/missing databases. PowerShell integration covers all aggregate group pages, cleanup beyond the eight-report capacity and the existing native-stream/child/error contracts.

`SecondPass.Tests.ps1` compares the former PowerShell gain implementation with the compiled report on 512 synthetic telemetry events, and compares framing on short records and a long fragmented record. Both implementations must satisfy independently known counts. Three alternating samples report their exact scope, durations, requests and actual pipe bytes. They are mechanism/workload samples, not a universal speed claim. Tests use their private measurement database and the normal visible companion monitor.

Actual stable/preview results, source fingerprints and comparative medians are recorded in [the local validation audit](audits/2026-11-05-csharp-second-pass.md). Both Windows x64 runs passed 73 scenarios with zero failures; Linux/ARM64 execution is not established by these local results.

The ordered migration is qualified in [the final Core-then-Git audit](audits/2026-11-05-core-then-git.md). ARM64/musl execution and public release qualification remain separate from the local Windows/Debian results.
