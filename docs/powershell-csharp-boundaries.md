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

## Third pass: shared limits, caller-side framing and configuration schema

Three pieces of business logic that existed in both languages now have one C# definition. PowerShell keeps parameter binding, error propagation and the cmdlet surface. Error-code strings are unchanged, so the wrappers unwrap the innermost exception message before rethrowing it as a string.

- **Native-request limits.** `RequestLimits` holds the single set of bounds (timeout, drain timeout, read block, terminal dimension, transport, output budget). `FacadeOptionValidator.FirstError` returns the first failing code in the historical order (tokenizer, transport and stream modes, role, limits, timeout, drain timeout, read block, terminal size). `Read-QuietArguments` calls it instead of repeating the checks, and `InvocationRequest` uses the same constants. Name membership stays case-insensitive, as the former `-in` test was. Side effects: the managed assembly is now loaded when `-Script` is exported, and the working directory is resolved after the limit checks.
- **Isolated-engine client framing.** `ProtocolClient.ExchangeAsync` is the caller-side counterpart of `Protocol`: it validates request sizes, writes the length-prefixed frame, reads and validates exactly one reply, and reports exact wire sizes for the protocol counters. `Send-QuietRequest` uses it only in Process mode. Request-id and version matching and the `EngineCommunicationFailed` wrapper stay in PowerShell, whose type-name suffix is now `InvalidDataException` for framing errors. The client runs in the PowerShell process, adds no IPC and serializes no business object.
- **Configuration schema.** `ConfigurationSchema` defines the closed key set, defaults, ranges, section list, scalar validation (enum, boolean, integer, number, path, optional path, recall size) and the generated template. `Get-QuietConfigurationSchema` exposes the rules as an ordered map, `ConvertTo-QuietConfigurationValue` and `Resolve-QuietConfigurationPath` delegate, and `New-QuietCliConfiguration` writes `RenderTemplate()`. YAML reading, the session snapshot and the cmdlets stay in PowerShell. Template scalars match the former `ConvertTo-Json -Compress` rendering (relaxed escaping, integral doubles keep `.0`).

### Reviewed and kept in PowerShell

- **Gain paging client.** The integrated path returns CLR DTOs while the isolated path returns JSON objects, and each page uses its own per-exchange deadline. Moving the loop needs either a second code path or a full C# state machine for little gain.
- **Engine integrity bootstrap.** Manifest and SHA-256 checks must run before the assembly can be trusted, so the minimal PowerShell bootstrap cannot move. Only the post-load resource assertions could, with little value.
- **Delivery accounting.** Hashing and size counting already use .NET APIs. Tokenizer assemblies are loaded from `resources/`, and moving that would need a private load context and a dependency-lock change.
- **Protocol constants, gain YAML graph normalization and lifecycle transitions.** Small and risky relative to their benefit; not moved.

### Validation

The companion adds 17 independent C# cases: 6 for facade limits (inclusive bounds, just-outside values with stable codes, precedence, case-insensitivity, a seeded generated property and agreement with `InvocationRequest.Validated`), 5 for the protocol client on in-memory streams (server-reader round trip, random read fragmentation, oversized requests, invalid reply lengths, truncation and cancellation) and 6 for the schema (key set, inclusive numeric bounds, a seeded generated range property, enum/boolean/path/recall-size codes, home-prefix path resolution, template shape). A seventh schema case parses the generated template with the product YAML reader and checks every value against its default; it runs in the configuration-delivery campaign. Oracle values are written literally in the tests. Seeds are 20261106, 20261107 and 20261108.

The configuration mutation catalogue replaces the PowerShell mutant `ps-configuration-budget-range` with the C# mutant `configuration-budget-range`, which removes the lower-bound check in `ConfigurationSchema.Convert`. The `Core` suite (56 cases, including the 63 C# cases counted by the wrapper) and the `ConfigurationDelivery` suite with mutations (25 cases, all five C# mutants killed) passed on Windows x64. Other campaigns were not rerun, and Linux and ARM64 execution is not established by these local results.

