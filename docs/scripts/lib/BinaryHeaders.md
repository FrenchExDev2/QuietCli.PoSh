# BinaryHeaders.psm1

## Purpose and usage

Exports `Get-QuietPeMachine -Path <file>`. Reads the PE machine field without loading or
executing the subject. SourceIdentity re-exports it for compatibility; RuntimeTargets imports
it directly for managed-assembly and apphost checks.

## Dependencies and effects

Import with `-DisableNameChecking -ErrorAction Stop`. Import defines the function without
business effects. The command uses System.IO binary readers, closes both reader and stream
on every path, and rejects missing MZ/PE signatures and invalid offsets. It does not import
the product, start a native process, access the network or change files.

## Validation and limits

The Tooling layout regression exercises the publication validator with a synthetic x64 PE
header. A valid machine field establishes header architecture only; it proves neither binary
authenticity nor runtime compatibility. Runtime and integrity qualification remain separate.

<!-- script-contract:begin -->
## Execution contract

Purpose: Reads the actual PE machine field without loading or executing a managed assembly or native apphost.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
