# Invoke-ContainerCi.ps1

For a focused Linux regression, use `-Suite Core -Case '*commit workspace*'`. The wildcard
is forwarded to the guest's existing case selector; its report remains partial and cannot
qualify a release. Other suites reject `-Case`. `-TimeoutSeconds` also bounds the guest worker.

Runtime selection follows the [shared environment contract](../ci/environment.md): explicit argument, checkout dotenv key, then Podman-first application discovery on Windows and Linux. Initialize-CiEnvironment.ps1 generates deterministic Local/GitHub presets.

This is the local workstation container launcher. `-ContainerRuntime docker|podman` explicitly
selects the local engine; when empty, Resolve-QuietVirtEngine reads the checkout dotenv key before
discovering Podman then Docker on Windows and Linux. It opens the
same required local monitor for either engine and forwards the selection to the shared transport.
It never installs an engine or falls back after a selected engine fails. GitHub uses its dedicated entry point.

```powershell
./scripts/Invoke-ContainerCi.ps1 -Image $image.Image -Platform debian -Suite Core -ExpectedRuntimeIdentifier linux-x64 -ContainerRuntime docker
```

## Purpose

Launches a Docker/Podman CI run of the full test suites (or a selected companion scope) against an
already-prepared container image, with a visible monitor window on the Windows host, by starting
`Invoke-ContainerWorker.ps1` in the background and (unless `-Headless`) `Watch-Tests.ps1` as a separate
monitor process. This exists so a developer/CI step can validate behavior inside a specific Linux
distribution/architecture (alpine/debian) without installing anything on the host beyond the selected Docker/Podman engine, while
still getting a live, visible test-run monitor as required by the repo's test-run policy. It is invoked
by `Invoke-ColdStartMatrix.ps1`'s sibling cold-start flow only indirectly through its own pattern
(`Invoke-ContainerColdStart.ps1`, a separate script) — no script in `scripts/` was found calling
`Invoke-ContainerCi.ps1` itself by name via grep, meaning it is presently a standalone/manual or
CI-workflow-invoked entry point (referenced conceptually in `docs/ci/linux-images.md` and related docs).

## Usage

Parameters:
- `-WorkspaceRoot` (string, optional, default `(Split-Path $PSScriptRoot -Parent)`).
- `-Image` (string, **mandatory**) — prepared local image containing PowerShell, .NET 11 RC and Git.
- `-Platform` (string, optional, `[ValidateSet('alpine','debian')]`) — platform label for the monitor.
- `-Headless` (switch, optional) — CI-only mode without a desktop window.
- `-TimeoutSeconds` (int, optional, `[ValidateRange(1,7200)]`, default `900`) — maximum worker duration including staging/cleanup.
- `-ExpectedRuntimeIdentifier` (string, optional, `[ValidatePattern('^linux-(musl-)?(x64|arm64)$')]`) — required guest RID.
- `-SkipTty` (switch, optional) — excludes native TTY/PTY execution (incompatible with `-Suite Mutation`, line 51).
- `-Profiler` / `-ProfilerModulePath` / `-ClrProfilerPath` (switch/string/string, optional) — enables a separate pinned profiling pass; requires `-Suite` in `Core`/`All`/`Integration` (line 39) and auto-prepares a pinned tool cache via `Initialize-Profilers.ps1` if paths are omitted (line 41).
- `-Suite` — a **dynamic parameter** (via `dynamicparam`/`New-QuietWorkspaceSuiteParameter`, lines 30–34), so its exact allowed values depend on `-WorkspaceRoot`'s discovered test suites at bind time; defaults to `'All'` if not bound (line 36).

Example:
```powershell
./scripts/Invoke-ContainerCi.ps1 -Image quietcli2-debian:local -Platform debian -ExpectedRuntimeIdentifier linux-x64 -Headless
```

## Dependencies

