# Export-CampaignReport.ps1

<!-- script-source:begin -->
Source file: [`Export-CampaignReport.ps1`](../../scripts/Export-CampaignReport.ps1)
<!-- script-source:end -->

Renders `report.md` with Mermaid charts and `report.html` with standalone bar charts for a mutation or profiling campaign. `-Outcome` records the original campaign step outcome. `-SummaryPath` appends the compact Markdown to the GitHub Actions job summary. `-WhatIf` previews the write.

```powershell
./scripts/Export-CampaignReport.ps1 -Kind ScriptMutation -Directory ./artifacts/script-mutation/Example -Title 'Script mutation Example' -Outcome success
```

The renderer keeps the JSON evidence and the mutation gate independent of the visualization. [Evidence contracts](lib/CampaignReports.md)

<!-- script-contract:begin -->
## Execution contract

Purpose: Renders campaign evidence as Markdown and standalone HTML.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
