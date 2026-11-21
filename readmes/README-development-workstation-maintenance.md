# Development workstation maintenance

[Workstation setup](README-development-workstation.md) · [Local tests and reports](README-qualification-local.md)

Use the commands from the monorepo root to verify the workstation installer with disposable targets and remove expired smoke-run artifacts.

## Run an installation smoke test

From a Windows host with working Podman, run the companion smoke launcher:

```powershell
./src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-DevelopmentWorkstationSmoke.ps1

# Windows controls and wrkflw archive/list/validation smoke only; no Podman required.
./src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-DevelopmentWorkstationSmoke.ps1 -Targets Windows
```

It opens the shared visible monitor. Windows exercises read-only control modes, installs only the
reviewed wrkflw binary in an external toolchain cache, and checks real job listing plus valid/invalid
workflow definition exit codes without executing workflow steps. Debian, Ubuntu,
Alpine and Fedora perform real package/tool installations inside disposable containers, with a
read-only source snapshot. Editor and nested Podman installation are excluded in those guests.
The guest checks activation, a second idempotent installation and a small sanitizer/linker probe;
this smoke probe is separate from the product's complete native fuzz/mutation qualification.

Every new run records `ownership.json`: source workspace, worker PID and creation time, host/user,
terminal state and exact labelled disposable image/container names. A live `run.lease` protects the
run independently of timestamps. Completed runs release their own inactive containers and images
without `--force` or `prune`; base images and resources in use are preserved. Reports and failure
diagnostics remain available under the printed temporary run directory. Monitor errors are saved
to `monitor*.stderr.log`; repeated monitor failure is bounded and stops the owned worker.

## Clean up expired smoke runs

```powershell
# Read the cleanup decisions before removing anything.
./scripts/Remove-DevelopmentWorkstationRun.ps1 -WhatIf
# Normal policy: retain seven days and at least the three latest runs.
./scripts/Remove-DevelopmentWorkstationRun.ps1
```

The enclosing workspace's `scripts/Invoke-ArtifactsCleanup.ps1` also calls this cleanup, including
when its `.artifacts` directory is absent. Use `-Category workstation` to select these runs or
`-SkipQuietCliWorkstation` to leave them out. Active, foreign, linked or unverifiable runs are kept;
legacy runs without an ownership receipt are reported as `Unmanaged` and preserved. User tool
installations under LocalAppData or `~/.local/share` are never treated as disposable smoke artifacts.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
