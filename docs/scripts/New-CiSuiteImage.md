# New-CiSuiteImage.ps1

ProbeOnly with RegistryCache returns final CacheHit without a pull, build or container-daemon call. It rejects PublishCache. CI probes before restoring intermediate layers: a verified final image hit downloads no BuildKit cache. PlanOnly stays offline.

Registry reuse probes the final suite image before preparing any parent. A verified hit pulls only that final image; a miss prepares the base and overlays in the same job. The automatic All path uses that one image for Core, then isolated parallel companions. There is one image-producer matrix, not separate base/suite producer runners.

`-ResolveOnly -RegistryCache` is the producer path: verify an existing registry configuration and return its immutable reference without pulling layers. A miss follows the normal build/publication path. A metadata reference is not a local Docker image ID; execution resolves/pulls its verified final image separately.

Resolves `-Suite <name>|All` image requirements from `build/companions.yml` through
`scripts/lib/CiCompanions.psm1`. Core's test suite requires Core and Git, so Debian Core tests use
the pinned Git overlay rather than distro Git 2.39. Vagrant's current fixture tests declare no
Vagrant executable image layer.

```powershell
./scripts/New-CiSuiteImage.ps1 -Suite Core -RuntimeIdentifier linux-arm64 -PlanOnly
./scripts/New-CiSuiteImage.ps1 -Suite All -RuntimeIdentifier linux-x64 -RegistryCache -ContainerRuntime docker -WhatIf
```

`WorkspaceRoot` selects the checkout. `PlanOnly` returns the final content/fingerprint plan without
native execution, registry lookup or credential access; the YAML reader may prepare its pinned
parser resource. WhatIf on preparation returns before configuration/resource preparation.
`RegistryCache`, `PublishCache` and `ContainerRuntime` retain the existing image engine semantics.
Publication requires its explicit switch and authorized develop event; PR fallback never requests
it. Preparation can build/pull/tag images and write receipts. See [the library](lib/CiCompanions.md).

<!-- script-contract:begin -->
## Execution contract

Purpose: Resolves or builds the image layers declared for a companion test suite.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
