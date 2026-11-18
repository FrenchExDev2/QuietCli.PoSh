# PowerShellSources.psm1

<!-- script-source:begin -->
Source file: [`lib/PowerShellSources.psm1`](../../../scripts/lib/PowerShellSources.psm1)
<!-- script-source:end -->

## Purpose and usage

`Test-QuietPowerShellSources -WorkspaceRoot $root` discovers inert module declarations
through WorkspaceProjects and parses their PowerShell sources plus scripts entry
points. It returns Check, Files, Functions and State after successful inspection.

## Dependencies and boundaries

Imports WorkspaceProjects without forced reload. It never imports inspected products
or evaluates inspected source. Recursion prunes the existing generated/library
boundary: bin, obj, lib, artifacts, .git, .cache and .dotnet. Filesystem links outside
these excluded trees are rejected. UTF-8 decoding is strict; parser errors and missing
function synopsis produce the existing Tooling diagnostic messages. Nested functions
and filters are included. No files, measurements or product sessions are created.

## Critical review and tests

This extracts the existing assertion; it does not establish complete help coverage
of script libraries previously excluded by that assertion. ScriptLayout independently
checks those libraries' syntax and structure. Repository-wide LF and JSON writer
properties remain in the owning Tooling case. The shared registry inspects a staged
snapshot for NoAll commits, preventing unstaged repairs from hiding staged defects.
Independent generated/malformed-source tests and mutations check parser rejection,
synopsis enforcement and nested traversal. Real hosted scheduling remains CI evidence.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Parses project and entry-point sources and requires readable function help without executing inspected code.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/lib/PowerShellSources.psm1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
