# Declarative CI companions and test suites

Invoke-QuietCiSuiteImage -ProbeOnly -RegistryCache returns final CacheHit after configuration verification, without daemon calls or image preparation. A miss never builds in this mode. Core selects only Core and the base image; Git executable fixtures remain independent of the Git module.

Registry preparation first resolves the final suite image and attempts a CacheOnly pull with identity verification. A hit returns immediately without preparing parents. A miss prepares the base and overlays in the same producer job; only the final verified image is required for execution. The retained credential is restored between probes and layers, then cleared on exit.

Producer-only ResolveOnly verifies the final registry configuration without pulling any layer. A miss still builds/publishes through the same reviewed layer path. Owned fixtures reject any attempt to prepare parents on either a final-image pull hit or a metadata-only producer hit.

`scripts/lib/CiCompanions.psm1` reads `build/companions.yml`. Import declares functions only;
reading configuration uses the checksum-pinned YamlDotNet resource through `Resources.ps1`,
without importing the QuietCli engine. Missing parser resources are prepared by that consumer.

`companions` describes product dependencies and image participation (`base`, `overlay`, `none`).
`suites` separately declares an exported test command, its test project and required companions.
An integration suite can require Core and Vagrant while keeping Core's product dependencies empty.
Its dedicated test module must exist and export the declared command. Running two functional suites
does not establish an integration test between them.

`Read-QuietCiCompanions` rejects duplicate YAML keys, unknown fields/names, malformed policies,
missing test manifests/exports, dependency cycles and missing or multiple base declarations.
`Resolve-QuietCiCompanions` selects one suite or every declared suite for All, expands only product
dependencies and deduplicates image layers. Tool-only dependencies do not enable Core performance
qualification or another companion's mutations. Declared mutation controls apply only to selected
suites on their exact RID/CLR-major target; other declared controls are explicitly zero.

`Get-QuietCiSuiteImagePlan` folds module-owned image fragments over the previous layer's fingerprint.
`Invoke-QuietCiSuiteImage` delegates actual preparation to existing image scripts and preserves
one ephemeral registry credential across layers, clearing it on completion or failure. Registry
identity, native architecture, integrity and publication-event guards remain in the image engine.

The YAML contains data and exported command identifiers, never shell fragments. A new companion
adds a declaration and, when it needs native tools, its existing `ci/Get-CiImageArguments.ps1`
contract and fetch/lock resources. The shared workflow requires no companion-specific job or
condition. Image optimization, scheduling limits and hosted qualification remain separate work.

<!-- script-contract:begin -->
## Execution contract

Purpose: Topologically orders product dependencies and rejects cycles or unknown references.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
