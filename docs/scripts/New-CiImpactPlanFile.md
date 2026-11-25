# New-CiImpactPlanFile.ps1

<!-- script-source:begin -->
Source file: [`New-CiImpactPlanFile.ps1`](../../scripts/New-CiImpactPlanFile.ps1)
<!-- script-source:end -->

Creates a UTF-8 file with the local working-tree CI job outputs from [New-CiImpactPlan.ps1](New-CiImpactPlan.md). Run it from any filesystem directory. The script's checkout supplies the plan and the relative output path resolves from your current directory.

```powershell
./scripts/New-CiImpactPlanFile.ps1 -GetContent
./scripts/New-CiImpactPlanFile.ps1 -Open
./scripts/New-CiImpactPlanFile.ps1 -Base $base -OutputPath ./artifacts/ci-plan/outputs.txt -GetContent -Open
```

- With no `-Base`, the script uses `git merge-base origin/develop HEAD` in its checkout. An explicit `-Base` accepts the comparison commit's full SHA.
- With no `-OutputPath`, the script uses `[IO.Path]::GetTempFileName()`. `-Output` is an alias. An explicit destination is replaced after the planner succeeds. Parent directories are created when needed.
- The default result is a `FileInfo` for the output. `-GetContent` returns its lines. `-Open` tries VS Code Insiders, then VS Code, and can be combined with `-GetContent`.
- `-WhatIf` skips Git, file writes and editor launch. `-Confirm` confirms the operation.

## Dependencies and review

`scripts/New-CiImpactPlanFile.ps1` uses [Ci.Process](lib/Ci.Process.md) for optional Git resolution, [New-CiImpactPlan](New-CiImpactPlan.md) for the plan, and [EditorExtensions](lib/EditorExtensions.md) for optional editor discovery. The planner also writes its normal reports under `artifacts/ci-plan`. Use an ignored destination such as `artifacts/ci-plan/outputs.txt` for a persistent preview file inside the checkout.

The wrapper publishes the destination after successful planning, so repeated calls produce one set of outputs. An unavailable comparison base fails before file creation. An editor discovery or launch failure leaves the generated file available at the reported path. Editor discovery follows the development editor helper's supported installations.

<!-- script-contract:begin -->
## Execution contract

Purpose: Writes the local working-tree CI plan outputs to a file.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

Use `-PullRequestBody (Get-Content -LiteralPath ./description.md -Raw -Encoding utf8)` to include the PR checklist in the local plan.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
