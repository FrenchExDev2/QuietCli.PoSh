# Invoke-GitHubCi.ps1

WorkspaceRoot and explicit RunDirectory values are normalized against the caller location before any worker runs. Product builds remain native-RID-only; Tooling, Distribution and GalleryPreview retain full IL distribution inputs. RunProfilesMutation skips product compilation. GitHub rejects Partial or Incomplete suite summaries even when their terminal state says Success.

## Scoped CI execution

Builds the selected suite dependency closure and only the expected native RID when a build is requested. Tooling remains separate; GitHub-only/headless restrictions, native RID checks and complete-run evidence requirements remain.

Ordinary companion and All invocations validate the complete case catalogue and inert manifest scheduling declarations before build/test effects. The same plan and bounded isolated batches are consumed by the owning runner on runners, job containers and Docker fallback. Each case child reuses the built checkout/image and receives one internal slot, private configuration/database/reports and the selected host/RID/TTY expectations. No extra image build/pull is introduced. See [classification and concurrency](../README-test-classification-and-concurrency.md).

GitHub-only entry point for the existing companion suites. It requires `GITHUB_ACTIONS=true` and
executes `Invoke-TestWorker.ps1` directly in the current PowerShell process, whether the job runs on
a native Windows runner or inside a Linux job container. It starts no desktop monitor or local
supervision process. Existing test/native fixtures may still create their own required processes.

Standard WhatIf/Confirm support guards the build/test orchestration before any artifact directory,
build, profiling preparation or container starts. WhatIf still requires the GitHub context and a valid
suite; AutomationContracts.Tests.ps1 verifies no-write preview with a synthetic GitHub context.

```powershell
./scripts/Invoke-GitHubCi.ps1 -Suite Core -SkipBuild -SkipTty -ExpectedRuntimeIdentifier linux-x64
```

Optional `-Image <verified-local-ID> -Platform debian|alpine` selects Docker fallback. It uses the
shared container transport with `docker`, stages the checked-out sources/binaries and invokes this
same GitHub entry inside the networkless container. It never builds/publishes an image or calls the
local desktop launcher. `-TimeoutSeconds` bounds this fallback guest; GitHub step/job timeouts bound
direct execution.

```mermaid
flowchart LR
    A[GitHub step] --> I{Image parameter supplied?}
    I -- No --> W[Shared test worker in the current process]
    I -- Yes --> D[Shared Docker transport]
    D --> C[Networkless container]
    C --> E[Same GitHub entry without Image]
    E --> W
    W --> R[Saved terminal report and direct CI logging]
```

`-WorkspaceRoot` defaults to the repository containing the script. `-RunDirectory` defaults to a
new directory under `artifacts/tests`. `-ExpectedRuntimeIdentifier` validates the selected host and
engine. `-SkipTty` explicitly excludes terminal campaigns. `-Platform` is required with `-Image`.
The fallback `-TimeoutSeconds` default is 1800 seconds; it does not override GitHub's job deadline.
`-MaxConcurrency` accepts `1..32`, defaults to `min(4, processor count)`, and is forwarded through both direct and fallback-container execution to bound parallel-safe internal test campaigns.

`-Profiler`, prepared profiler paths, `-RunDirectory`, `-SkipBuild` and the dynamic `-Suite` contract
retain the shared worker semantics. Reports remain under `artifacts/tests` or the explicitly selected
run directory. Failure prints the terminal state and bounded failed cases before returning an error.
The prepared profiler paths are supplied as `-ProfilerModulePath` and `-ClrProfilerPath`; this entry
does not install those tools implicitly. `-SkipBuild` is passed after the workflow's explicit
`Build-Workspace.ps1 -Configuration Release -ReadyToRun -ReadyToRunRuntimeIdentifier <tested-rid>` step.
Without `-SkipBuild`, this GitHub-only entry also builds Release ReadyToRun for the expected RID
(or the actual host RID when omitted). The package job separately precompiles all release RIDs.

Local development uses `Invoke-WorkspaceCi.ps1` or `Invoke-ContainerCi.ps1`. The companion
`Invoke-GitHubCiSmoke.ps1` supplies the normal local monitoring window while testing the GitHub entry
inside an existing Docker toolchain image; it does not claim hosted Windows/ARM qualification.



## Shard execution and completion

Only an explicit RunProfilesMutation shard context may return intermediate partial evidence. Before worker effects, the entry validates both environment controls, index/count range, exact GITHUB_SHA and direct non-profiled execution. Afterward it reads bounded strict UTF-8 JSON and requires the expected source-controlled partition, green baseline, identical source hash/revision, fixed seed/iterations and Killed-only results.

Exactly one successful RunProfiles mutation summary must match that report: Partial=true, Incomplete=false, no failures/skips and consistent counts. The returned entry result retains Partial=true. Product partial/incomplete summaries and a partial mutation run without valid shard controls remain rejected. The dependent completion job still requires both current-attempt artifacts and their exact complete union; no shard emits complete qualification.

The real GitHub entry is tested in owned child processes with synthetic worker reports: both shards accepted, damaged/stale evidence and product partials rejected, complete product behavior preserved, WhatIf effect-free, and mutations reproducing the old rejection or removing the product guard detected. This validates the entry boundary without claiming a new hosted campaign.

## Critical review and verdict

`scripts/Invoke-GitHubCi.ps1:49` validates the context before effects; the final shard branch reuses Assert-QuietMutationShard, also consumed by the complete aggregator. Partition acceptance therefore has one implementation. Existing host/RID, failure-state and full product qualification checks remain active. See [the workflow contract](../ci/github/script-tooling-ci.md#shard-execution-boundary).
<!-- script-contract:begin -->
## Execution contract

Purpose: GitHub-only test entry point; executes directly in the selected runner or job container.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
