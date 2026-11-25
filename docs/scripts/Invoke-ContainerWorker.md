# Invoke-ContainerWorker.ps1

<!-- script-source:begin -->
Source file: [`Invoke-ContainerWorker.ps1`](../../scripts/Invoke-ContainerWorker.ps1)
<!-- script-source:end -->

The dynamic `Suite` block precedes executable imports so PowerShell binds companion selection before
execution. The layout campaign checks real Core, Git, Vagrant and Mutation bindings with `-WhatIf`.
The independent native probe uses the grouped Core test path inside `/workspace/src/Core/test/`.
The transport-origin receipt validates binaries for the requested suite's dependency closure. A
Core or Vagrant run does not require an unbuilt Git parser merely because its source manifest exists.

`-Case` forwards a development-only Core wildcard to `Invoke-WorkspaceCi.ps1`. The guest
retains partial-run metadata. It is rejected with other suites or `-GitHubActions`, keeping
the hosted qualification entry point unfiltered.

For PowerShell test suites, the driver verifies the pinned Pester archive on the host and copies it into the guest workspace cache before starting the network-isolated container. With `QUIETCLI_TEST_TOOLS_OFFLINE=1` the host also requires a cached archive. The guest always initializes Pester in offline mode and verifies the archive again. The standalone native mutation path stages its native inputs independently.

Copying the retained guest report uses TimeoutSeconds rather than a fixed 60-second limit;
the host launcher still bounds the entire run, including transfer and cleanup.
The monitor keeps the last readable progress when a live status copy contains incomplete JSON.
Qualification still requires the completed guest report and its confirmed exit status.

Runtime selection follows the [shared environment contract](../ci/environment.md): explicit argument, checkout dotenv key, then Podman-first application discovery on Windows and Linux. Initialize-CiEnvironment.ps1 generates deterministic Local/GitHub presets.

Before container creation, the worker logs the requested image reference, resolved immutable image
ID, expected guest RID and owned container name. Compare this with `CI image selection` from the image
builder to distinguish a verified cache hit from a new build and confirm which image the tests use.

`-ContainerRuntime podman|docker` is optional. Empty reads checkout `.env`, then discovers Podman before Docker on Windows and Linux through Resolve-QuietVirtEngine;
the GitHub fallback supplies `docker` and `-GitHubActions` to execute `Invoke-GitHubCi.ps1` directly
inside the guest. No local desktop launcher is started in that GitHub path. `-TimeoutSeconds`
defaults to 360 for existing callers; GitHub supplies its explicit guest deadline through its entry.

## Purpose

The actual containerized execution logic behind `Invoke-ContainerCi.ps1`: stages explicit source
directories (scripts, build config, GitHub workflows, every discovered workspace project, or — for the
`Mutation` suite — just the native C sources and their test harness) into a private, networkless Docker/Podman
container, runs the selected test-suite entrypoint (`Invoke-WorkspaceCi.ps1` normally, or
`Probe-Independent.ps1` for the `Mutation` suite) as the container's entrypoint, polls for progress, and
retrieves the full `artifacts/tests/container-run` report tree back to the host. It solves the problem of
running the companion test suites (and the native PTY mutation/fuzz campaign) inside a specific
Linux distribution/architecture with no network access and bounded memory, while reporting live progress
back to the host-side monitor. It is invoked by `Invoke-ContainerCi.ps1` as a background `pwsh -File`
process.

`ContainerInputs.ps1` owns ordinary staging, including documentation, root credits and restored NuGet
packages selected from host assets files. `NUGET_PACKAGES` points to the staged cache, so mutation
builds need no guest network. Native-only campaign staging remains restricted. Alpine PowerShell
uses the separately checksum-pinned Microsoft musl runtime under `/opt/pwsh-runtime`; the SDK keeps
its own root. This preserves strict native RID checks instead of accepting distro-specific aliases.

Root SDK/package inputs accompany the discovered projects without an internal workspace lock.
The transport-origin receipt retains the host's available Git revision/tree, dirty state and
observed source hashes, since the networkless guest does not receive Git internals.

## Usage

Parameters:
- `-WorkspaceRoot` (string, **mandatory**).
- `-RunDirectory` (string, **mandatory**).
- `-Image` (string, **mandatory**).
- `-Platform` (string, **mandatory**) — note: declared as plain `[string]`, not `[ValidateSet('alpine','debian')]` here, unlike the launcher (`Invoke-ContainerCi.ps1`) which does constrain it (see Findings).
- `-ExpectedRuntimeIdentifier` (string, optional).
- `-SkipTty` (switch, optional) — incompatible with `-Suite Mutation` (throws at line 76).
- `-Profiler` / `-ProfilerModulePath` / `-ClrProfilerPath` (switch/string/string, optional) — stages a pinned profiler cache into the container (lines 78–86) and copies its tool receipt back to the host if present.
- `-Suite` — dynamic parameter (lines 28–32), same pattern as `Invoke-ContainerCi.ps1`; defaults to `'All'`.
- `-MaxConcurrency` (`int`, `1..32`, default `min(4, processor count)`) — forwarded to the guest launcher and bounds parallel-safe internal test campaigns.

Example (internal invocation shape):
```powershell
pwsh -File ./scripts/Invoke-ContainerWorker.ps1 -WorkspaceRoot C:\repo -RunDirectory C:\run\ctr-1 -Image quietcli2-debian:local -Platform debian -Suite Core
```

## Dependencies

