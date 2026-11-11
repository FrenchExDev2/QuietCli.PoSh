# Bootstrap.ps1

## Purpose

A compatibility entry point so a caller expecting a file named `Bootstrap.ps1` can still reach the independent CI process runner, by forwarding (dot-sourcing) to `Ci.Process.ps1` in the same directory. It defines no AI command aliases of its own and loads no product module or engine, per its own one-line comment (line 2). It is invoked by `FrenchExDev2.QuietCli.Core.Tests.PoSh/audit/Probe-Bootstrap.ps1` (line 12, which dot-sources it), itself launched through `quiet ... pwsh -NoProfile -File Probe-Bootstrap.ps1` from `Invoke-AuditWorker.ps1` (line 152).

## Usage

No parameters. The entire file is:

```powershell
. (Join-Path $PSScriptRoot 'Ci.Process.ps1')
```

```powershell
. ./scripts/Bootstrap.ps1
```

## Dependencies

- Dot-sources `Ci.Process.ps1` (same directory), which supplies `Invoke-CiProcess` and `ConvertTo-CiArgument`.

## Side effects

None of its own. Inherits `Ci.Process.ps1`'s own side effect of setting `[Console]::InputEncoding`/`OutputEncoding`/`$OutputEncoding` to UTF-8 (no BOM) when no PowerShell profile is active.

## Findings

- No bug, convention violation, or design smell was found after genuine review: the file does exactly what its one comment line says, nothing more, nothing hidden.
- DESIGN (very minor): nothing in the repository's visible docs/README files explains why this alias for `Ci.Process.ps1` exists, or which caller specifically still needs the `Bootstrap.ps1` name rather than calling `Ci.Process.ps1` directly. If the compatibility need no longer exists, this is dead indirection; if it does, the reason is undocumented.
- Testability: only exercised transitively through `Probe-Bootstrap.ps1`, which is an audit-only probe script, not a committed Pester `*.Tests.ps1`. There is no assertion that dot-sourcing `Bootstrap.ps1` actually yields a working `Invoke-CiProcess` function — though given the file is a single forwarding statement, the risk this represents is low.

## Verdict

Fit for purpose as a trivial shim; there is nothing to fix functionally. The only item worth addressing is documenting (or removing, if unneeded) the reason a second name for `Ci.Process.ps1` is kept — low priority given the file's triviality.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Provide Bootstrap automation.

Boundary: **Library**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
