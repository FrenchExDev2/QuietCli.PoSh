# Resources

The [generated inventory and source dependencies](docs/resources/README.md) describes the files declared by Core's `resources/dependencies.lock.json`, their origins and the code that consumes or prepares them.

`dotnet restore` resolves project references. It does not prepare the module's ignored resource payloads. `Initialize-Workspace.ps1` delegates this preparation to `Restore-CoreResources.ps1`; module import itself never downloads files. Native PTY payloads are built separately by `Build-PtyBridge.ps1`.

Automation that needs a particular resource calls `Ensure-QuietResource` from `scripts/Resources.ps1`. It verifies the declared hash, restores only the corresponding package if needed, verifies the resulting bytes, and optionally loads the required managed type. An already loaded assembly must match the pinned hash; an incompatible assembly requires a fresh process. Workflow documentation uses this function for YamlDotNet in development and CI, without relying on an earlier workflow step.

PowerShell production archives have a separate [availability audit](docs/scripts/Test-PowerShellReleaseAvailability.md) and [guarded lock updater](docs/scripts/Update-PowerShellCiLock.md). The reviewed host lock selects GA 7.7.0 for Windows/Linux glibc x64/ARM64; downloaded archives are SHA-256 verified before extraction. Next-version preview execution is opt-in and has no invented hash while unpublished. An existing PowerShell process cannot change its CLR/version in place; prepared executables start fresh sessions without changing profiles or the machine installation.

Alpine 3.24 and edge currently publish only native 7.6.9-r0, and Microsoft publishes no 7.7.0 musl ARM64 archive. The explicitly accepted `PowerShellException` retains that package and its separate .NET 10 runtime. Debian uses GA 7.7.0. SDK/OS pins are preserved. Compile-time SMA references use 7.7.0 on net11.0 and compatible servicing 7.6.10 on net10.0.

The CI companion catalogue uses the same pinned YAML reader from `scripts/lib/CiCompanions.psm1`.
It prepares its own parser dependency and loads no product engine. Preview entry points return
before preparation; image PlanOnly mode may prepare this parser but performs no native or registry operation.

```powershell
#Objective: Preview preparation of the pinned workflow parser.
. ./scripts/Resources.ps1
Ensure-QuietResource -RelativePath resources/yaml/YamlDotNet.dll -AssemblyType YamlDotNet.Serialization.DeserializerBuilder -WhatIf

#Objective: Review and regenerate the declared resource inventory.
./scripts/Sync-ResourcesReadme.ps1 -Apply -Confirm
./scripts/Test-Resources.ps1
```

Missing resources remain missing under `-WhatIf`; a consumer that needs them cannot complete its check until they are prepared. Existing verified files are reused. Resources absent from the lock, invalid hashes and incompatible loaded assemblies fail explicitly. Source-built PTY resources are never silently downloaded or built by this helper.

GitHub uses the shared `.github/actions/cache-resources` action after checkout in jobs that prepare module resources. The OS and resource-lock hash form the resource cache key. It also caches checksum-addressed PowerShell ZIPs under `.cache/powershell-hosts` on Windows, with separate architecture/channel/host-lock keys so stable and preview entries cannot compete for the same immutable cache entry. Consumers still verify every archive or extracted resource hash. A cache miss falls back to ordinary preparation. Linux job containers also cache NuGet packages using project, central-package, build-property and SDK inputs. Caches never replace integrity checks and are not required for local execution. See [GitHub's cache action](https://github.com/actions/cache) for cache lifecycle and PR access boundaries.

~~~mermaid
flowchart TD
    W[Local automation or GitHub job] --> E[Ensure-QuietResource]
    E --> V{Declared bytes match?}
    V -- Yes --> L[Reuse or load matching assembly]
    V -- No --> P{ShouldProcess approves?}
    P -- No --> N[Planned: consumer cannot proceed]
    P -- Yes --> R[Restore selected package]
    C[Optional archive cache] --> R
    R --> H[Verify resource SHA-256]
    H --> L
    D[Lock and source references] --> G[Sync-ResourcesReadme -Apply]
    G --> M[docs/resources/README.md]
    M --> T[Test-Resources]
    T --> K[Shared checks and Commit-Workspace]
~~~

`Sync-ResourcesReadme.ps1` is deterministic and supports `-Apply -WhatIf`/`-Confirm`. Its default is check-only. `Commit-Workspace.ps1` runs the `Resources` registry check for the working tree or exported prepared index. `-NoResourcesCheck` or `-SkipCheck Resources` explicitly reports an omission. `-NoSyncChecks` skips documentation checks but preserves the independent script safety gate.

The generated reference list is source inspection, not exhaustive static data-flow analysis. Dynamic whole-module copy paths and source-built/instruction payloads have separate documented owners. Resource readiness remains the responsibility of the verifier/build/consumer, not of the documentation gate.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

Intermediate Docker layers use a separate checkout-owned .cache/ci-buildkit cache. These toolchain-only layers are outside source identity and pinned archive inventories; final image provenance and pinned payload verification remain required. A final registry hit is probed before restoring any intermediate layer cache.
