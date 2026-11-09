# Privacy and integrity internals

[Back to the documentation index](README.md) · [QuietCli overview](../README.md)

The [Core README's "Limits, integrity and privacy" section](../FrenchExDev2.QuietCli.Core.PoSh/README.md#limits-integrity-and-privacy) states the contract in one paragraph per mechanism. This guide traces each mechanism to the code that implements it, then proposes how a companion module could plug into it without forking Core. Related: [Measurements and privacy](../README-measurements.md), [PowerShell and C# boundaries](README-powershell-csharp-boundaries.md), [Companion modules](../README-modules.md).

## 1. Timeouts that turn an unfinished exchange into a known outcome

Two independent deadlines exist, and they bound different failures:

- **`-DrainTimeoutSeconds`** (`execution.drainTimeoutSeconds`, default 30 s) bounds how long the engine waits for EOF on stdout/stderr *after the native process has already exited*. It is validated against `RequestLimits.MinDrainTimeoutSeconds`/`MaxDrainTimeoutSeconds` (0.05–300 s) in `RequestLimits.cs` and carried end-to-end through `InvocationRequest.DrainTimeoutSeconds` (`InvocationRequest.cs`). A cutoff here does not mean the process failed — it means the *source* is marked incomplete (`Completeness.Source=false`) even though the process itself finished. This is the case the README calls out explicitly: a drain cutoff makes the source incomplete "even if the main process has already finished".
- **`engine.ipcTimeoutSeconds`** (default 30 s, same 0.05–300 s range) bounds *each* exchange between the PowerShell facade and the engine — hello, a request/reply, shutdown. It is read once per cmdlet through `EngineCommands.IpcTimeout` (`engine\Cmdlets\EngineCommands.cs:10`) and enforced on the wire in `EngineConnection.cs:176`, which throws `InvalidOperationException("InvalidIpcTimeout")` outside that range before any exchange is attempted.

The distinction matters when you design a caller script: a drain cutoff is a *data-completeness* signal (check `Completeness.Source`), an IPC timeout is a *transport* failure (the owned engine is closed, and an unconfirmed startup's effect stays unknown — the call is never silently retried). A new independent root call may start a fresh engine; it does not resume the interrupted one.

## 2. Every read is projected through a closed DTO, not raw storage

`MeasurementProjection.Read` (`engine\MeasurementProjection.cs:13`) is the single choke point every stored telemetry row passes through before anything PowerShell-visible is built from it (`Get-QuietCliGain`'s report, for example). It:

1. Parses the stored JSON with `MaxDepth = 64` — an attacker-controlled or corrupted payload cannot blow the stack through nesting.
2. Walks it with `Project(node, typeof(MeasurementRecord))`, a reflection-driven copier that only emits properties declared on `MeasurementRecord` (`engine\MeasurementModels.cs:113`) — `InvocationId`, `Context`, `Command`, `Outcome`, `Error`, `Sources`, token/allocation counters, and so on. Anything not on that record — a legacy `Message` field, a free-form `Data` bag — is silently dropped, never surfaced.
3. Specifically sanitizes `Code`, `Phase` and `Error` string values: a value is kept only if it is ≤ 64 characters and matches `[A-Za-z0-9_.-]+`; anything else (an old free-text exception message, for instance) becomes the literal string `"LegacyDiagnostic"` — see the regex/length guard inline in `Project` (`MeasurementProjection.cs:62-64`).

This is read-time projection: it does not change what is on disk. It guarantees that *reading* an old or malformed row can never leak a raw exception message, no matter how it got into SQLite.

## 3. `Repair-QuietCliMeasurementPrivacy` is the one-shot, irreversible rewrite

The cmdlet (`RepairQuietCliMeasurementPrivacyCommand`, `engine\Cmdlets\GainCommands.cs:220`) is declared `SupportsShouldProcess` with `ConfirmImpact = High`:

- `-WhatIf` resolves the target database name from `QuietSession.Engine?.Database` or the `telemetry.database` setting — it **never starts an engine**, so previewing the operation has zero side effects beyond reading configuration.
- Without `-WhatIf` (and after `ShouldProcess` confirms), it sends `{ Action = "scrub", Confirmed = true }` to the engine, which runs `MeasurementProjection.Scrub(database)` (`MeasurementProjection.cs:21`):
  - `PRAGMA secure_delete=ON` so SQLite overwrites freed pages instead of leaving old bytes recoverable from the file.
  - A single `BEGIN IMMEDIATE` transaction wraps the whole pass; any exception triggers `TryRollback()` before rethrowing, so a failed scrub never leaves a half-rewritten table.
  - Rows are paged 16 at a time (`SELECT id,payload FROM quiet2_events WHERE id>? ORDER BY id LIMIT 16`) rather than loaded in bulk — the table can be scrubbed without a single huge in-memory read.
  - Each row is re-projected through the **same** `Read()` used for ordinary reads, then compared with `JsonElement.DeepEquals` against the original. Only rows that actually differ get an `UPDATE`; the returned count (`changed`) is exactly the number of rewritten rows, not the number scanned.

The practical effect: `Repair-QuietCliMeasurementPrivacy` does not add new redaction rules — it just applies rule #2's projection *permanently and physically* to history that predates a safer projection, instead of only at read time. That is also why the README is explicit that it "does not guarantee physical erasure from backups or storage media": `secure_delete` only addresses the live database file's freed pages.

## 4. Nothing loads until its bytes are proven to match the lock file

`ResourceVerifier.VerifyAsync` (`engine\ResourceVerifier.cs:39`) runs before the engine starts and before a managed resource (YAML, tokenizer) loads:

- The inventory comes from `resources/dependencies.lock.json`, parsed once and re-parsed only if the file's length/mtime stamp changes (`LoadInventory`).
- Every path is checked against `^resources/[A-Za-z0-9_./-]+$` and rejected if it contains a `..` segment (`SafePath`) — the manifest cannot be used to point outside `resources/`.
- For a platform-specific check (no explicit `relativePath`), entries are filtered to the current `RuntimeIdentifier` via the `PlatformPath` regex (`^resources/(?:runtime/runtimes|transport)/<RID>/`); an unrecognized platform falls back to verifying *everything* rather than silently skipping the check.
- Each file is SHA-256 hashed and compared byte-for-byte against the manifest's expected digest (`ResourceVerifier.cs:49-51`); a mismatch throws `InvalidDataException("DependencyIntegrityFailed: <path>")`. A `(length, mtime, expectedHash)` stamp is memoized per process so a file that already passed in this process is not re-hashed on every call.

The explicit caveat in the README — "a checksum proves neither an author's identity nor the absence of known vulnerabilities" — is the honest boundary of what this buys you: tamper/corruption detection against the pinned manifest, not supply-chain attestation.

## 5. Build staleness is a separate, test-time check

The build manifest linking C# sources, SDK, protocol and compiled files is a different mechanism from `dependencies.lock.json`: it is enforced by the test suite (including with `-SkipBuild`), not by `ResourceVerifier` at runtime. `protocol.json` is the shared limits file both the C# engine and the PowerShell facade read, so the two sides cannot silently drift. See [tests and qualification](../README-qualification.md) for how staleness rejection is exercised; this guide does not re-trace that path.

## Where a developer can already turn a knob

Everything in the table below is a supported, documented extension point today — no Core change needed:

| Need | Knob | Where |
| --- | --- | --- |
| Tolerate a slower draining native process | `-DrainTimeoutSeconds` per call, or `execution.drainTimeoutSeconds` in YAML | per-invocation parameter or `~/.quietcli/config.yaml` |
| Tolerate a slower/faster engine round-trip | `engine.ipcTimeoutSeconds` | YAML, 0.05–300 s |
| Disable telemetry writes entirely (nothing to scrub later) | `telemetry.enabled: false` | YAML |
| Point the scrub/report at a specific database | `telemetry.database` | YAML |
| Preview a scrub without side effects | `Repair-QuietCliMeasurementPrivacy -WhatIf` | any caller script |
| Verify one specific managed resource before loading it yourself | `ResourceVerifier.Verify(root, relativePath)` | companion module C# code |

## Where there is genuinely no plug point yet

Two pieces are **hardcoded**, not configurable, and that is a real gap against this repository's own SOLID/DRY/modular rules (`AGENTS.md`):

- `MeasurementProjection` is `internal static` and always projects through `typeof(MeasurementRecord)`. A companion module (Git, or a future one) cannot register its own closed DTO, and cannot add a field to the allowlist without editing Core.
- `ResourceVerifier` always loads `resources/dependencies.lock.json` under `QuietSession.Root`. A companion module that ships its own native resources (Git already does, for its platform-specific apphosts) has no registered inventory of its own — it either reuses Core's manifest (if its files happen to be listed there) or is unverified.

Neither gap is a bug today — Core's own contract never promised extensibility here — but both block the stated goal of giving a developer "a way to plug their own script in" for privacy or integrity without forking `FrenchExDev2.QuietCli.Core.PoSh`.

## A proposed extension design, consistent with the existing companion-module pattern

Core already has exactly one precedent for "a companion module registers something, Core's loop stays unchanged and just asks a registry": `Register-QuietHandler` / `Get-QuietHandler` / `Unregister-QuietHandler` (see [companion modules](../README-modules.md)). The same shape covers both gaps above without duplicating logic (DRY) and without widening Core's responsibility (SOLID's single-responsibility/open-closed principles):

1. **A privacy-projection registry, mirrored on the handler registry.**
   Add `Register-QuietPrivacyProjection -ModuleId <id> -Type [MyCompanion.SafeRecord]`, backed by a small `PrivacyProjectionRegistry` next to the existing handler registry. `MeasurementProjection.Scrub` and `.Read` stay exactly as they are — same transaction, same paging, same `DeepEquals` comparison — except the projection type is resolved per row from a `ModuleId`/`HandlerId` tag that rows already carry (`MeasurementRecord.HandlerId`), falling back to `MeasurementRecord` for rows with no registered module. Core's loop does not grow a branch per module; it stays open for extension, closed for modification.
   - Keep the type itself a closed DTO (a `sealed record` with only value-type/string/array properties), exactly like `MeasurementRecord` — this is what makes the allowlist mechanical (reflection over declared properties) rather than a maintained string list. Do **not** expose a configurable "extra allowed field names" YAML setting: that would let configuration — not a reviewed, compiled type — decide what counts as safe, which quietly weakens the exact guarantee this document is about.
   - The `Code`/`Phase`/`Error` sanitization regex stays in Core and applies uniformly to every registered projection. It is a cross-cutting security invariant, not business logic — the same boundary already drawn in [PowerShell and C# boundaries](README-powershell-csharp-boundaries.md) between what moves into a companion module and what stays shared.

2. **A resource-inventory registry for `ResourceVerifier`.**
   `ResourceVerifier.VerifyAsync` already accepts an explicit `root` and `relativePath` — it is *almost* reusable as-is. Add `Register-QuietResourceInventory -Root <companionModuleRoot>` so a companion module's own `resources/dependencies.lock.json` (with its own apphosts/assemblies) is verified the same way, with the same path-traversal and platform-filter rules, instead of requiring the companion to either smuggle entries into Core's manifest or skip verification. No change to the hashing or memoization logic — only to where the manifest is looked up.

3. **Why type registration, not a config flag, for both.** A YAML-driven allowlist or a YAML-driven "skip verification for path X" would be the lowest-effort extension, but it moves the decision of what is safe/trusted out of reviewed, compiled code and into a text file an operator can edit without a build — which is precisely the class of weakening this document's "Limits, integrity and privacy" section exists to prevent. Registration of a type or a root keeps the decision in code that ships through the same review and test gates as Core itself.

This is a design proposal, not a shipped API — nothing above exists in the codebase yet. Treat it as the starting point if/when a companion module actually needs its own privacy or integrity surface; until then, the table in the previous section is what is actually available to reach for.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
