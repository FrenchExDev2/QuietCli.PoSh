# Windows 11 ARM64 CI

The PR workflow now runs two independent Windows jobs: `windows-latest` / `win-x64` and `windows-11-arm` / `win-arm64`. Both build with the pinned .NET SDK and then run the same Core and Git suites, without skipping scenarios on ARM64. Artifacts are separated by RID.

The `windows-11-arm` target is a GitHub-hosted virtual machine, not a local OCI image. See the [official runner list](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and the [published Windows 11 ARM64 image contents](https://github.com/actions/runner-images/blob/main/images/windows/Windows11-Arm64-Readme.md). This label evolves; the report retains the version actually used. It does not provide a reproducible system-disk lock. Repository eligibility and runner billing terms must be checked before enabling it remotely.

`Build-Workspace.ps1` publishes the C# engine twice: `lib/engine/win-x64` with `PlatformTarget=x64`, then `lib/engine/win-arm64` with `PlatformTarget=ARM64`. Each distribution contains the assembly and its native Windows apphost. Publication is framework-dependent: the .NET 11 RC runtime for the corresponding architecture is still required. This is C# executed by the ARM64 JIT, not a NativeAOT publication.

The PE headers of the assembly and apphost are verified independently: `0x8664` for x64 and `0xAA64` for ARM64. Their hashes and compilation settings are recorded in the build manifests. Packaging requires both distributions and includes them in the Core module.

`Invoke-WorkspaceCi.ps1 -ExpectedRuntimeIdentifier win-arm64` requires this architecture for PowerShell and the isolated engine process, as well as a `win-arm64` publication. The facade selects the directory for the current RID and starts its apphost. An emulated x64 execution fails. Reports record the RID, OS/process architectures, OS description, machine name, engine PID, engine assembly hash and build identity. SQLite is shipped under `resources/runtime/runtimes/win-arm64/native`. Windows PTY uses ConPTY.

On a prepared Windows ARM64 host:

```powershell
# Goal: build and test locally on ARM64, with a visible monitoring window.
./scripts/Invoke-WorkspaceCi.ps1 -ExpectedRuntimeIdentifier win-arm64
```

An ISO alone cannot run CI: an installed guest with PowerShell 7.6+, .NET 11 RC and Git, an isolated working disk and a report transport are required. Do not relabel an x64 base as ARM64. This workflow does not modify any user disk or existing database.

The reference retrieved from GitHub is the documentation for the `windows-11-arm` runner, not a downloaded local disk. This job therefore uses the GitHub image directly. The workflow is configured; no ARM success is claimed until a report from that runner is available.
