# Invoke-GitQualification.ps1

## Purpose

This is a deliberate "qualification gate" that refuses to report success for the Git-handler qualification effort unless the coverage work is actually finished. It solves a trust problem: an inventory-based coverage report (`Get-QuietGitCoverage`) could otherwise be mistaken for proof that every Git command/option/platform combination has been exercised. The script computes coverage, always writes a `qualification.json` report, and then throws one of three explicit failure reasons (missing configuration, incomplete inventory, or "runner not implemented") rather than ever returning a green exit code. It is not wired into any CI workflow or caller script found anywhere else in `scripts/` (no `.ps1` or `.yml` reference to it was found besides its own docs and the qualification README), so today it appears to be a manually invoked audit/reporting tool rather than a step in an automated pipeline.

## Usage

Parameters (all optional):
- `ConfigurationPath` (`string`, optional) — path to a prepared Podman/Dockur qualification configuration with capability evidence. If omitted or the path does not exist, `ConfigurationAvailable` is `false`.
- `WorkspaceRoot` (`string`, optional, default: parent of `$PSScriptRoot`) — QuietCli2 workspace root.

Example:
```powershell
./scripts/Invoke-GitQualification.ps1 -ConfigurationPath ./qualification/podman-dockur.json
```
Because the script always throws (see Findings), every invocation currently terminates with a non-zero exit, so it functions purely as a report generator plus an assertion that the feature is not yet qualified.

## Dependencies

- Dot-sources `Common.ps1` (line 12), which in turn loads `ReportPaths.ps1`, `Ci.Process.ps1`, `SourceIdentity.ps1`, `RuntimeTargets.ps1`.
- Imports `FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1` (line 16) — the actual source of `Get-QuietGitCoverage`.
- Uses `Get-QuietReportRoot` (from `ReportPaths.ps1`) and `Write-WorkspaceJson` (from `Common.ps1`) for report placement/writing.
- Filesystem: creates a timestamped directory under the workspace's report root (`qualification/<timestamp>`).
- No external native process is shelled out to directly in this script.

## Side effects

- Mutates `$env:PSModulePath` by prepending the workspace root (line 15) — this is a process-wide, not scoped, side effect that persists for the remainder of the PowerShell session.
- Creates a directory and writes `qualification.json` into it (lines 13–14, 21).
- Throws (never returns 0) under all three paths explored in the code.

## Findings

- BUG: The script is unconditionally terminal — after the unconditional `Write-WorkspaceJson` write, every exit path is a `throw` (lines 22–24). Even the "fully qualified, configuration present" case has no success branch: if `$missing.Count` is zero and `$configurationAvailable` is true, execution falls through to line 24's unconditional `throw 'QualificationRunnerNotImplemented...'`. In other words, no input can ever make this script succeed — it is a stub that always fails by design, but nothing in the `.SYNOPSIS`/parameter docs says that plainly to a caller who might expect a possible success exit.
- DESIGN: The hardcoded `RequiredPlatforms` (`'windows-dockur','debian-glibc','alpine-musl'`) and `Versions` (`40..56|ForEach-Object{"2.$_.0"}`, line 20) bake specific product/version expectations directly into a generic-sounding "gate" script instead of sourcing them from a shared configuration/manifest. If the supported version range changes, this file must be hand-edited and is easy to miss since it isn't named as a version-authority file.
- CONVENTION: No explicit UTF-8 handling for `Write-WorkspaceJson`'s caller — this is delegated correctly to `Common.ps1`'s own UTF-8-without-BOM writer, so this particular file is compliant by inheritance, not by its own code.
- CONVENTION: Uses `.ToString('yyyyMMdd-HHmmss')` with no explicit `[Globalization.CultureInfo]::InvariantCulture`, unlike some peer scripts (e.g. `RunLog.psm1` explicitly passes `InvariantCulture` for its timestamp format). Low risk since the format string contains no culture-variant tokens, but it's an inconsistency worth normalizing.
- Testability: No Pester test file was found anywhere under `FrenchExDev2.QuietCli.Core.Tests.PoSh` or `FrenchExDev2.QuietCli.Git.Tests.PoSh` referencing `Invoke-GitQualification`. Given the script's entire job is to enforce a specific failure/success decision tree, this is a clear coverage gap: a regression that accidentally let the script return 0 on incomplete coverage would go undetected.
- No property-based testing, fuzzing, or mutation testing evidence exists for this script's decision logic (missing-count threshold, configuration-availability branch), despite AGENTS.md's requirement for all three on behavior with meaningful invariants (a gate whose entire purpose is a pass/fail invariant is a prime candidate).

## Verdict

As a guardrail that intentionally never reports success until qualification work is complete, the script does its narrow job, but it is effectively dead/unreachable from any automated pipeline today and has zero test coverage for its own branching logic. Highest-priority fix: add a Pester test asserting each of the three throw paths (missing configuration, incomplete inventory, runner-not-implemented) fires under the right synthetic inputs, since a silent regression here would defeat the entire point of the gate.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
