# Invoke-ContainerColdStartWorker.ps1

## Purpose

Stages a baseline module and a ReadyToRun candidate module into a private, networkless Podman container
and runs `Invoke-ColdStartGate.ps1` as the container's entrypoint, then retrieves the resulting
`artifacts/coldstart` directory back to the host. This is the actual containerized execution logic behind
`Invoke-ContainerColdStart.ps1` (which is only the host-side launcher/monitor wrapper). Per its own
`.DESCRIPTION` (lines 9–13), it deliberately stays independent of `Invoke-ContainerWorker.ps1` because
there is exactly one guest entrypoint and no test-suite dispatch needed here, unlike the general worker.
An unstable A/A noise floor or inconclusive/slower A/B verdict is treated as informational, not a crash —
only a guest crash, missing report, or architecture mismatch is a crash. It is invoked by
`Invoke-ContainerColdStart.ps1` as a background `pwsh -File` process.

## Usage

Parameters:
- `-WorkspaceRoot` (string, **mandatory**) — source of `scripts/` and the already-built baseline module.
- `-RunDirectory` (string, **mandatory**) — dedicated host report directory.
- `-Image` (string, **mandatory**) — already-prepared platform image; never pulled implicitly.
- `-Platform` (string, **mandatory**, `[ValidateSet('alpine','debian')]`).
- `-CandidateModule` (string, **mandatory**) — host path to the ReadyToRun candidate `.psd1`.
- `-CandidateLabel` (string, optional, `[ValidateNotNullOrEmpty()]`, default `'readytorun'`).
- `-ExpectedRuntimeIdentifier` (string, optional, `[ValidatePattern('^linux-(musl-)?(x64|arm64)$')]`).

Example (invoked internally by the launcher; not meant for direct ad hoc use, but structurally):
```powershell
pwsh -File ./scripts/Invoke-ContainerColdStartWorker.ps1 -WorkspaceRoot C:\repo -RunDirectory C:\run\coldstart-1 -Image quietcli2-debian:local -Platform debian -CandidateModule C:\cand\Module.psd1
```

## Dependencies

- Dot-sources `Common.ps1` (line 45) for `Write-WorkspaceJson`, `Invoke-WorkspaceNative`, `Invoke-CiProcess`.
- Native tool: `podman` — `image inspect`, `create`, `cp`, `start`, `inspect` (status/exit code), `logs`, `rm` (lines 76, 88, 90, 92, 97, 104, 127, 135).
- Filesystem: copies `scripts/`, `FrenchExDev2.QuietCli.Core.PoSh/` (excluding `.git`/`bin`/`obj`), and the candidate module's directory into a staging folder (lines 52–72), then `podman cp`'s the whole stage into the container's `/workspace`.
- Guest dependency: the staged image must have `pwsh` at its entrypoint-resolvable path and must contain (after staging) `Invoke-ColdStartGate.ps1`.

## Side effects

- Writes `status.json` repeatedly (lines 49, 91, 99, 138) as a live progress heartbeat.
- Creates and populates a host staging directory under `$RunDirectory/workspace`.
- Creates a Podman container (owned, uniquely named `quietcli2-coldstart-<guid>`, line 46) with `--network none` (line 88) — networkless by design.
- Copies the container's `/workspace/artifacts/coldstart` back to `$RunDirectory/guest` (line 102).
- Writes `guest-diagnostics.json` on crash (lines 125–130) and `summary.json`/`status.json` in the `finally` block (lines 136–138).
- Force-removes the owned container in `finally` (line 135) — best-effort; sets `$state.Cleanup` to an "Unconfirmed" string on failure rather than retrying or escalating.
- Calls `exit 1` (line 140) only on `'Crash'` state.

## Findings

- No outright bugs found in the main happy-path logic after genuine scrutiny; the polling loop (lines 94–101) has a hard 900-second deadline (`$deadline = [DateTimeOffset]::UtcNow.AddSeconds(900)`, line 93) that throws `[TimeoutException]` on exceeding it — this duration is hardcoded rather than parameterized, unlike the launcher's own `-TimeoutSeconds` (`Invoke-ContainerColdStart.ps1` has a configurable `-TimeoutSeconds` default 1200s that bounds the *whole* worker including staging/cleanup, but this inner 900s guest-run deadline is a separate, non-configurable constant) — a caller who raises the outer `-TimeoutSeconds` to accommodate a slower host still hits this inner fixed ceiling first. This should be a parameter or at least derived from the outer timeout rather than a second, independent magic number.
- DESIGN: the "report, not crash" policy for an inconclusive/slower A/A is implemented by checking `$guestFiles.Count -eq 0` (line 107) combined with `$state.GuestExitCode -eq 0` (line 110) to distinguish "A/A was not conclusive" from "something else went wrong with no A/B file and non-zero exit" — this is a reasonable, deliberate way to encode a three-way outcome (success / informational no-run / crash) without a dedicated state enum, consistent with the documented policy, not a flaw.
- Security/robustness: image identity is re-verified via `podman image inspect --format {{.Id}}` and regex-validated against a 64-hex-char SHA256 pattern (line 77) before use — a solid anti-tampering/anti-typo check, consistent with the "never pulled implicitly" / immutable-image-ID philosophy stated in the doc comment.
- Minor: `Invoke-WorkspaceNative podman @('cp', ...)` calls (lines 90, 102) use a fixed `-TimeoutSeconds` (90, 60) that may be tight for large staged directories (the whole `scripts/` + `FrenchExDev2.QuietCli.Core.PoSh/` tree) on a slow disk/CI runner — not a bug per se, but a potential source of flaky timeouts under load, and not configurable from the caller.
- No companion Pester test found for `Invoke-ContainerColdStartWorker.ps1`.
- This script performs no `-Headless`/monitor logic itself (correctly, since that's the launcher's job) — consistent separation of concerns between launcher and worker, matching the pattern used by the general `Invoke-ContainerWorker.ps1`/`Invoke-ContainerCi.ps1` pair.

## Verdict

Fit for purpose, with careful, well-reasoned handling of the three-way success/informational/crash outcome. The main improvement opportunity is the hardcoded, non-configurable 900-second inner deadline (line 93) that is independent of and potentially inconsistent with the launcher's own `-TimeoutSeconds` parameter.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