## Fourth pass: correctness and safety fixes (wave A)

This pass changes no boundary; it fixes defects found by a full audit of Core. Gains are not claimed because none was measured.

- **Recall journal recovery.** An interrupted capture is read up to its checkpointed length strictly. After it, a failing record is discarded as a truncated tail only when the rest of the file is zero bytes (crash or preallocation residue) or when it is the final record with a damaged payload (torn write). Any other failure, including damage inside the checkpoint or before a later record, is still rejected. Previously a zero-filled tail made the whole valid prefix unreadable.
- **Private capture files.** Recall directories, journals, locks, manifests and ZIP transports are created owner-only on Unix (`RecallPrivateFiles`), matching the SQLite database.
- **Atomic publication.** Manifest checkpoints retry a short move failure and delete their unique temporary file on failure. ZIP export writes a unique `.partial` file and renames it. Import builds a staging directory and renames it, so a failed import leaves neither a half-imported identity nor a staging directory.
- **Invocation threading.** `cancelled`, `timedOut`, the first error and the exit code are published with `volatile`/`Volatile`/`Interlocked`; the exit code is a single 64-bit slot, so it cannot be read torn. A snapshot reads each field once. A failing reader or writer can no longer skip the end of the run (output completion, stopwatch) or the disposal of the process and tokens, and `EngineSession.DisposeAsync` releases every owner before rethrowing.
- **Input state.** The `input` reply now carries `Closed` beside `Accepted`, so a closed input fails at once with `InputAlreadyClosed` instead of looping until the process ends. A failed write closes the input.
- **Validation and storage.** NaN and infinite record, output and item limits are rejected with `InvalidLimits`. A failing `ROLLBACK` no longer replaces the original SQLite error (`Database.TryRollback`).
- **PowerShell.** `Get-QuietCliGain` no longer sends a redundant release for a report the engine already released; the unused `ConvertTo-QuietErrorCodes` was removed.

Tests: two new Recall cases (journal tails, atomic export/import and Unix modes), NaN/infinity limit checks, and three Recall mutants (`tail-ignores-checkpoint`, `tail-accepts-garbage`, `tail-accepts-inner-torn-record`). The Core wrapper now expects 65 C# cases.

## Keep the PowerShell boundary deliberate

PowerShell parameter binding, scriptblock execution on the caller runspace, interaction callbacks, nested invocation coordination and references to caller Data remain in PowerShell. Calling those callbacks from a C# background thread changes runspace and identity semantics. A lower interpreter cost does not justify that behavior change.

CI/bootstrap scripts remain engine-independent orchestration. In particular, native C qualification must run without a built product assembly. Moving Ci.Process.ps1 or native test launchers into the product engine would violate that bootstrap contract. Monitoring is a read-only PowerShell terminal UI and remains separate from product execution.

## Validation and measurements

The companion adds six independent C# assertions for UTF-8 splits, delimiter boundaries, byte limits, invalid EOF, source deduplication/root-delivery joins and exact query budgets/missing databases. PowerShell integration covers all aggregate group pages, cleanup beyond the eight-report capacity and the existing native-stream/child/error contracts.

`SecondPass.Tests.ps1` compares the former PowerShell gain implementation with the compiled report on 512 synthetic telemetry events, and compares framing on short records and a long fragmented record. Both implementations must satisfy independently known counts. Three alternating samples report their exact scope, durations, requests and actual pipe bytes. They are mechanism/workload samples, not a universal speed claim. Tests use their private measurement database and the normal visible companion monitor.

Actual stable/preview results, source fingerprints and comparative medians are recorded in [the local validation audit](audits/2026-11-05-csharp-second-pass.md). Both Windows x64 runs passed 73 scenarios with zero failures; Linux/ARM64 execution is not established by these local results.

The ordered migration is qualified in [the final Core-then-Git audit](audits/2026-11-05-core-then-git.md). ARM64/musl execution and public release qualification remain separate from the local Windows/Debian results.
