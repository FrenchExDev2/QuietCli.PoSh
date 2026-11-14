# Test-PowerShellSources.ps1

## Purpose and usage

`./scripts/Test-PowerShellSources.ps1` checks syntax and readable function synopsis
using the shared [PowerShellSources](lib/PowerShellSources.md) library. WorkspaceRoot
selects a checkout or the isolated prepared-index snapshot used by Commit-Workspace.
`Invoke-WorkspaceChecks.ps1 -Check PowerShellSources` selects the same check.

## Dependencies and effects

Read-only source inspection. The entry point imports only its local checker; inspected
modules, scripts and function bodies are never imported or executed. It writes no
files, starts no process and requires no compiled product or network preparation.
The hash-bound read-only policy exception preserves execution during commit WhatIf;
preview does not silently omit this check. It returns bounded file/function counters.

## Review and qualification limits

Scope matches the former Tooling syntax/help loop: discovered project sources and
scripts entry points, pruning bin, obj, lib, artifacts and Git/generated caches.
In particular, function-help coverage does not newly qualify scripts/lib; ScriptLayout
continues parsing those libraries independently. Strict UTF-8 decoding and link
rejection make inspected source boundaries explicit. The owning Tooling case retains
its repository LF checks and 64 JSON-writer value/line-ending properties separately.

PowerShellSources.Tests.ps1 checks 32 Unicode sources with nested functions, invalid
syntax, missing nested/filter help, malformed encoding, three targeted mutants,
read-only inspection and a real prepared-index/unstaged-repair commit preview.
The unconditional source-checks job runs alongside planning; QuietCli required CI
requires its success even when product suites are skipped. Local checks are not
hosted platform qualification.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Checks PowerShell syntax and function help using inert source analysis, including during commit preview.

Boundary: **ReadOnly**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
