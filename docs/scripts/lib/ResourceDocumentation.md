# Resource documentation model

<!-- script-source:begin -->
Source file: [`lib/ResourceDocumentation.psm1`](../../../scripts/lib/ResourceDocumentation.psm1)
<!-- script-source:end -->

## Library boundary

Located at `scripts/lib/ResourceDocumentation.psm1`. Load with `Import-Module ([IO.Path]::Combine($root,'scripts/lib/ResourceDocumentation.psm1')) -DisableNameChecking -ErrorAction Stop`. Import defines functions and explicit dependencies without running business operations. Paths use `System.IO.Path`. Effects remain owned by the calling operation and its preview contract.

Explicit export surface:

```powershell
Export-ModuleMember -Function 'Get-QuietResourceDocumentation'
```


## Usage

imported this library and call `Get-QuietResourceDocumentation -WorkspaceRoot <root>`.

## Dependencies and effects

Reads lock/source files, returns deterministic Markdown including a Mermaid lifecycle and direct dependency references; does not load resource binaries or write files. Gallery consumers now refer to scripts/lib/Gallery.psm1; the generated inventory tracks that module's source hash and dynamic resource staging rather than the removed root Gallery.ps1 file.

## Critical review and verdict

Source: [ResourceDocumentation.psm1:12](../../../scripts/lib/ResourceDocumentation.psm1#L12). Reference extraction is textual; dynamic whole-module copy edges are explicitly declared. It is not exhaustive data-flow analysis or resource-readiness proof.

Verdict: suitable within the documented boundary; qualification evidence belongs in the companion test reports.

<!-- script-contract:begin -->
## Execution contract

Purpose: Generates the resource inventory and dependency graph from the lock and inspected source references.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/lib/ResourceDocumentation.psm1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
