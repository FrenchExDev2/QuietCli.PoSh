# Assert-RunProfileMutationShards.ps1

## Purpose and usage

```powershell
./scripts/Assert-RunProfileMutationShards.ps1 -ReportRoot ./artifacts/mutation-shards -Revision $env:GITHUB_SHA -OutputPath ./artifacts/mutation-complete/receipt.json
```

Requires two complete, source-identical run-profile mutation shards from the selected revision. The workflow downloads only the current attempt's uniquely named artifacts. The source-controlled catalogue determines every expected name; failed baselines, unknown/duplicate/missing mutants and outcomes other than Killed fail closed.

## Dependencies and side effects

Imports only `lib/MutationShards.psm1`; reads bounded UTF-8 JSON and the inert catalogue, hashes current inputs, and writes a new completion receipt only after acceptance. Existing receipts are not overwritten. WhatIf skips all reads, imports, directories and writes. No product build/import, native command, network or publication occurs.

## Critical review and verdict

`scripts/Assert-RunProfileMutationShards.ps1:1` separates artifact transport from catalogue acceptance. Runtime fixtures exercise successful export, rejection without a receipt and no-write preview. The completion receipt establishes only the declared mutation catalogue, never platform/product release qualification.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Accepts only the complete run-profile mutation catalogue from matching isolated shards.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
