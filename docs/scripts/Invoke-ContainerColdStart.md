# Invoke-ContainerColdStart.ps1

## Purpose and usage

Local monitored launcher for a private cold-start container. GitHub invokes the worker directly.

```powershell
./scripts/Invoke-ContainerColdStart.ps1 -Image <verified-local-id> -Platform debian -CandidateModule <manifest> -ExpectedRuntimeIdentifier linux-x64 -ContainerRuntime docker
```

WorkspaceRoot is optional; Image, Platform and CandidateModule are required. Platform accepts debian/alpine. CandidateLabel defaults to readytorun. ContainerRuntime accepts Docker/Podman; empty discovers Docker then Podman using Get-Command. TimeoutSeconds defaults to 1200. Headless is retained for compatibility; the GitHub profiling workflow no longer uses this launcher.

## Dependencies and side effects

Uses Common.ps1, Invoke-ContainerColdStartWorker.ps1 and Watch-Tests.ps1. Starts a hidden background worker and a visible read-only monitor on Windows; saves reports under the external coldstart-containers report root. Terminal windows close automatically. Requires an already-prepared local image and candidate; no pull, build or publication is implicit.

## Critical review

- `scripts/Invoke-ContainerColdStart.ps1:39` declares the selected engine and forwards it to the worker; both local Docker and Podman are supported.
- The launcher treats infrastructure crash/timeout as errors. Informational measurement verdicts remain saved evidence rather than release qualification.
- A local monitor is required outside headless compatibility mode; GitHub uses its own logs and direct worker instead of launching a desktop supervisor.

## Verdict

Workstation supervision only. Keep GitHub orchestration in its workflow and share the worker.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Launches Invoke-ContainerColdStartWorker.ps1 in the background with a visible monitor, local only.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
