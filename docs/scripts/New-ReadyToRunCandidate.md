# New-ReadyToRunCandidate.ps1

## Purpose and usage

Creates a separate net10.0 ReadyToRun candidate for the manual cold-start comparison. The baseline remains unchanged.

```powershell
$candidate=./scripts/New-ReadyToRunCandidate.ps1 -CandidateRoot <new-owned-directory> -RuntimeIdentifier linux-arm64
```

WorkspaceRoot defaults to the repository root. CandidateRoot defaults to the temporary quietcli-r2r-candidate path and must not already exist. RuntimeIdentifier defaults to the actual host RID, including musl/ARM64; Configuration defaults to Release. The result is the candidate module manifest path. The candidate is for the stable CLR 10 profiling host; the release build script separately publishes both CLR builds.

## Dependencies and side effects

Requires Common.ps1, the pinned SDK/runtime packs and an already-built baseline. Copies Core, global.json and Directory.Packages.props; publishes into `lib/inprocess/<rid>`, verifies its R2R header and updates only the candidate portable manifest's selected slots. No baseline mutation, tests or publication.

## Critical review

- `scripts/New-ReadyToRunCandidate.ps1:45` rejects existing destinations and workspace overlap rather than recursively deleting arbitrary paths. Choose a fresh owned destination for each attempt.
- `scripts/New-ReadyToRunCandidate.ps1:56` records the actual RID, architecture and verified format. Copying the source module also copies unused baseline binaries; hosted-path footprint is separate from whole-package footprint.
- The manual workflow builds an IL baseline first and supplies a fresh RUNNER_TEMP directory. It never measures the production R2R build against an identical R2R baseline.
- Compilation and architecture checks do not establish a speedup. The A/A noise floor and A/B results remain informational on shared runners.

## Verdict

Dedicated manual experiment input. Production GitHub R2R builds use Build-Workspace.ps1 instead.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Builds a ReadyToRun copy of FrenchExDev2.QuietCli.Core.PoSh for cold-start A/B profiling.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
