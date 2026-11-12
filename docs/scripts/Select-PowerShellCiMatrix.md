# Select-PowerShellCiMatrix.ps1

## Purpose and usage

Produces the Windows matrix from the reviewed host lock instead of duplicating version numbers in YAML.

```powershell
./scripts/Select-PowerShellCiMatrix.ps1 -OutputPath $env:GITHUB_OUTPUT
./scripts/Select-PowerShellCiMatrix.ps1 -IncludePreview -OutputPath $env:GITHUB_OUTPUT -WhatIf
```

WorkspaceRoot defaults to the checkout. Production has four rows: Windows x64/ARM64, each in Process and InProcess hosting, using the locked GA host. IncludePreview adds exactly two next-version InProcess rows only when their real archives are locked. Requesting an unpublished preview fails before outputs are appended. Default selection does not depend on preview availability.

OutputPath is the existing GitHub output file. It receives `windows_matrix` and `expected_reports`: four Linux targets plus the selected Windows rows, hence eight by default or ten with requested preview. WhatIf returns before lock reads or writes.

## Dependencies and effects

Uses the pure policy in [GitHubCi](GitHubCi.md), local UTF-8 JSON and bounded matrix output. No product import, native execution, network, host installation or qualification receipt is produced.

## Critical review and verdict

`scripts/Select-PowerShellCiMatrix.ps1:1` binds matrix and profile-count selection to the same policy. Independent cross-product/shuffle properties, unavailable-preview rejection, source workflow wiring and three policy mutants verify completeness. No preview is counted when omitted; a selected preview must succeed like other requested rows.

<!-- script-contract:begin -->
## Execution contract

Purpose: Writes the lock-derived Windows matrix and exact required profile count, with optional preview.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
