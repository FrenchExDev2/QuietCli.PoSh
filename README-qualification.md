# Tests and qualification

[Back to the QuietCli overview](README.md) · [Documentation index](docs/README.md)

Qualification combines independent examples, generated properties, malformed-input fuzzing and targeted mutation campaigns in the Core, Git and Vagrant companion test projects. A successful focused run establishes only its executed scope. Reports must identify the source revision, binaries, host/runtime, RID, scenarios, exclusions and remaining gaps; missing or incomplete required evidence blocks qualification.

## Local suites

Run from the monorepo root in PowerShell Core 7.6+, with the pinned SDK and existing native prerequisites. Builds and tests do not publish packages.

Local feature/fix-branch commits and pushes do not require running the companion suites. Commit-Workspace checks source/documentation contracts and the source lock; it never launches companions. Ask before starting a full local campaign unless explicitly requested. GitHub workflows perform the qualification for their PR/develop/release scope. A cancelled or filtered local run does not prevent creating a work-branch checkpoint and never counts as qualification.

Core mixes pure logic, filesystem integration, native processes and qualification campaigns. The special Integration suite selects the import/performance workload; it is not a filter for every integration test. Known case reports expose TestKind/Dependencies; unreviewed cases remain Unclassified. [Commit-suite boundaries and PSDrive feasibility](docs/testing/commit-workspace.md) explain the physical temporary repositories and the separation available for fast unit logic.

```powershell
./scripts/Initialize-Workspace.ps1 -Restore
./scripts/Build-Workspace.ps1
# Use a fresh PowerShell process after rebuilding loaded assemblies.
./scripts/Invoke-WorkspaceCi.ps1 -Suite All -SkipBuild
```

[Invoke-WorkspaceCi.ps1](scripts/Invoke-WorkspaceCi.ps1) runs a background worker with a dedicated visible PowerShell monitor on Windows. It prints the reopening command and closes the monitor after saving the terminal result. `-Headless` is for CI; local Linux-container runs use the Windows host launcher. `-SkipBuild` still requires matching, integrity-checked binaries. Use `-TimeoutSeconds` to bound a campaign and a new `-RunDirectory` to select its output location.

| `-Suite` | Development scope |
| --- | --- |
| `All`, `Core`, `Git` | All discovered companions, Core only, or Git only. `All` currently includes Core, Git and Vagrant; it is an orchestration mode, not a module. Core changes also require consumer validation. |
| `Import`, `Integration` | Fresh-process import measurements; import diagnostics and eight controlled Core-only Git fixture states. |
| `RealStatus` | Core callbacks against explicitly selected existing repositories; requires `-RepositoryConfig` pointing to a UTF-8 JSON array of repository paths. |
| `Recall`, `RecallMutation`, `RecallLarge` | Capture/replay regressions, targeted mutations, or actual 4 GiB + 1 MiB streaming and ZIP64 evidence. `RecallLarge` requires 12 GiB free disk space. |
| `ConfigurationDelivery` | YAML schema, unique deliveries, tokenization, historical SQLite fixtures and targeted mutations. |
| `Vagrant` | Deterministic parser/handler fixtures and 200 seeded fragmented-stream cases; no Vagrant installation or real provider. Set `QUIETCLI_VAGRANT_PARSER_MUTATION=1` for the targeted parser catalogue. |
| `AgentInstructions`, `Script` | Distributed agent instructions and examples; reusable scripts, factories, generated inputs and targeted mutations. |
| `RunProfiles`, `RunProfilesMutation` | Complete profiling-tooling suite or its entire targeted mutation catalogue. |
| `GalleryPreview` | Preview-version properties, malformed inputs, staged manifests, offline package installation and targeted mutations. |

For example, `./scripts/Invoke-WorkspaceCi.ps1 -Suite RecallMutation -SkipBuild` selects one campaign. Use `-TimeoutSeconds 1800` for `RecallLarge`, `600` for `RunProfiles`, and `3300` for `RunProfilesMutation`. Focused campaigns supplement the full run. `-Case <wildcard>` and `-StopOnFirstFailure` are Core development controls: their partial/incomplete results never satisfy a CI or publication qualification gate. They are not mandatory before a local work-branch commit.

Recall also provides `Compare-QuietRecallAnalysis` (independent analysis states and projected differences), `Export-QuietRecallFixture` (capture plus a skeleton requiring independent expectations), and `Reduce-QuietRecall` (bounded failure-preserving reduction, without a global-minimality claim). See the [Recall contract](docs/README-recall.md).

## Real provider and interactive console checks

