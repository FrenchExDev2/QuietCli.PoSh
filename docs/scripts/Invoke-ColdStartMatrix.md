# Invoke-ColdStartMatrix.ps1

## Purpose

Single entry point that builds the baseline and every requested ReadyToRun candidate, then runs the
cold-start A/A-gated A/B comparison across every requested target — Windows locally and Linux
distributions (debian/alpine, x64/arm64) in Podman containers — with configurable concurrency, mirroring
what `.github/workflows/quietcli2-readytorun.yml`'s Windows job + Linux matrix does, but as one
repeatable local command (per its own `.DESCRIPTION`, lines 7–16). It solves the problem of manually
repeating several build/pull/run steps per platform when validating a ReadyToRun candidate. Every
target's outcome (unstable noise floor, inconclusive/slower verdict, or outright failure) is
informational only and never aborts the other targets — the command always finishes and reports what
happened. No caller inside `scripts/` invokes this script (confirmed via grep); it is a human-run
top-level command, with its result renderable afterward via `Show-ColdStartMatrixReport.ps1`.

## Usage

Parameters:
- `-Targets` (string[], optional, `[ValidateSet('windows','debian-x64','alpine-x64','debian-arm64','alpine-arm64')]`) — explicit target list; mutually exclusive with `-All`.
- `-All` (switch, optional) — fills `-Targets` with `'windows'` plus every Linux distribution for the selected `-Platform`(s).
- `-Platform` (string[], optional, `[ValidateSet('x64','arm')]`) — architectures to include when `-All` is used; ignored otherwise.
- `-MaxConcurrency` (int, optional, `[ValidateRange(1,8)]`, default `2`) — concurrent Linux container targets.
- `-CandidateLabel` (string, optional, `[ValidateNotNullOrEmpty()]`, default `'readytorun'`).
- `-WorkspaceRoot` (string, optional, default `(Split-Path $PSScriptRoot -Parent)`).
- `-SkipBuild` (switch, optional) — skips `Build-Workspace.ps1`, reusing an existing build.
- `-Headless` (switch, optional) — suppresses per-container visible monitor windows (combined progress still printed to console).
- `-RegistryToken` (string, optional, `[AllowEmptyString()]`, default `$env:QUIETCLI_REGISTRY_TOKEN`) — GHCR read token forwarded to `Get-CiImageForDevelopment.ps1`; ignored with `-LocalBuild`.
- `-LocalBuild` (switch, optional) — builds Linux images locally via `New-CiImage.ps1`/Podman instead of pulling published ones.

