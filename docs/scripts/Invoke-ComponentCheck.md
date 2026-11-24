# Invoke-ComponentCheck.ps1

The optional `-Campaign mutation`, `profiling` and `profiled-mutation` modes run one declared companion. Mutation reads the focused suite or mutation environment from `build/companions.yaml`. Profiling runs the PowerShell test suite with PSProfiler and saves its report under `profiling/`. `profiled-mutation` enables both in the same test pass. `-Parallel:$false` selects one test worker.

With an explicit `-RunDirectory`, Git and Vagrant also save their mutation catalogue summaries under `mutation-evidence/`. GitHub Actions adds Markdown and HTML measurement tables to the campaign artifact after the test step. [Export-CampaignReport](Export-CampaignReport.md)

<!-- script-source:begin -->
Source file: [`Invoke-ComponentCheck.ps1`](../../scripts/Invoke-ComponentCheck.ps1)
<!-- script-source:end -->

## Purpose and usage

Validates explicit component paths and executes build, smoke or full workspace-component checks.

```powershell
./scripts/Invoke-ComponentCheck.ps1 -Suite Git -QualificationMode smoke -WhatIf
```

## Dependencies and side effects

ValidateOnly checks catalogue paths and the mode without starting a build or test. SmokeBatch requires a nonempty SuitesJson array. Local tests use the shared visible monitor; GitHub runs use headless reports. Smoke success never qualifies publication.

## Critical review

- The implementation in scripts/Invoke-ComponentCheck.ps1 keeps executable orchestration in entry points and helper functions in libraries; imports do not start business operations.
- WorkspaceLayout.Tests.psm1 covers generated membership, preview behavior, selective package consumption, 120-companion isolation, malformed XML and a targeted selection mutant. CompanionSmoke.Tests.psm1 exercises actual imports and native integration.
- Hosted Windows/Linux matrix and cache-transfer evidence must be read from the revision's CI artifacts; local checks do not establish unexecuted targets.

## Verdict

Explicit source-bound automation with a checked scope. Read the selected run's saved reports for qualification evidence.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

The `-Campaign performance` option times one unprofiled test run for a declared companion after the build. It writes `component-performance.json` to the run directory on success. The measurement includes test harness overhead and process startup. It does not apply a performance threshold.

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs a profile-validated build, grouped smoke or full workspace-component qualification.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
