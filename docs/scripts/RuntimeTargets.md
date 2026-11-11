# RuntimeTargets.ps1

## Purpose and usage

Shared binary checks; dot-sourced by Common.ps1. `Get-QuietRuntimeTargets -WorkspaceRoot <root>` reads the six-RID catalogue. `Assert-QuietRuntimePublication -Directory <slot> -Target <row>` checks managed and native architectures. `Test-QuietReadyToRunImage -Path <dll>` reads the CLR native-header directory and RTR signature without loading code. `Assert-QuietPtyPublications -WorkspaceRoot <root>` checks static ELF bridges and source/binary receipts.

## Dependencies and side effects

Uses host .NET PEReader, bounded ELF reads, SourceIdentity.ps1's PE reader and the runtime catalogue. Reads files only; no native commands, compilation, imports, network or publication.

## Critical review

- `scripts/RuntimeTargets.ps1:32` rejects absent native headers; malformed PE input can throw rather than being reported as valid IL. The build must fail on corrupt output.
- `scripts/RuntimeTargets.ps1:59` validates actual machine fields. Linux ReadyToRun uses the runtime's `0x7B79` PE machine OS override; ordinary IL and Windows PE retain the catalogue machine.
- Header/signature checks establish the format. They do not prove every method is precompiled or that startup is faster. Corrupt-image fuzz cases and real cross-RID publications complement routing properties.

## Verdict

Shared architecture and R2R format checks are suitable for build/package verification; runtime execution remains necessary for platform qualification.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Reads the explicit release platform catalogue without running a binary.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
