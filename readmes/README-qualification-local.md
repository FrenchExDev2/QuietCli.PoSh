# Local tests and reports

[Tests and qualification](README-qualification.md) · [Hosted qualification on GitHub](README-qualification-github.md) · [Development](README-development.md)

Run the commands from the monorepo root in PowerShell Core 7.6+ with the pinned SDK and the native prerequisites for the selected suite. Follow the [workstation setup](README-development-workstation.md) if you need those tools.

## Local suites

Prepare the checkout and build. Use a fresh PowerShell process with its normal profile before testing rebuilt assemblies.

```powershell
./scripts/Initialize-Workspace.ps1 -Restore
./scripts/Build-Workspace.ps1
```

Choose the relevant suite. Run the commands below independently.

```powershell
./scripts/Invoke-WorkspaceCi.ps1 -Suite Core -SkipBuild
./scripts/Invoke-WorkspaceCi.ps1 -Suite Core -SkipBuild -Case 'solution build catalogue*'
```

The [workspace launcher](../docs/scripts/Invoke-WorkspaceCi.md) opens a dedicated visible PowerShell monitor on Windows, prints the report and reopening paths, and closes the monitor after saving a terminal summary. `-SkipBuild` reuses matching, integrity-checked binaries. `-TimeoutSeconds` bounds a run and `-RunDirectory` selects a fresh output directory. `-Headless` is for CI.

For a prepared local Linux image, use the [container launcher](../docs/scripts/Invoke-ContainerCi.md) with the image, platform, suite and expected RID. Runtime selection uses `-ContainerRuntime`, then the checkout's `.env`, then Podman-first discovery. The launcher supervises the guest through the local Windows monitor. The saved result covers the guest, hosting mode and suite that actually ran.

The static metadata check validates `TestKind` and `Dependencies` before case filtering. The [classification and concurrency contract](../docs/README-test-classification-and-concurrency.md) describes the metadata and [commit-suite boundaries](../docs/testing/commit-workspace.md) explains the role of physical temporary repositories. Local commit and push commands run their own repository checks, independently of the companion suites.

| `-Suite` | Development scope |
| --- | --- |
| `All`, `Core`, `Git` | All discovered companions (Core, Git and Vagrant), Core only, or Git only. See the hosted guide for dependent consumer checks. |
| `Import`, `Integration` | Fresh-process import measurements; import diagnostics and eight controlled Core-only Git fixture states. |
| `RealStatus` | Core callbacks against explicitly selected existing repositories; requires `-RepositoryConfig` pointing to a UTF-8 JSON array of repository paths. |
| `Recall`, `RecallMutation`, `RecallLarge` | Capture/replay regressions, targeted mutations, or actual 4 GiB + 1 MiB streaming and ZIP64 evidence. `RecallLarge` requires 12 GiB free disk space. |
| `ConfigurationDelivery` | YAML schema, unique deliveries, tokenization, historical SQLite fixtures and targeted mutations. |
| `Vagrant` | Deterministic parser/handler fixtures and 200 seeded fragmented-stream cases; no Vagrant installation or real provider. Set `QUIETCLI_VAGRANT_PARSER_MUTATION=1` for the targeted parser catalogue. |
| `AgentInstructions`, `Script` | Distributed agent instructions and examples; reusable scripts, factories, generated inputs and targeted mutations. |
| `Tooling` | Repository automation, packaging and source checks, independently of product All. |
| `RunProfiles`, `RunProfilesMutation` | Complete profiling-tooling suite or its entire targeted mutation catalogue. |
| `GalleryPreview` | Preview-version properties, malformed inputs, staged manifests, offline package installation and targeted mutations. |

For example, `./scripts/Invoke-WorkspaceCi.ps1 -Suite RecallMutation -SkipBuild` selects one campaign. Use `-TimeoutSeconds 1800` for `RecallLarge`, `600` for `RunProfiles`, and `3300` for `RunProfilesMutation`. `-Case <wildcard>` and `-StopOnFirstFailure` are development controls. Treat their results as scoped to the selected and completed cases.

Recall also provides `Compare-QuietRecallAnalysis` (independent analysis states and projected differences), `Export-QuietRecallFixture` (capture plus a skeleton requiring independent expectations), and `Reduce-QuietRecall` (bounded failure-preserving reduction, without a global-minimality claim). See the [Recall contract](../docs/README-recall.md).

## Real provider and interactive console checks

Run the opt-in checks from a Windows desktop with matching built binaries:

```powershell
./src/Vagrant/test/FrenchExDev2.QuietCli.Vagrant.Tests.PoSh/Invoke-ProviderSmoke.ps1
./src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-UiConsoleSmoke.ps1
```

Both use the shared visible monitor and save terminal reports before their windows close. The provider
check requires existing Vagrant 2.4.9 and a reachable Docker-compatible engine. It builds the copied
two-machine fixture, so network access may be needed; it installs no tools or plugins. Its unique
containers are removed, with an independent absence check. Downloaded base images/build caches can remain.
The console check uses a real unredirected window, changes its dimensions without changing lane data,
then verifies native cancellation, child termination and subsequent UI reuse. Physical Ctrl+C is a separate check.

