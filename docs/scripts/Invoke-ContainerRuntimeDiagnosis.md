# Invoke-ContainerRuntimeDiagnosis.ps1

## Purpose

Diagnoses why a prepared Linux container image may be resolving the wrong .NET runtime root (e.g. which
`DOTNET_ROOT`/architecture the PowerShell host actually binds to) by running a default control plus one
or more explicit `-RuntimeRoots` overrides inside a single, uniquely labeled, networkless disposable
container, without pulling, rebuilding, installing, or changing any RID guard. It exists to answer "is
this image's runtime binding broken, and if so under which root?" as a read-only investigation tool,
separate from qualification (the file's own doc explicitly warns: "Success means the diagnostic
completed... which is never product qualification", lines 8–9). This script is both its own host-side
launcher and its own container-side worker (self-relaunching via `-Worker`, lines 37–53) — it is
referenced from `docs/README-container-runtime-diagnosis.md` and the dated audit
`docs/audits/2026-11-09-container-runtime-diagnosis.md`, but no other script in `scripts/` was found
invoking it by name via grep, indicating it is a standalone diagnostic tool run directly by a developer
when a runtime-identifier mismatch is suspected.

## Usage

Parameters:
- `-Image` (string, **mandatory**) — existing local image reference, resolved once to its immutable ID.
- `-ExpectedRuntimeIdentifier` (string, **mandatory**, `[ValidatePattern('^linux-(musl-)?(x64|arm64)$')]`) — the portable Linux target.
- `-RuntimeRoots` (string[], optional, default `@('/usr/lib/dotnet','/usr/share/dotnet')`) — explicit Linux .NET roots compared against the image's unchanged default.
- `-ExpectedRuntimeMajor` (int, optional, `[ValidateRange(10,99)]`, default `10`) — required CLR major for the selected PowerShell host.
- `-WorkspaceRoot` (string, optional, default `(Split-Path $PSScriptRoot -Parent)`).
- `-RunDirectory` (string, optional) — new report directory; auto-generated under the shared temp report root when omitted.
- `-Headless` (switch, optional) — CI-only, no local Windows monitor window.
- `-Worker` (switch, optional, internal) — "internal background entry point; use the normal launcher locally" (per doc, line 25).

Example:
```powershell
./scripts/Invoke-ContainerRuntimeDiagnosis.ps1 -Image quietcli2-debian:local -ExpectedRuntimeIdentifier linux-x64
```

## Dependencies

- Dot-sources `Common.ps1` (line 33); imports `lib/RuntimeDiagnosis.psm1` (line 34) for `Get-QuietRuntimeDiagnosis`.
- Launcher path: resolves `pwsh`/`pwsh.exe` via `$PSHOME` (line 43), self-relaunches itself (`$PSCommandPath`, line 44) with `-Worker`, and optionally `Watch-Tests.ps1` as the visible monitor (line 49).
- Worker path: native tool `podman` — `image inspect`, `create`, `cp`, `start`, `exec`, `rm` (via the local `Invoke-DiagnosisProcess` helper, lines 62–74, used throughout 79–124).
- Copies `Probe-ContainerRuntime.ps1`, `Ci.Process.ps1`, `RuntimeTargets.ps1`, `lib/RuntimeDiagnosis.psm1` into the container stage (lines 86–88) and re-imports the staged copy of `RuntimeDiagnosis.psm1` (line 88).
- Uses `Get-QuietRuntimeTargets $WorkspaceRoot` (line 35, 90) to validate `-ExpectedRuntimeIdentifier` and to enumerate native asset sources (`libe_sqlite3.so` per target RID, lines 90–93).
- Uses `Get-FileHash -Algorithm SHA256` extensively for asset/source provenance (lines 92, 97–98 via `Select-String`).

## Side effects

- Worker: writes `request.json`, `status.json`, `inputs.json`/`assets.json`, per-variant probe JSON files, `diagnosis.json`, `commands.json`, `summary.json` under `-RunDirectory` and its `inputs`/`assets` subfolders.
- Creates and (in `finally`) force-removes an owned, networkless, uniquely-labeled Podman container (`quietcli-runtime-<owner-prefix>`, lines 56, 100, 124).
- Launcher: starts the background self-relaunched worker process and, unless `-Headless`, a visible `Watch-Tests.ps1` monitor (lines 47–49).
- Throws `'RuntimeDiagnosisRunExists'` (line 40) if `-RunDirectory` already exists — refuses to overwrite a prior run's artifacts.
- Throws on the launcher side if the overall `Wait-WorkspaceWorker` summary state isn't `'Success'` (line 52); worker sets `$state.State='Failed'` and overwrites `$state.State` to `'Failed'`/re-marks cleanup `'Unconfirmed'` if container removal itself fails (line 124), which is a secondary failure mode worth noting (a successful diagnosis can be downgraded to `'Failed'` purely due to cleanup trouble, conflating diagnostic result with janitorial result).

## Findings

- DESIGN: line 124's `finally` block can overwrite a diagnosis that completed successfully (`$state.State='Success'` set at line 121) with `'Failed'` purely because the owned container could not be removed afterward (`if($state.Cleanup -eq 'Unconfirmed'){$state.State='Failed';...}`). This conflates "did the diagnosis produce a valid result" with "did cleanup succeed" into a single status field — a caller checking `$summary.State.State -ne 'Success'` cannot distinguish "the diagnosis itself failed" from "the diagnosis succeeded but a container leaked." A separate `Cleanup` status (which does already exist, line 124 sets `$state.Cleanup`) being surfaced independently in the launcher's returned object (it already is, `Cleanup=$summary.State.Cleanup` at line 51) partially mitigates this, but the overwritten top-level `State` still loses information.
- Missing input validation: `-RuntimeRoots` entries are validated with a regex + no-`..`-traversal check (line 36: `if($runtimeRoot -cnotmatch '^/[A-Za-z0-9_./-]+$' -or $runtimeRoot.Contains('..'))`) — this is a genuinely good defensive practice against path-injection into the container environment variables, worth calling out as a positive, not a gap.
- Self-relaunch pattern (worker invoking `$PSCommandPath` with `-Worker`, line 44) is a slightly unusual design versus the sibling scripts' convention of a separate `*Worker.ps1` file (e.g. `Invoke-ContainerColdStart.ps1` + `Invoke-ContainerColdStartWorker.ps1`). This is DRY in the sense of not needing two files, but is a DESIGN inconsistency with the rest of this script family's naming/splitting convention, and makes `-Worker` an easily-misused parameter if a caller passes it directly (the doc explicitly warns "use the normal launcher locally", but nothing in code prevents direct `-Worker` use outside a container, i.e. it is not fenced to only run meaningfully inside the container context).
- No companion Pester test found for `Invoke-ContainerRuntimeDiagnosis.ps1`.
- Correct, consistent use of `[Console]`/async-free direct JSON write via `Write-WorkspaceJson`/`Get-Content -Encoding utf8` throughout — matches the repo's UTF-8 convention.
- Monitor convention: launcher correctly uses `Start-Process $runner -WindowStyle Normal` (line 49) for the visible monitor and guards non-Windows+non-headless at line 38, consistent with `AGENTS.md`.

## Verdict

Fit for purpose as a careful, narrowly-scoped diagnostic tool with good path-injection defenses; the main improvement is decoupling the cleanup-failure path (line 124) from the diagnosis's own success/failure state so a successful diagnosis is never masked as `'Failed'` purely due to a leaked container.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Diagnoses a prepared Linux image without pulling, rebuilding, installing or changing RID guards.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
