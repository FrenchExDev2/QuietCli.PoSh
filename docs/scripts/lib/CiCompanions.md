# Declarative CI companions and test suites

<!-- script-source:begin -->
Source file: [`lib/CiCompanions.psm1`](../../../scripts/lib/CiCompanions.psm1)
<!-- script-source:end -->

Invoke-QuietCiSuiteImage -ProbeOnly -RegistryCache returns final CacheHit after configuration verification, without daemon calls or image preparation. A miss never builds in this mode. Core selects only Core and the base image; Git executable fixtures remain independent of the Git module.

Registry preparation first resolves the final suite image and attempts a CacheOnly pull with identity verification. A hit returns immediately without preparing parents. If the read-only registry cache misses or the digest download fails, preparation can still reuse cached parents and builds the final layer locally without another registry lookup for that layer. The retained credential is restored between probes and layers, then cleared on exit.

Producer-only ResolveOnly verifies the final registry configuration without pulling any layer. A miss still builds/publishes through the same reviewed layer path. Owned fixtures reject any attempt to prepare parents on either a final-image pull hit or a metadata-only producer hit.

When preparing multiple suites for an archive, the producer shares locally verified base and overlay layers between chains on the same Docker daemon. Receipt-only registry resolutions never stand in for a loaded layer. [Export-CiImageBundle](../Export-CiImageBundle.md)

`scripts/lib/CiCompanions.psm1` reads `build/companions.yaml`. Import declares functions only;
reading configuration uses the checksum-pinned YamlDotNet resource through `Resources.ps1`,
without importing the QuietCli engine. Missing parser resources are prepared by that consumer.

`companions` describes product dependencies and image participation (`base`, `overlay`, `none`).
`suites` separately declares an exported test command, its test project and required companions.
An integration suite can require Core and Vagrant while keeping Core's product dependencies empty.
Its dedicated test module must exist and export the declared command. Running two functional suites
does not establish an integration test between them.

`Get-QuietCompanions` reads companion names from `companions`. Use `-Name` to validate a selection case-insensitively and return the catalogue spelling. `-Capability Mutation` and `-Capability Workstation` require the corresponding declaration. Omitting `-Name` lists every eligible companion. Launchers pass a previously read `-Configuration` when they also need suite or campaign details.

```powershell
Import-Module ./scripts/lib/CiCompanions.psm1 -DisableNameChecking
Get-QuietCompanions -WorkspaceRoot $PWD.ProviderPath -Name git,vagrant -Capability Mutation
```

`Read-QuietCiCompanions` rejects duplicate YAML keys, malformed paths or policies, unknown fields or names, missing test manifests or exports, dependency cycles and missing or multiple base declarations. The reader can resolve test suites in a source subset such as the Core-independence checkout. `Sync-CompanionWorkflows.ps1` verifies the declared directories in a full checkout.
`Resolve-QuietCiCompanions` selects one suite or every declared suite for All, expands only product
dependencies and deduplicates image layers. Tool-only dependencies do not enable Core performance
qualification or another companion's mutations. Declared mutation controls apply only to selected
suites on their exact RID/CLR-major target; other declared controls are explicitly zero.

`Get-QuietCiSuiteImagePlan` folds module-owned image fragments over the previous layer's fingerprint.
`Invoke-QuietCiSuiteImage` delegates actual preparation to existing image scripts and preserves
one ephemeral registry credential across layers, clearing it on completion or failure. Registry
identity, native architecture, integrity and publication-event guards remain in the image engine.

`Invoke-QuietCiSuiteImages` prepares the chains of several suites for one RID in a single job, the
`images` warm-up of `companions-ci.yml`. Suites that resolve to the same ordered layers share one
chain; chains run sequentially, shortest first, so a parent is resolved or published before any
overlay that extends it. It resolves every suite before preparing anything, hands the ephemeral
registry credential to each chain and clears it on exit or failure. `Fingerprint` is the SHA-256 of
the sorted `RegistryPath@Fingerprint` identities of the chains, independent of the suite order, and
`CacheHit` is true only when every chain hit. An empty suite list fails with `CiSuiteImagesEmpty`.

`Assert-QuietCiCompanionImages` enforces the image participation rule before workflows are generated
(`Sync-QuietCompanionWorkflows`). A companion without its own image (`image: none`) is legitimate and
runs on its parent's image. A companion whose product module ships `ci/Get-CiImageArguments.ps1` or a
`Dockerfile`/`Containerfile` must be an `overlay` (`CiCompanionImageMustBeOverlay`), and every overlay
must ship the contract (`CiCompanionOverlayContractMissing`). Test projects are not inspected: their
container files are fixtures, not CI images. The base is never rejected.

The YAML contains data and exported command identifiers, never shell fragments. A new companion
adds a declaration and, when it needs native tools, its existing `ci/Get-CiImageArguments.ps1`
contract and fetch/lock resources. The shared workflow requires no companion-specific job or
condition. Image optimization, scheduling limits and hosted qualification remain separate work.

<!-- script-contract:begin -->
## Execution contract

Purpose: Topologically orders product dependencies and rejects cycles or unknown references.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 2.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Container file paths in the image validation results use `/` as the directory separator on every host.

Reviewed source: scripts/lib/CiCompanions.psm1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