See the [recorded provider/UI audit](../docs/audits/2026-11-09-provider-ui-qualification.md) for executed
stable/preview scopes, mutation outcomes and the unresolved Alpine distribution-RID mismatch.
These checks supplement the release matrix; they do not authorize publication.

## Core performance evidence and profiling

Core/All includes fresh-session import samples, ten import diagnostic controls and eight owned repository states: unborn, clean, mixed, conflict, detached, linked worktree, submodule and bulk. The controlled workload uses Core callbacks without loading the Git companion. [Assert-CoreIntegrationEvidence.ps1](../scripts/Assert-CoreIntegrationEvidence.ps1) checks measurements, independent byte/record/hash oracles, damaged-input cases and targeted assertion mutants.

```powershell
# Focused integration plus a separate PowerShell/CLR diagnostic pass.
./scripts/Invoke-WorkspaceCi.ps1 -Suite Integration -SkipBuild -Profiler
```

`-Profiler` is supported for `Core`, `All` and `Integration`, including the corresponding [container launcher](../scripts/Invoke-ContainerCi.ps1). [Initialize-Profilers.ps1](../scripts/Initialize-Profilers.ps1) prepares checksum-pinned **Profiler 4.3.0** and **dotnet-trace 10.0.750501** in a private cache, without global installation. Supply `-ProfilerModulePath` and `-ClrProfilerPath` to use already prepared tools; explicit initialization with `-OutputDirectory <cache> -Offline` verifies cached archives without downloading.

[Invoke-CoreProfiling.ps1](../scripts/Invoke-CoreProfiling.ps1) runs after ordinary timing samples. It records PowerShell line self/inclusive durations and a speedscope view, then collects raw CLR `.nettrace` files and converted speedscope traces for the owned PowerShell PID and, in `Process` hosting, the separate engine PID. Missing collectors, conversions or expected files fail the requested pass. Line wall times and managed frame-name counts are different observations; they are not additive CPU percentages.

[New-CoreEvidenceBundle.ps1](../scripts/New-CoreEvidenceBundle.ps1) binds reports and traces to the revision/run and checks file hashes. [New-CorePerformanceReport.ps1](../scripts/New-CorePerformanceReport.ps1) produces readable `PERFORMANCES_RESULTS.md` and structured JSON, preserving missing evidence as a failure. See [Core performance definitions and reproduction](../src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/PERFORMANCES.md).

## ReadyToRun and cold-start comparisons

Use the [ReadyToRun walkthrough](../docs/README-readytorun_profiling.md) to prepare a separate candidate and run the comparison. The [A/B protocol](../docs/README-ab_testing.md) explains the A/A noise gate, timing intervals and verdicts. Keep diagnostic instrumentation outside the timed pairs. Use [run profiles](../docs/README-run-profiles.md) for named samples and profiling-tool qualification.

## Native TTY and PTY campaigns

Local suites include TTY by default; `-SkipTty` selects the same TTY exclusion as GitHub CI. The separate [native PTY campaign](../src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/Invoke-PtyMutation.ps1) and `Invoke-ContainerCi.ps1 -Suite Mutation -ExpectedRuntimeIdentifier <RID>` remain available with visible monitoring. Full Linux native C qualification requires the 43-assertion baseline (including six generated property groups), 20,000 libFuzzer executions with ASan/UBSan and detection of all 31 targeted mutants. Windows ConPTY uses the separate C# implementation. [Assert-PtyQualification](../scripts/lib/Assert-PtyQualification.psm1) rejects missing/incomplete phases. Catalogue mutation coverage is bounded; survivors, invalid mutants, crashes and timeouts are distinct failures, never kills. See [native findings and reproduction](../docs/README-native-pty-and-llvm-fuzzing.md).

## Read the local reports

Start from the path printed by the launcher. The default suite and container report root is under the system temporary directory, `QuietCli2/<workspace-id>/<category>/<run-id>`. Open the terminal summary and the suite reports to check completion, case counts, failures and exclusions. For containers, check the guest exit code and actual RID. Retain the revision and source hashes, binary identity, PowerShell and CLR versions, hosting mode, seed and relevant diagnostic files if you need to reproduce a result.

Direct cold-start gates default to `artifacts/coldstart` and accept `-ArtifactsDirectory`. Matrix summaries use `artifacts/coldstart-matrix`. [Show-ColdStartReport](../docs/scripts/Show-ColdStartReport.md) and [Show-ColdStartMatrixReport](../docs/scripts/Show-ColdStartMatrixReport.md) read saved reports. Pass the actual container report root to `Show-ColdStartMatrixReport.ps1 -ContainersDirectory` when reading the local matrix.

A focused selection, cancellation, or timeout establishes only the result recorded for that scope. Use the [hosted guide](README-qualification-github.md) for required matrix evidence. Dated [audits](../docs/README.md#dated-audits-and-evidence) identify their original revisions and environments.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
