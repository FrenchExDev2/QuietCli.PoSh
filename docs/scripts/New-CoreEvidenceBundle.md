# New-CoreEvidenceBundle.ps1

## Purpose

Collects a CI job's test/container report tree into a separate, checksummed "evidence bundle" directory — attaching workflow revision/run identity and SHA-256 per file — so that downstream reporting (`New-CorePerformanceReport.ps1`) and human reviewers can trust that the evidence wasn't silently modified or partially produced, and so that missing or incomplete mandatory profiling data becomes an explicit, visible gap rather than a silent pass. It is called twice from `.github/workflows/ci.yml` (lines 169, 331) — once per test-matrix job and once per container job — immediately before `New-CorePerformanceReport.ps1` consumes the resulting `evidence-manifest.json`.

## Usage

Parameters:
- `-ReportRoot [string]` — the owned test/container report tree to copy from.
- `-OutputDirectory [string]` — a separate artifact directory that must be outside `ReportRoot` (enforced; see Findings).
- `-Revision [string]` — exact workflow revision recorded in the manifest.
- `-RequireProfiling [switch]` — when set, missing successful profiling evidence is recorded as an explicit gap (and the script exits with a thrown error at the end if any gap exists).

Example (from `ci.yml`):
```powershell
./scripts/New-CoreEvidenceBundle.ps1 -ReportRoot ./artifacts/tests -OutputDirectory ./artifacts/evidence -Revision $env:GITHUB_SHA -RequireProfiling:($env:QUIETCLI_SUITE -ne 'Git')
```

## Dependencies

- Dot-sources `Common.ps1` (line 16) for `Write-WorkspaceJson`.
- Pure filesystem/hashing (`Get-FileHash -Algorithm SHA256`, `[IO.FileStream]`/`CopyToAsync`) — no external process, no git, no network.
- Reads GitHub Actions environment variables `GITHUB_REPOSITORY`, `GITHUB_RUN_ID`, `GITHUB_RUN_ATTEMPT`, `RUNNER_OS`, `RUNNER_ARCH` directly (lines 61-62) for the manifest — these are `$null`/empty when run outside Actions, which the manifest would then simply record as empty values (no explicit guard or local-run fallback).
- Assumes profiling evidence (`profiling/summary.json` and friends) follows a specific nested shape (`ProfilerVersion`, `ClrProfilerVersion`, `Collectors[].Trace/.Speedscope/.SHA256`, `TargetIdentity.EngineMode`) produced elsewhere by the profiling pipeline (not reviewed in this pass).

## Side effects

- Enforces (`EvidenceDestinationMustBeOutsideReports`, line 20) that `-OutputDirectory` is not inside `-ReportRoot`, via a relative-path check.
- Creates `-OutputDirectory` if missing.
- Recursively walks `-ReportRoot` (explicit stack-based traversal, not `Get-ChildItem -Recurse`, lines 25-42), **throwing** `EvidenceSourceLinkRejected` on any reparse point found anywhere in the source tree (line 28) — refuses to follow symlinks.
- Skips the `workspace`, `.git`, `.profilers`, `bin`, `obj`, `lib` subdirectory names entirely (line 29) and only copies files with extensions `.json .nettrace .log .txt .xml .csv` (line 30).
- Copies every eligible file into `-OutputDirectory`, preserving relative paths, and records `{Path, Bytes, SHA256}` for each.
- Reads (but does not modify) any `profiling/summary.json`-shaped files found, cross-validating referenced trace/speedscope files' hashes.
- Writes `evidence-manifest.json` into `-OutputDirectory` (via `Write-WorkspaceJson`, assumed UTF-8 per `Common.ps1`).
- Throws `MandatoryProfilingEvidenceMissing` at the very end (line 67) if `-RequireProfiling` was set and any gap was recorded — this is the mechanism that fails the CI job when required evidence is absent.

## Findings

- No bug found in the reparse-point / destination-boundary guards (lines 20, 28) — both are exactly the kind of defensive filesystem checks the sibling `WorkstationResources.psm1::Test-WorkstationDirectoryBoundary` also implements, applied here directly inline rather than via a shared helper (see DRY note below).
- DESIGN: the reparse-point/destination-boundary/path-traversal safety logic in this script (lines 20, 28) duplicates the same *kind* of check already implemented as a reusable, independently tested function in `scripts/lib/WorkstationResources.psm1` (`Test-WorkstationDirectoryBoundary`). The two aren't identical (this script checks `-OutputDirectory` vs `-ReportRoot`, not an owned-run subtree vs a root), but the underlying safety property — "never traverse or write through a symlink, never let a destination end up inside or equal to a protected source" — is the same business rule implemented twice in two different files with two different styles. Per AGENTS.md's DRY guidance ("avoid duplicated business rules, validation or protocol logic"), these could share one helper.
- CONVENTION: this file has **no doc-comment author-level `.SYNOPSIS`/parameter English-language issue** — unlike several of its siblings, the English comment-based help here (lines 1-12) is clean, with no stray French summary line. This is worth noting positively since several other files in this review carried a French top-line.
- DESIGN: the hardcoded skip-list for directory names (`'workspace','.git','.profilers','bin','obj','lib'`, line 29) and the hardcoded allowed-extension list (`.json .nettrace .log .txt .xml .csv`, line 30) are inline magic literals with no named constant, parameter, or shared configuration — a future report type using a new extension (e.g. `.trace` for a different profiler, or `.md`) silently drops those files from the evidence bundle with no warning, which could produce a false "evidence complete" signal if a profiling pipeline change introduces a new output file type this script doesn't know about yet.
- No unhandled error path found for the main copy loop; `Get-FileHash`/`ConvertFrom-Json` failures inside the profiling-validation loop (lines 44-58) are not wrapped in try/catch, so a malformed `summary.json` would throw an unhandled exception and abort the whole bundle rather than being recorded as a gap like other anomalies in this file — inconsistent with the rest of the script's "record a gap, keep going" philosophy (e.g. line 43's `else` branch when `$source` doesn't exist at all).
- Testability: has a dedicated test — `FrenchExDev2.QuietCli.Core.Tests.PoSh/Evidence.Tests.ps1` references `scripts/New-CoreEvidenceBundle.ps1` directly (line 12 of that test file) and presumably exercises at least the happy path and the destination-boundary guard; the malformed-`summary.json` unhandled-exception path noted above was not confirmed to be covered.

## Verdict

Solid, security-conscious evidence collection with a correct fail-loud design for missing mandatory profiling; the highest-priority fix is wrapping the profiling-evidence read/validate loop (lines 44-58) in a try/catch that records a gap (consistent with the rest of the file) instead of letting a malformed `summary.json` abort the whole bundle with an unhandled exception.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Copies bounded report types into a CI evidence artifact with revision/run identity and SHA-256 checksums.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
