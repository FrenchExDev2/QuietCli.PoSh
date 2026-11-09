# New-ReadyToRunCandidate.ps1

## Purpose

Builds a disposable, ReadyToRun (R2R) copy of `FrenchExDev2.QuietCli.Core.PoSh`'s native engine, so it can be A/B cold-start profiled against the normal (non-R2R) build without ever touching the source workspace's own build output. It solves the business problem of measuring whether `PublishReadyToRun=true` meaningfully improves cold-start latency, which matters for an interactive CLI module whose first-call latency is user-visible. It is invoked by the GitHub Actions workflow `.github/workflows/quietcli2-readytorun.yml` and feeds its output (a `.psd1` manifest path) into `Invoke-ColdStartGate.ps1` as `-CandidateModule`, as documented in `docs/README-readytorun_profiling.md`.

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `WorkspaceRoot` | `string` | No | `Split-Path $PSScriptRoot -Parent` |
| `CandidateRoot` | `string` | No | `Join-Path ([IO.Path]::GetTempPath()) 'quietcli-r2r-candidate'` |
| `RuntimeIdentifier` | `string` | No | Windows: `win-<arch>`; Linux: `linux-x64`; other platforms: throws, requiring explicit `-RuntimeIdentifier` |
| `Configuration` | `string` (`ValidateSet('Release','Debug')`) | No | `Release` |

```powershell
$candidate = ./scripts/New-ReadyToRunCandidate.ps1
./scripts/Invoke-ColdStartGate.ps1 -CandidateModule $candidate -CandidateLabel readytorun -Arguments @{ MeasurePackageSize = $true }
```

## Dependencies

- Dot-sources `Common.ps1` (line 44), which in turn dot-sources `ReportPaths.ps1`, `Ci.Process.ps1`, `SourceIdentity.ps1`, and `RuntimeTargets.ps1` — giving this script `Invoke-WorkspaceNative`, `Get-QuietBinaryInputs`, and `Write-QuietBuildManifest` (used at lines 53-55; the latter two are not shown in this file so are presumably defined in `Common.ps1`'s dependency chain or `SourceIdentity.ps1`).
- Shells out to `dotnet publish` via `Invoke-WorkspaceNative` (line 54), which itself shells out through the bounded `Invoke-CiProcess` wrapper in `Common.ps1` — not directly through `quiet`, unlike `New-QuietPreviewTag.ps1`'s Git calls. This is a deliberate split per `AGENTS.md`'s own `scripts/Ci.Process.ps1` carve-out: "CI/build orchestration retains the monorepo's engine-independent `scripts/Ci.Process.ps1` helper," so `dotnet publish` calls are exempt from the `quiet` facade requirement.
- Assumes `global.json` and the whole `FrenchExDev2.QuietCli.Core.PoSh/` directory exist under `WorkspaceRoot`, that `dotnet` is on `PATH`, and that the `net10.0` target framework and the selected RID's SDK/runtime packs are installed.
- Assumes write access to the system temp directory (`CandidateRoot` defaults there).

## Side effects

- Deletes (`Remove-Item -Recurse -Force -ErrorAction SilentlyContinue`, line 46) and recreates `CandidateRoot` unconditionally, with **no confirmation and no `SupportsShouldProcess`** — unlike `New-QuietPreviewTag.ps1`, this script offers no `-WhatIf` safety net even though it performs a recursive delete.
- Copies `global.json` and the entire `FrenchExDev2.QuietCli.Core.PoSh` tree into `CandidateRoot` (lines 48-49).
- Runs `dotnet publish` into `CandidateRoot/FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess` (line 54), consuming CPU/disk and network (NuGet restore) during the publish.
- Writes a build manifest JSON (`Write-QuietBuildManifest`, line 55) into the candidate tree.
- Writes the resulting manifest path to stdout (`Write-Output`, line 59) as the script's contract-defined return value.
- Never writes to `WorkspaceRoot` itself — this isolation is explicitly the stated purpose (see `.DESCRIPTION`, lines 6-11) and the implementation honors it: every write target is under `CandidateRoot`.

## Findings

- BUG-adjacent / DESIGN: `Remove-Item -LiteralPath $CandidateRoot -Recurse -Force -ErrorAction SilentlyContinue` (line 46) silently swallows any deletion failure (e.g. a locked file from a previous crashed run, or a user-supplied `-CandidateRoot` that points somewhere unintended). If deletion partially fails, `New-Item -ItemType Directory -Path $CandidateRoot` on the next line will likely throw on an existing directory, but a partial failure (some files removed, some locked) could leave a candidate tree with stale leftovers that silently get copied over by `Copy-Item ... -Recurse`, producing a corrupted R2R candidate without any clear error. The `-ErrorAction SilentlyContinue` should at minimum be scoped more narrowly (e.g. tolerate "path does not exist" only) rather than blanket-suppressing.
- CONVENTION: no `SupportsShouldProcess`/`-WhatIf` guard on a script that recursively deletes a directory tree (line 46), unlike the comparable `Remove-DevelopmentWorkstationRun.ps1` and `New-QuietPreviewTag.ps1` in this same folder, which both use `[CmdletBinding(SupportsShouldProcess, ...)]`. This is an inconsistency within the scripts folder's own conventions, not a hard requirement violation, but worth flagging since the default `-CandidateRoot` is a fixed, predictable temp path (`quietcli-r2r-candidate`) that a careless caller could collide with another process using the same path.
- CONVENTION: the repo's async-preference guidance ("prefer async methods... use `.GetAwaiter().GetResult()` even in sync PowerShell") is not applicable here in any meaningful way — `Copy-Item`, `Remove-Item`, and the `dotnet publish` invocation (delegated to `Invoke-WorkspaceNative`/`Invoke-CiProcess`) are the natural calls; there's no raw synchronous I/O API being used where an async equivalent is idiomatically expected. No violation.
- DESIGN: hardcoded relative paths `'FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj'` and `'FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess'` (lines 51-52) are baked into the script body rather than being parameters or sourced from a shared constant (e.g. the module name used elsewhere as `FrenchExDev2.QuietCli.Core.PoSh`). If the Core module is ever renamed or restructured, this script silently breaks at a hardcoded string rather than failing fast with a clear message tied to a single source of truth.
- Testability: no Pester test exercises this script directly (no match for `New-ReadyToRunCandidate` found under any `*Tests*.ps1` in this module). Given it performs a real `dotnet publish`, a full functional test is expensive, but there is no test at all — not even one asserting the "never touch the source workspace" invariant stated in its own `.DESCRIPTION`, which is exactly the kind of property that should be regression-tested (e.g. hash the source tree before/after and assert no change).

## Verdict

Functionally sound and narrowly scoped, but needs rework on robustness grounds: the unguarded `-ErrorAction SilentlyContinue` recursive delete (line 46) combined with the complete absence of `-WhatIf`/confirmation is the single highest-priority fix — add `SupportsShouldProcess` and replace the blanket error suppression with an explicit check that the directory either doesn't exist or was fully removed before proceeding.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
