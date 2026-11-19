# RuntimeTargets.psm1

<!-- script-source:begin -->
Source file: [`lib/RuntimeTargets.psm1`](../../../scripts/lib/RuntimeTargets.psm1)
<!-- script-source:end -->

## Library boundary

Located at `scripts/lib/RuntimeTargets.psm1`. Load with `Import-Module ([IO.Path]::Combine($root,'scripts/lib/RuntimeTargets.psm1')) -DisableNameChecking -ErrorAction Stop`. Import defines functions and explicit dependencies without running business operations. Paths use `System.IO.Path`. Effects remain owned by the calling operation and its preview contract.

Explicit export surface:

```powershell
Export-ModuleMember -Function 'Get-QuietRuntimeTargets','Get-QuietElfHeader','Test-QuietReadyToRunImage','Assert-QuietRuntimePublication','Assert-QuietPtyPublications'
```


## Purpose and usage

Shared binary checks; imported by Common.ps1. `Get-QuietRuntimeTargets -WorkspaceRoot <root>` reads the six-RID catalogue. `Assert-QuietRuntimePublication -Directory <slot> -Target <row>` checks managed and native architectures. `Test-QuietReadyToRunImage -Path <dll>` reads the CLR native-header directory and RTR signature without loading code. `Assert-QuietPtyPublications -WorkspaceRoot <root>` checks static ELF bridges and source/binary receipts.

## Dependencies and side effects

Uses host .NET PEReader, bounded ELF reads, SourceIdentity.ps1's PE reader and the runtime catalogue. Reads files only; no native commands, compilation, imports, network or publication.

## Critical review

- `scripts/RuntimeTargets.psm1:32` rejects absent native headers; malformed PE input can throw rather than being reported as valid IL. The build must fail on corrupt output.
- `scripts/RuntimeTargets.psm1:59` validates actual machine fields. Linux ReadyToRun uses the runtime's `0x7B79` PE machine OS override; ordinary IL and Windows PE retain the catalogue machine.
- Header/signature checks establish the format. They do not prove every method is precompiled or that startup is faster. Corrupt-image fuzz cases and real cross-RID publications complement routing properties.

## Verdict

Shared architecture and R2R format checks are suitable for build/package verification; runtime execution remains necessary for platform qualification.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Reads the explicit release platform catalogue without running a binary.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

## Explicit library dependencies

Imports BinaryHeaders directly for PE machine reads. Publication validation is independent of caller-scope helper functions; importing the module does not inspect binaries.

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/lib/RuntimeTargets.psm1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