Run the opt-in checks from a Windows desktop with matching built binaries:

```powershell
./FrenchExDev2.QuietCli.Vagrant.Tests.PoSh/Invoke-ProviderSmoke.ps1
./FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-UiConsoleSmoke.ps1
```

Both use the shared visible monitor and save terminal reports before their windows close. The provider
check requires existing Vagrant 2.4.9 and a reachable Docker-compatible engine. It builds the copied
two-machine fixture, so network access may be needed; it installs no tools or plugins. Its unique
containers are removed, with an independent absence check. Downloaded base images/build caches can remain.
The console check uses a real unredirected window, changes its dimensions without changing lane data,
then verifies native cancellation, child termination and subsequent UI reuse. Physical Ctrl+C is a separate check.

See the [recorded provider/UI audit](docs/audits/2026-11-09-provider-ui-qualification.md) for executed
stable/preview scopes, mutation outcomes and the unresolved Alpine distribution-RID mismatch.
These checks supplement the release matrix; they do not authorize publication.

## Core performance evidence and profiling

Core/All includes fresh-session import samples, ten import diagnostic controls and eight owned repository states: unborn, clean, mixed, conflict, detached, linked worktree, submodule and bulk. The controlled workload uses Core callbacks without loading the Git companion. [Assert-CoreIntegrationEvidence.ps1](scripts/Assert-CoreIntegrationEvidence.ps1) checks measurements, independent byte/record/hash oracles, damaged-input cases and targeted assertion mutants.

```powershell
# Focused integration plus a separate PowerShell/CLR diagnostic pass.
./scripts/Invoke-WorkspaceCi.ps1 -Suite Integration -SkipBuild -Profiler
```

`-Profiler` is supported for `Core`, `All` and `Integration`, including the corresponding [container launcher](scripts/Invoke-ContainerCi.ps1). [Initialize-Profilers.ps1](scripts/Initialize-Profilers.ps1) prepares checksum-pinned **Profiler 4.3.0** and **dotnet-trace 10.0.750501** in a private cache, without global installation. Supply `-ProfilerModulePath` and `-ClrProfilerPath` to use already prepared tools; explicit initialization with `-OutputDirectory <cache> -Offline` verifies cached archives without downloading.

[Invoke-CoreProfiling.ps1](scripts/Invoke-CoreProfiling.ps1) runs after ordinary timing samples. It records PowerShell line self/inclusive durations and a speedscope view, then collects raw CLR `.nettrace` files and converted speedscope traces for the owned PowerShell PID and, in `Process` hosting, the separate engine PID. Missing collectors, conversions or expected files fail the requested pass. Line wall times and managed frame-name counts are different observations; they are not additive CPU percentages.

[New-CoreEvidenceBundle.ps1](scripts/New-CoreEvidenceBundle.ps1) binds reports and traces to the revision/run and checks file hashes. [New-CorePerformanceReport.ps1](scripts/New-CorePerformanceReport.ps1) produces readable `PERFORMANCES_RESULTS.md` and structured JSON, preserving missing evidence as a failure. See [Core performance definitions and reproduction](FrenchExDev2.QuietCli.Core.PoSh/PERFORMANCES.md).

## ReadyToRun and cold-start comparisons

R2R is an opt-in experiment, separate from functional qualification and the mandatory Core profiling pass. Normal CI/release builds do not enable it. [New-ReadyToRunCandidate.ps1](scripts/New-ReadyToRunCandidate.ps1) copies Core and republishes only the candidate's **net10.0 `lib/inprocess`** engine with Crossgen2, leaving the baseline unchanged. Use a disposable `-CandidateRoot`: the script removes and recreates that directory. Pass the intended RID explicitly for Linux/musl/ARM64.

```powershell
# Baseline already built; select the RID matching the measured PowerShell host.
$candidateRoot = Join-Path ([IO.Path]::GetTempPath()) ('quietcli-r2r-' + [guid]::NewGuid().ToString('N'))
$candidate = ./scripts/New-ReadyToRunCandidate.ps1 -CandidateRoot $candidateRoot -RuntimeIdentifier win-x64
./scripts/Invoke-ColdStartGate.ps1 -CandidateModule $candidate -CandidateLabel readytorun -MeasurePackageSize
./scripts/Show-ColdStartReport.ps1
```

The measured process must actually load the rebuilt net10.0 path; this helper does not produce an R2R net11.0 candidate for a CLR 11 host. `Build-Workspace.ps1 -ReadyToRun -LocalRuntimeIdentifier <RID>` also supports R2R for the integrated build and net11.0 RID publications, but needs a separate complete workspace to preserve an A/B baseline. Its availability does not establish a speedup or qualification on every RID.

