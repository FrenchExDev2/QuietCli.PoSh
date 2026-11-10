# Watch-DotNetTests.ps1

## Purpose

Reopen the shared read-only monitor for a saved .NET tooling run.

## Usage and parameters

```powershell
./scripts/Watch-DotNetTests.ps1 -StatusPath '<run-directory>/status.json'
```

StatusPath is the saved status.json reported by the shared launcher.

## Dependencies and effects

Delegates to Watch-Tests.ps1. Reads existing reports and draws terminal output; does not
write reports, run tests, start a daemon or modify a source file. A reviewed read-only
source-hash exception is stored in build/script-shouldprocess.json.

## Findings

- scripts/Watch-DotNetTests.ps1:12 only delegates the selected report directory.
  The existing monitor owns framing, resize handling and normal closure after a saved terminal state.
- Old reports may be removed by OS temporary-directory cleanup. A missing report cannot
  be recreated by this read-only observer.

## Verdict

An observer with a hash-bound exception, not a cosmetic WhatIf/Confirm implementation.

<!-- script-contract:begin -->
## Execution contract

Purpose: Reopens the shared read-only monitor for a saved .NET tooling campaign.

Boundary: **ReadOnly**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
