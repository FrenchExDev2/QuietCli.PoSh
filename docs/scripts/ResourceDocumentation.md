# Resource documentation model

## Usage

Dot-source this library and call `Get-QuietResourceDocumentation -WorkspaceRoot <root>`.

## Dependencies and effects

Reads lock/source files, returns deterministic Markdown including a Mermaid lifecycle and direct dependency references; does not load resource binaries or write files. Gallery consumers now refer to scripts/lib/Gallery.psm1; the generated inventory tracks that module's source hash and dynamic resource staging rather than the removed root Gallery.ps1 file.

## Critical review and verdict

Source: [ResourceDocumentation.ps1:12](../../scripts/ResourceDocumentation.ps1:12). Reference extraction is textual; dynamic whole-module copy edges are explicitly declared. It is not exhaustive data-flow analysis or resource-readiness proof.

Verdict: suitable within the documented boundary; qualification evidence belongs in the companion test reports.

<!-- script-contract:begin -->
## Execution contract

Purpose: Generates the resource inventory and dependency graph from the lock and inspected source references.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
