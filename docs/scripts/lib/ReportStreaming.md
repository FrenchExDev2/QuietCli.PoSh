# Incremental run report streaming

## Library boundary

Located at `scripts/lib/ReportStreaming.psm1`. Load with `Import-Module ([IO.Path]::Combine($root,'scripts/lib/ReportStreaming.psm1')) -DisableNameChecking -ErrorAction Stop`. Import defines functions and explicit dependencies without running business operations. Paths use `System.IO.Path`. Effects remain owned by the calling operation and its preview contract.

Explicit export surface:

```powershell
Export-ModuleMember -Function 'New-QuietReportStream','Read-QuietReportStream'
```


## Usage

imported; create `New-QuietReportStream -Path <run-owned-log>`; poll `Read-QuietReportStream -State $state`.

## Dependencies and effects

Reads at most 64 KiB per poll with incremental strict UTF-8 decoding; keeps a bounded line tail and partial record. Does not write or start a process. Watch-Tests and Wait-WorkspaceWorker share this implementation.

## Critical review and verdict

Source: [ReportStreaming.psm1:22](../../../scripts/lib/ReportStreaming.psm1#L22). The bounded tail can omit earlier lines between polls; complete evidence stays in the run's existing log. Activity bytes/lines are not test counts. This helper never enables product event collection or raw business-output capture.

Verdict: suitable within the documented boundary; qualification evidence belongs in the companion test reports.

<!-- script-contract:begin -->
## Execution contract

Purpose: Creates caller-owned incremental UTF-8 tail state.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
