# CampaignReports.psm1

<!-- script-source:begin -->
Source file: [`lib/CampaignReports.psm1`](../../../scripts/lib/CampaignReports.psm1)
<!-- script-source:end -->

`Write-QuietCampaignReport` writes measurement tables in Markdown and offline HTML and appends them to the optional job summary. Download the artifact to open `report.html` in a browser or view `report.md` directly.

- `ScriptMutation` reads `report.json` and retains the detailed score, survivor and equivalent tables in Markdown.
- `RunProfilesMutation` reads `run-profiles-mutation.json`. Each sharded report identifies its shard.
- `Component` reads the run-profile mutation file or the JSON catalogues under `mutation-evidence/`. It reads PowerShell profiling traces under `profiling/` and shows up to eight functions and lines by self time in milliseconds.

The report prints the original step outcome even if evidence is missing or partial. The renderer reads only the campaign's owned evidence and keeps the machine-readable files intact.

<!-- script-contract:begin -->
## Execution contract

Purpose: Reads one JSON file from the selected campaign directory when present.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