[Invoke-ColdStartGate.ps1](scripts/Invoke-ColdStartGate.ps1) first requires an all-`inconclusive` A/A control, meaning its intervals include zero. The console displays that accepted control as `conclusive`; JSON retains `inconclusive`. A failed control blocks A/B with `ColdStartNoiseFloorUnstable`. The cache is keyed by machine/profile and reused for up to 14 days (`-MaxAgeDays`); use `-Force` after changing inputs, arguments or environment because freshness alone does not establish their identity.

| Profile | Measured pairs | Warm-up pairs | Bootstrap resamples | Confidence |
| --- | ---: | ---: | ---: | ---: |
| `coldstart-100` | 100 | 5 | 2,000 | 95% |
| `coldstart-1000` | 1,000 | 10 | 5,000 | 99% |

[Measure-ColdStart.ps1](scripts/Measure-ColdStart.ps1) interleaves seeded fresh-process baseline/candidate pairs and measures import, first call and second call. Failed pairs are discarded and counted, never retried. Verdicts use the bootstrap interval of median paired differences (`candidate - baseline`): below zero means `faster`, above zero `slower`, otherwise `inconclusive`; fewer than 20 valid pairs yields `too-few-pairs`. A passing A/A control is a prerequisite, not a calibration of the method's false-positive rate or proof of a general speedup.

The report also records total module bytes, the selected hosting-directory bytes and, with `-MeasurePackageSize`, compressed `.nupkg` bytes. These static sizes are separate from timing. `-ProfileName coldstart-1000` selects the longer gate profile. `-Arguments @{ ProfileImport = $true }` profiles one extra child import per variant, outside timed samples. [Invoke-RunProfile.ps1](scripts/Invoke-RunProfile.ps1) offers `-List`, `-WhatIf`, argument overrides and `-Profiler`; that switch profiles the target script's orchestration, rather than attaching CLR collectors or profiling child imports. [New-RunProfile.ps1](scripts/New-RunProfile.ps1) creates validated data-only profiles. Calling a profile or benchmark directly bypasses the A/A gate.

For the local Windows plus Debian/Alpine x64/ARM64 matrix:

```powershell
./scripts/Invoke-ColdStartMatrix.ps1 -MaxConcurrency 2
# Container reports use the shared temporary report root locally.
. ./scripts/ReportPaths.ps1
$containerReports = Get-QuietReportRoot -WorkspaceRoot (Get-Location).Path -Category coldstart-containers
./scripts/Show-ColdStartMatrixReport.ps1 -ContainersDirectory $containerReports
```

`-Targets windows,debian-x64,alpine-x64,debian-arm64,alpine-arm64` selects a subset. Windows runs first; Linux targets use bounded concurrency. The matrix retains per-target failures and continues; completion is not a performance pass. [Get-CiImageForDevelopment.ps1](scripts/Get-CiImageForDevelopment.ps1) pulls an already published, fingerprint-checked image by digest; it never builds one. Podman, matching images and usable guest architectures are prerequisites. [Invoke-ContainerColdStart.ps1](scripts/Invoke-ContainerColdStart.ps1) stages a candidate and starts a monitored guest worker. Direct gate/benchmark calls do not create a monitoring window; arrange the required visible monitoring for local campaigns.

Details: [A/B protocol](docs/README-ab_testing.md), [R2R walkthrough](docs/README-readytorun_profiling.md), [run profiles and tooling qualification](docs/README-run-profiles.md).

## GitHub workflows and gates

| Workflow | Trigger and actual responsibility |
| --- | --- |
| [core-ci.yml](.github/workflows/core-ci.yml) | Path-filtered PRs and `main` pushes for Core/tests/shared infrastructure; calls reusable CI with `suite: All`, including Git consumers. |
| [git-ci.yml](.github/workflows/git-ci.yml) | Path-filtered PRs and `main` pushes for Git/tests; calls reusable CI with `suite: Git`. |
| [ci.yml](.github/workflows/ci.yml) | Reusable/manual Windows/Linux matrix, evidence aggregation and revision-bound `qualified_sha` gate. |
| [quietcli2-readytorun.yml](.github/workflows/quietcli2-readytorun.yml) | Manual informational R2R comparison: one Windows job plus four Debian/Alpine x64/ARM64 container jobs. It does not gate qualification or publication. |
| [qualification.yml](.github/workflows/qualification.yml) | Manual full-Git entry point on a self-hosted Linux x64 Podman/KVM runner, using `QUIETCLI_QUALIFICATION_CONFIG`. The underlying runner currently refuses exhaustive certification; see below. |
| [publish-psgallery.yml](.github/workflows/publish-psgallery.yml) | Reusable/manual packaging after `All` qualification of the exact SHA; rebuilds/rechecks packages. Manual `publish=false` prepares and validates artifacts only; publication requires its explicit input and the `psgallery` environment. |
| [preview-psgallery.yml](.github/workflows/preview-psgallery.yml) | Applicable upstream `develop` pushes request automatic Core preview publication through the same qualified packaging workflow; manual dispatch defaults to preparation only. |

