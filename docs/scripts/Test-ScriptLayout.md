# Test-ScriptLayout.ps1

## Purpose and usage

```powershell
./scripts/Test-ScriptLayout.ps1
./scripts/Invoke-WorkspaceChecks.ps1 -Check ScriptLayout
```

Checks RAC-PS-004 against `WorkspaceRoot`, which defaults to the checkout. Recursively parses
automation `.ps1` and `.psm1` files using [ScriptLayout.psm1](lib/ScriptLayout.md), without
executing the inspected files. Names use `Verb-Noun` with a capitalized alphabetic verb and
an alphanumeric noun; this is a syntax convention, not the PowerShell approved-verb list
(`Commit-Workspace` remains valid). Data-only run profiles use `.profile.psd1`.

## Dependencies and effects

Imports the local library with `-DisableNameChecking -ErrorAction Stop`. Reports file count
on success and throws `ScriptLayoutInvalid` with violations on failure. Rejects function/filter
definitions anywhere in entry points, misplaced modules, `Join-Path`, module dot sourcing,
module imports lacking `-DisableNameChecking`, malformed syntax and filesystem links.
Path composition uses `System.IO.Path`. Comments and literal examples are not executable commands.

The shared registry runs this gate for standalone checks, `Commit-Workspace` (including
exported prepared indexes) and GitHub `scripts-docs-check.yml`. `-NoSyncChecks` retains it;
`-SkipCheck ScriptLayout` reports an explicit omission. It never writes, imports inspected
libraries, starts processes or accesses the network; WhatIf/Confirm are unnecessary.

## Validation limits

The AST gate proves source structure. It does not execute dynamic command names or prove
the behavior of imported functions. Companion properties, malformed samples and targeted
mutations cover these static guarantees; runtime previews cover delegated operations separately.

<!-- script-contract:begin -->
## Execution contract

Purpose: Checks automation entry-point names, function placement, imports and path composition without executing scripts.

Boundary: **ReadOnly**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