- Dot-sources `WorkspaceProjects.ps1` (dynamicparam) and `Common.ps1` (line 35).
- Calls `Get-QuietWorkspaceTestSuites $WorkspaceRoot` (line 39) to resolve suite-to-project mapping for status reporting.
- Native tool: the resolved Docker/Podman application (`image inspect`, `create`, `cp`, `start`, `inspect`, `rm`) via `Invoke-WorkspaceNative`/`Invoke-CiProcess`.
- For the `Mutation` suite, dot-sources `Assert-PtyQualification.ps1` (line 126) and calls `Assert-PtyQualification $summary`.
- Filesystem: stages a large set of directories depending on `-Suite` (lines 47, 58–63) — either `scripts`, `build`, `.github/containers`, `.github/workflows`, plus every project in `(Get-QuietWorkspaceProjects $WorkspaceRoot).Path`, or (for `Mutation`) just `src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/native`, `src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/resources/transport`, `src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests`.

## Side effects

- Writes `status.json` repeatedly as a progress heartbeat, including guest-reported `Passed`/`Failed`/`Case` counters pulled every 2 seconds via the selected engine cp command of the guest's own `status.json` (lines 98–106).
- Creates and (in `finally`) force-removes an owned, networkless container (`quietcli2-<owner-prefix>`, memory-limited to `1g`/`1g` swap for `Mutation` suite only, line 87).
- For `Mutation`: asserts (line 62) that no `.dll`/`.csproj`/`.psd1`/`.psm1` file exists in the staged tree, throwing `'NativeStageMustNotContainProductBuildsOrModules'` if any are found — an explicit independence guard ensuring the native mutation campaign cannot accidentally be influenced by a pre-built product module.
- Writes `bootstrap.json` (line 63, Mutation) or `transport-origin.json` (line 66, non-Mutation) recording source identity/hashes.
- Copies the full guest `artifacts/tests/container-run` tree back to `$RunDirectory/guest` (line 112).
- Copies the guest suite summaries into the host `summary.json`, so the shared failure reporter can show the actual failing cases instead of an empty `0/0` diagnostic.
- Throws on numerous specific conditions: `'PreparedImageIdentityUnavailable'`, `'GuestTestDeadlineExceeded'` (360s hardcoded deadline, line 95), `'GuestExitCodeUnconfirmed'`, `'GuestExitedNonzeroAfterSuccessReport'` (line 118 — cross-checks the guest's self-reported success against its actual process exit code, a good consistency check), `'GuestArchitectureMismatch'`, `'GuestRuntimeDoesNotMatchRequestedPlatform'`, `'NativeIndependenceUnconfirmed'` (line 129, Mutation only).

## Findings

- DESIGN: `-Platform` is declared as a plain `[string]` with no `ValidateSet` in this worker (line 27), while the public launcher `Invoke-ContainerCi.ps1` constrains it to `[ValidateSet('alpine','debian')]`. Since this worker is only ever invoked by that launcher with an already-validated value, this is low risk in practice, but it means the worker itself has no defense-in-depth if ever invoked directly (e.g. for debugging) with an arbitrary string — later logic (line 121: `$expected = if ($Platform -eq 'alpine') {...} else {...}`) silently treats *any* non-`'alpine'` value as the debian pattern, which could mask a typo'd platform name as a false-negative architecture mismatch rather than an explicit "unknown platform" error.
- Hardcoded 360-second guest-test deadline (line 95, `$deadline=[DateTimeOffset]::UtcNow.AddSeconds(360)`) is not parameterized, unlike other sibling scripts that expose `-TimeoutSeconds`; a caller cannot extend this for a legitimately slower full-suite run inside a resource-constrained container (notably the `Mutation` suite is additionally memory-limited to 1GB, line 87, which could make a 360s ceiling tight for a real fuzzing/mutation campaign depending on corpus size) — this combination (fixed 1GB memory + fixed 360s timeout for `Mutation`) is a plausible source of flaky, resource-starved failures with no way to tune it from the call site.
- The guest-progress polling block (lines 98–106) treats a failed container cp of `status.json` as silently ignorable (`if($progress.Outcome -eq 'Success'){...}` with no `else`), meaning transient inability to read guest progress produces no diagnostic trace at all for that poll cycle — minor, since the loop retries every 2 seconds, but means a prolonged guest-side status write failure would show as "no progress updates" rather than a reported error.
- Good positive: the independence guard for `Mutation` (lines 61–63, 129) and the guest-exit-vs-report cross-check (line 118) are both genuinely careful, specific invariant checks that catch real classes of bugs (a stale pre-built module leaking into a supposedly from-source native build; a guest falsely reporting success while actually exiting non-zero).
- No companion Pester test found for `Invoke-ContainerWorker.ps1` itself (the native mutation pipeline it stages has its own `native-tests` suite, which is a different, out-of-scope test target).

## Verdict

Fit for purpose, with careful cross-checks for the higher-risk `Mutation` suite. The highest-priority improvement is making the 360-second guest-test deadline (line 95) and the `Mutation` suite's 1GB memory limit (line 87) configurable, since their current fixed combination risks flaky failures on larger fuzz/mutation workloads with no way to tune it without editing this script.

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [Assert-PtyQualification.psm1](lib/Assert-PtyQualification.md), [Common.psm1](lib/Common.md), [ContainerInputs.psm1](lib/ContainerInputs.md), [WorkspaceProjects.psm1](lib/WorkspaceProjects.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Stages explicit sources and built artifacts into a private, networkless container.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/Invoke-ContainerWorker.ps1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