- Dot-sources `WorkspaceProjects.ps1` (line 31, inside `dynamicparam`) and `Common.ps1` (line 37).
- Calls `Initialize-Profilers.ps1` (line 41) when `-Profiler` is set without explicit tool paths.
- Starts `Invoke-ContainerWorker.ps1` as a separate background `pwsh` process (lines 47–55) via `Start-Process`, and `Watch-Tests.ps1` as the visible monitor (line 57) unless `-Headless`.
- Calls `Wait-WorkspaceWorker` (from `Common.ps1`, line 58) to block until the worker/monitor reach a terminal state.
- Native tool: resolves `pwsh` via `Get-Command pwsh -CommandType Application` (line 47) — assumes `pwsh` is on `PATH`.
- Filesystem: creates a per-run report directory under `Get-QuietReportRoot $WorkspaceRoot 'containers'` (lines 45–46).

## Side effects

- Creates a new per-run directory and writes `worker.stdout.log`/`worker.stderr.log` there.
- Starts two background OS processes (`Start-Process`, lines 55, 57) — the worker (hidden on Windows, line 53) and, unless `-Headless`, a visible monitor window.
- Throws `'A local visible monitor requires the Windows host launcher.'` (line 54) if run non-headless on a non-Windows host — i.e. refuses to proceed rather than silently going headless, consistent with the repo's visible-monitor test-run policy.
- Throws `"Container tests failed: $run"` (line 60) if the worker's final state isn't `'Success'`.
- The real container creation/teardown (Docker/Podman `create`/`cp`/`start`/`rm`) happens inside the delegated `Invoke-ContainerWorker.ps1`, not here.

## Findings

- No bugs found in the control flow itself after genuine scrutiny: the `-Headless`+non-Windows guard (line 54) correctly prevents the "launch a GUI window on a host with no desktop" failure mode, and `Wait-WorkspaceWorker` is used uniformly rather than ad hoc polling.
- DESIGN: `-Suite` being a dynamic parameter resolved from `-WorkspaceRoot` at bind time (lines 30–34) is clever but makes the script's actual accepted values invisible from `Get-Help` without a live `$WorkspaceRoot` to probe — this is a minor discoverability/testability cost traded for avoiding a duplicated, hand-maintained `ValidateSet` of suite names (a reasonable DRY tradeoff, not a bug).
- Missing input validation: `-Image` has no existence/format check before being forwarded into the worker's argument list (line 48) — a typo'd image name only fails much later inside the selected engine image inspect call made by `Invoke-ContainerWorker.ps1`, several process hops away from this script.
- CONVENTION: lines 48–52 build the argument list by string concatenation of `@(...)` arrays with conditional `+=`; this is standard PowerShell idiom but produces an argument *array* rather than a single pre-escaped command string — correctly avoids shell-injection risk since `ConvertTo-CiArgument` (from `Common.ps1`) is applied to path-shaped values before inclusion (lines 48, 50), which is a good security practice (exact argument vectors rather than string-built shell commands, matching the `AGENTS.md` "Example" guidance on `-FilePath`/`-ArgumentList`).
- Security: the launcher quotes Image with ConvertTo-CiArgument before Start-Process; the worker passes an argument vector to the selected engine through the CI process helper. No interpolated shell command is used.
- No companion Pester test found for `Invoke-ContainerCi.ps1`.
- Test-run monitor convention compliance: the monitor is `Watch-Tests.ps1`, started via `Start-Process -FilePath $runner -WindowStyle Normal` (line 57), matching the `AGENTS.md` "Start-Process pwsh -WindowStyle Normal" requirement; whether `Watch-Tests.ps1` itself renders a bordered Unicode table with a `Duration` column is outside this script's own scope (it is a separate script) and was not verified here.

## Verdict

Fit for purpose: correctly guards against a headless/non-Windows monitor contradiction and delegates cleanly to the worker/monitor pair. Highest-priority improvement: validate `-Image` (and its selected-engine reachability) before launching the background worker, so a bad image reference fails fast with a clear message instead of several process-hops deep inside the worker.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs existing prepared images; no pull, host installation or implicit dependency download.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