Reusable CI has **ten test/evidence entries**: six Windows entries (x64/ARM64, stable/.NET 10 with `Process` and `InProcess`, preview/.NET 11 with `InProcess`) and four native Linux entries (Debian glibc and Alpine musl, x64/ARM64, `Auto`). Pinned host receipts and actual PowerShell/CLR/engine/RID checks reject architecture substitution. [Linux image jobs](docs/ci/linux-images.md) build/reuse fingerprinted toolchains on matching native runners; developer image pulls do not publish images.

Core/All requests PowerShell/CLR profiling on every entry. The Windows x64 stable `InProcess` entry additionally requires both the complete `RunProfiles` suite and its mutation catalogue; this does not qualify the tooling on other platforms. Git-only CI keeps Core profiling outside its scope. The `performance-results` job verifies all ten revision-bound bundles and publishes the combined Markdown/JSON report. The gate requires Windows, Linux and report aggregation to succeed before emitting `qualified_sha`; Gallery packaging requires that SHA to equal `github.sha`.

GitHub CI explicitly passes **`-SkipTty`**: native TTY/PTY execution and its standalone C property/fuzz/mutation campaigns are excluded, not passed. This is also the publication workflow's configured gate scope. R2R workflow comparison errors/noisy controls are retained as informational warnings; inspect the reports rather than inferring a speedup from a green job. Build/setup failures and missing required upload artifacts can still fail that workflow. It neither publishes the candidate nor covers Windows ARM64 R2R.

For explicit remote use, [Invoke-RemoteWorkflow.ps1](scripts/Invoke-RemoteWorkflow.ps1) lists runs with `-Status` or dispatches a selected workflow with `-Ref`; [Watch-GitHubRun.ps1](scripts/Watch-GitHubRun.ps1) monitors an existing `-RunId` without dispatching, retrying or cancelling it. Neither a configured workflow nor a local run establishes remote success.

## Native campaigns, evidence and limits

Local suites include TTY by default; `-SkipTty` reproduces the reduced GitHub scope. The separate [native PTY campaign](FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/Invoke-PtyMutation.ps1) and `Invoke-ContainerCi.ps1 -Suite Mutation -ExpectedRuntimeIdentifier <RID>` remain available with visible monitoring. Full Linux native C qualification requires the 43-assertion baseline (including six generated property groups), 20,000 libFuzzer executions with ASan/UBSan and detection of all 31 targeted mutants. Windows ConPTY uses the separate C# implementation. [Assert-PtyQualification.ps1](scripts/Assert-PtyQualification.ps1) rejects missing/incomplete phases. Catalogue mutation coverage is bounded; survivors, invalid mutants, crashes and timeouts are distinct failures, never kills. See [native findings and reproduction](docs/README-native-pty-and-llvm-fuzzing.md).

[Invoke-GitQualification.ps1](scripts/Invoke-GitQualification.ps1) reports inventory gaps and currently ends with `QualificationRunnerNotImplemented` even after prerequisites pass. The full-Git workflow is therefore an incomplete entry point, not evidence of exhaustive command/option/version/platform coverage. Keep it separate from passing companion scenarios.

Suite/container reports normally use the system temporary directory under `QuietCli2/<workspace-id>/<category>/<run-id>`; CI uses `artifacts/<category>`. Preserve summaries, source identities, seeds, failures and raw/converted traces. Direct cold-start gates instead default to `artifacts/coldstart` (override with `-ArtifactsDirectory`); matrix summaries use `artifacts/coldstart-matrix`. `Show-ColdStartReport.ps1` and `Show-ColdStartMatrixReport.ps1` read saved JSON without rerunning measurements; point them at the actual report locations.

CI uploads per-entry evidence and combined performance results even on failure, with 30-day retention. Export durable evidence before temporary storage or artifact retention expires. Dated [audits](docs/README.md#dated-audits-and-evidence) establish only their recorded revisions and environments. Release claims must retain every platform, campaign and exclusion boundary above.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