Examples (from the file's own help, lines 62–72):
```powershell
./scripts/Invoke-ColdStartMatrix.ps1
./scripts/Invoke-ColdStartMatrix.ps1 -Targets debian-x64, alpine-x64 -MaxConcurrency 1 -Headless
./scripts/Invoke-ColdStartMatrix.ps1 -Targets debian-x64, alpine-x64, debian-arm64, alpine-arm64 -LocalBuild -Headless
./scripts/Invoke-ColdStartMatrix.ps1 -All -Platform x64 -LocalBuild -Headless -SkipBuild -MaxConcurrency 4
```

## Dependencies

- Dot-sources `Common.ps1` (line 90); imports `lib/RunEncoding.psm1`, `lib/RunFormat.psm1` -Force (line 91).
- Invokes, per target: `Build-Workspace.ps1` (line 117, unless `-SkipBuild`), `New-ReadyToRunCandidate.ps1` (lines 128, 154), `Invoke-ColdStartGate.ps1` (line 129, Windows target), `New-CiImage.ps1` (line 156, `-LocalBuild`) or `Get-CiImageForDevelopment.ps1` (line 159, default), `Invoke-ContainerColdStart.ps1` (line 161, Linux targets).
- Uses PowerShell 7+ `ForEach-Object -Parallel` (line 142) with `-ThrottleLimit $MaxConcurrency` and `$using:` scope capture for the Linux target fan-out.
- Native tool dependency: Podman (transitively, via `New-CiImage.ps1`/`Invoke-ContainerColdStart.ps1`).
- Filesystem assumption: a temp directory under `[IO.Path]::GetTempPath()` is created and removed (lines 110–111, 176) for staged ReadyToRun candidates per target.

## Side effects

- Writes/builds the baseline (`Build-Workspace.ps1`), unless skipped.
- Creates per-target temp candidate directories under the system temp path and force-removes the whole `$candidateRoot` tree in a `finally` block (line 176) — `-ErrorAction SilentlyContinue` suppresses cleanup failures silently (see Findings).
- Writes the combined matrix result JSON to `<WorkspaceRoot>/artifacts/coldstart-matrix/<UTC-stamp>.json` (lines 180–182).
- Prints a formatted table (`Format-RunTable`, line 186) and guidance to the console.
- Starts/pulls container images and runs containers (via delegated scripts) — network access for image pulls unless `-LocalBuild`.

## Findings

- Missing input validation: line 101 only checks `if ($Targets -and $All)`, but does not validate that `-Targets` is non-empty when explicitly supplied as an empty array (`-Targets @()`) — this would silently fall through to the `elseif (-not $Targets)` default-list branch (line 106) rather than running zero targets as the caller may have intended, since an empty array is falsy in this boolean context. Minor, but surprising behavior for an explicit empty list.
- CONVENTION: cleanup at line 176 uses `-ErrorAction SilentlyContinue` on `Remove-Item -Recurse -Force`, silently swallowing any failure to clean the per-run temp directory. Over many matrix runs this could leak temp directories under `%TEMP%`/`/tmp` without any trace in logs or the written JSON report — a `catch`/`Write-Warning` on failure would make this observable instead of silent.
- DESIGN: the parallel block (lines 142–168) captures `$candidateRoot`, `$PSScriptRoot`, `$WorkspaceRoot`, etc. via `$using:` correctly, and errors inside are caught per-target (lines 164–167) and converted to a `'Failed'` result rather than aborting the whole `ForEach-Object -Parallel`, consistent with the documented "every target's result is informational" policy (lines 14–16). This is a genuine strength, not a flaw.
- The Windows branch (lines 120–136) is also wrapped in its own try/catch converting failure to a `'Failed'` result entry, consistent with the same policy — good symmetry between the Windows and Linux code paths.
- Test-run monitoring window convention: per `AGENTS.md`'s "Test runs" section, every started test run must open a dedicated visible `Start-Process pwsh` monitor window rendered as a bordered Unicode table. This script does not itself open any monitor window directly — it delegates to `Invoke-ColdStartGate.ps1` (no monitor) and `Invoke-ContainerColdStart.ps1` (which does open one per container, unless `-Headless`). Since `-Headless` here only "suppresses the per-container visible monitor window" per its own doc (lines 44–47) while still printing combined progress to console, this is consistent with the convention, not a violation — flagged only because the matrix's own top-level console output (`Write-Host`, `Format-RunTable`) is the only aggregate view a caller gets when running multiple containers with `-Headless`, which may or may not satisfy the "monitor reports progress and every terminal state" requirement at the matrix (as opposed to per-container) level. This is a borderline DESIGN note, not a clear violation, since the underlying container monitor still exists per target when not headless.
- No companion Pester test found for `Invoke-ColdStartMatrix.ps1`.

## Verdict

Fit for purpose: a well-structured, resilient top-level orchestrator with good per-target failure isolation. The highest-priority fix is making temp-directory cleanup failures observable (replace silent `-ErrorAction SilentlyContinue` at line 176 with a logged warning) so leaked temp directories don't accumulate unnoticed across repeated matrix runs.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Single entry point: builds the baseline and every requested ReadyToRun candidate, then runs the cold-start A/B gate on every requested target (Windows locally, Linux distributions in containers), with configurable con...

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
