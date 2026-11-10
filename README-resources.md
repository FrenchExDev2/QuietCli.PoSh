# Resources

The [generated inventory and source dependencies](docs/resources/README.md) describes the files declared by Core's `resources/dependencies.lock.json`, their origins and the code that consumes or prepares them.

`dotnet restore` resolves project references. It does not prepare the module's ignored resource payloads. `Initialize-Workspace.ps1` delegates this preparation to `Restore-CoreResources.ps1`; module import itself never downloads files. Native PTY payloads are built separately by `Build-PtyBridge.ps1`.

Automation that needs a particular resource calls `Ensure-QuietResource` from `scripts/Resources.ps1`. It verifies the declared hash, restores only the corresponding package if needed, verifies the resulting bytes, and optionally loads the required managed type. An already loaded assembly must match the pinned hash; an incompatible assembly requires a fresh process. Workflow documentation uses this function for YamlDotNet in development and CI, without relying on an earlier workflow step.

```powershell
#Objective: Preview preparation of the pinned workflow parser.
. ./scripts/Resources.ps1
Ensure-QuietResource -RelativePath resources/yaml/YamlDotNet.dll -AssemblyType YamlDotNet.Serialization.DeserializerBuilder -WhatIf

#Objective: Review and regenerate the declared resource inventory.
./scripts/Sync-ResourcesReadme.ps1 -Apply -Confirm
./scripts/Test-Resources.ps1
```

Missing resources remain missing under `-WhatIf`; a consumer that needs them cannot complete its check until they are prepared. Existing verified files are reused. Resources absent from the lock, invalid hashes and incompatible loaded assemblies fail explicitly. Source-built PTY resources are never silently downloaded or built by this helper.

GitHub uses the shared `.github/actions/cache-resources` action after checkout in jobs that prepare module resources. The OS and resource-lock hash form the cache key. Only `.cache/nuget-resources` archives are cached; consumers still verify extracted resource hashes. A cache miss falls back to ordinary preparation. The cache never replaces integrity checks and is not required for local execution. See [GitHub's cache action](https://github.com/actions/cache) for cache lifecycle and PR access boundaries.

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
