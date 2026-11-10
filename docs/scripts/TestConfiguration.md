# TestConfiguration.ps1

## Purpose

Gives each test worker (a test run, a mutation campaign worker, a profiling probe, etc.) its own
private, disposable configuration (`config.yaml` pointing at its own SQLite telemetry database) that
is completely independent of whatever configuration the *product* (QuietCli engine) would use by
default. The business problem: test/profiling/mutation workers must never share state, a database, or
a configuration directory with each other or with a developer's real QuietCli configuration — doing so
would make concurrent test runs corrupt each other's telemetry or make test runs non-reproducible. It
is dot-sourced (not run standalone) by essentially every test-support/worker script under
`FrenchExDev2.QuietCli.Core.Tests.PoSh` — `ConfigurationDelivery.Tests.ps1`,
`Status.RealProbe.ps1`, `Status.ControlledProbe.ps1`, `Profiler.Target.ps1`,
`tools/Invoke-TelemetryQualification.ps1`, `tools/Telemetry.MutationWorker.ps1`,
`audit/Probe-GalleryInstall.ps1`, `audit/Probe-PublishedGallery.ps1`, `audit/Invoke-AuditWorker.ps1`
— confirmed by grep. It is also dot-sourced by `Invoke-TestWorker.ps1` (line 40), the general worker
entry point used by the container/CI test orchestration (`Invoke-WorkspaceCi.ps1`,
`Invoke-ContainerCi.ps1`, etc.).

## Usage

```
function Initialize-QuietTestConfiguration {
    param([Parameter(Mandatory)][string]$DatabasePath,[string]$Hosting='Auto',[bool]$Enabled=$true)
    ...
}
. (Join-Path $PSScriptRoot '../FrenchExDev2.QuietCli.Core.Tests.PoSh/Configuration.TestSupport.ps1')
```

This file is itself dot-sourced, not invoked with arguments; it defines one function and immediately
dot-sources a second file as a side effect of being loaded.

- `Initialize-QuietTestConfiguration -DatabasePath <string> (mandatory) [-Hosting <string>='Auto']
  [-Enabled <bool>=$true]`
  - `DatabasePath` (string, mandatory) — the private SQLite database path owned by the calling worker.
  - `Hosting` (string, optional, default `'Auto'`) — explicit engine hosting mode for the test run.
  - `Enabled` (bool, optional, default `$true`) — whether the worker persists telemetry at all.

Example:

```powershell
. (Join-Path $PSScriptRoot 'scripts/TestConfiguration.ps1')
Initialize-QuietTestConfiguration -DatabasePath (Join-Path $run 'telemetry.sqlite') -Hosting InProcess
```

## Dependencies

- Dot-sources `../FrenchExDev2.QuietCli.Core.Tests.PoSh/Configuration.TestSupport.ps1` (line 21)
  unconditionally as part of being loaded, which defines `global:Get-QuietTestConfiguration` — a
  function that reaches into the already-imported `FrenchExDev2.QuietCli.Core.PoSh` module's private
  scope (`& $core {Get-QuietConfigurationSnapshot}`) to expose its internal configuration snapshot to
  test assertions. This means dot-sourcing `TestConfiguration.ps1` has a hard, path-relative dependency
  on a sibling test-support project directory existing one level up from `scripts/` — it is not
  self-contained within the `scripts/` folder.
- No external process is shelled out to.
- Filesystem assumption: none pre-existing; it creates its own `config-<dbname>` directory next to the
  database path (line 13-14).
- Environment: sets `$env:QUIETCLI_CONFIG_DIRECTORY` (line 19) as a process-global side effect, which
  is presumably how the QuietCli engine discovers which configuration directory to load — meaning any
  code that subsequently imports/initializes the engine in the same process is affected by this call.

## Side effects

- Creates a new directory `config-<DatabasePath-basename-without-extension>` next to the database path
  (lines 13-14).
- Writes `config.yaml` into that directory (line 18), containing the database path (as a JSON-escaped
  string literal embedded in YAML, line 15) and the hosting/enabled settings — using the async
  `WriteAllTextAsync(...).GetAwaiter().GetResult()` pattern.
- Mutates the current process's `$env:QUIETCLI_CONFIG_DIRECTORY` (line 19) — a global, not
  worker-scoped, side effect; calling this function twice in the same process (e.g. from two
  sequential test phases) silently overwrites the previous call's effective configuration directory
  for any code that reads the environment variable afterward.

## Findings

- DESIGN: `$env:QUIETCLI_CONFIG_DIRECTORY` is a process-wide global. If a single PowerShell process
  ever needs to run two independent "workers" concurrently or sequentially-but-with-overlap (e.g. a
  test harness that spins up a background job in the same process, or parallel Pester containers in
  one runspace), this global would create cross-talk between them — directly contradicting the stated
  purpose ("owned", "independent of product imports", "Private database belonging to the worker").
  The isolation this function provides is per-process, not per-call, despite the per-call `DatabasePath`
  parameter suggesting finer granularity.
- DESIGN: the YAML is hand-assembled via string interpolation (`"schemaVersion: 1`ntelemetry:`n
  database: $databaseLiteral..."`, line 17) rather than through a YAML serialization library. The
  database path value is at least escaped via `ConvertTo-Json -Compress` (line 15) to produce a
  JSON-safe quoted string (which happens to also be valid inline YAML), which is a reasonable minimal
  safeguard, but `Hosting` and `Enabled` are interpolated completely unescaped (lines 16-17) — if
  `Hosting` ever became attacker- or widely-caller-controlled (today it is caller-trusted,
  developer-supplied) a value containing a newline or colon could corrupt the YAML structure. Low risk
  today given all current call sites pass literal constants, but it is hand-rolled serialization
  instead of a proper writer, which is fragile by construction.
- CONVENTION: no violation — this file does correctly use the async
  `WriteAllTextAsync(...).GetAwaiter().GetResult()` pattern (line 18), and forces UTF-8 without BOM.
- DESIGN: the file does two unrelated things on load — defines a function, *and* unconditionally
  dot-sources another file as a side effect of being dot-sourced itself (line 21, outside any function
  body). This makes the file's name ("TestConfiguration.ps1") undersell what it actually does: callers
  dot-sourcing it for `Initialize-QuietTestConfiguration` also get `global:Get-QuietTestConfiguration`
  injected into the global scope as an unannounced side effect — a SOLID/single-responsibility smell;
  the file mixes "build a config file" with "reach into module internals for test assertions," two
  different responsibilities bundled into one load.
- Testability: ironically, this *is* the test-support infrastructure, so there is no separate test file
  for it — it's exercised indirectly by every test suite that relies on it functioning correctly
  (`ConfigurationDelivery.Tests.ps1` is the closest thing to a direct consumer/validator, given its
  name). No dedicated unit test isolates `Initialize-QuietTestConfiguration`'s YAML-writing logic from
  the rest of a real test run.
- No security concern: purely local, developer/CI-trusted inputs; the YAML-injection concern above is
  theoretical given current callers, not an active vulnerability.

## Verdict

Functionally adequate for the current single-worker-per-process usage pattern, but the process-global
`$env:QUIETCLI_CONFIG_DIRECTORY` is a latent correctness risk that contradicts the "owned,
worker-private" framing in its own doc comment — the highest-priority fix would be making the
configuration directory discoverable by the engine through an explicit parameter/handle rather than a
mutable process environment variable, so two configurations can coexist safely in one process.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Creates an owned YAML configuration for a test worker, independent of product imports.

Boundary: **Library**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
