# Pull requests and CI options

Use [Publish-WorkspacePullRequest.ps1](scripts/Publish-WorkspacePullRequest.md) to commit, push, publish the PR and monitor its CI from `develop`. Use [New-PullRequest.ps1](scripts/New-PullRequest.md) when the branch is already pushed. Both compose the standard checklist and optional Markdown footer. The GitHub PR form supplies the same checklist. The planner accepts the raw description as `-PullRequestBody`, including for [local working-tree previews](scripts/New-CiImpactPlanFile.md).

| Option | Additional work |
| --- | --- |
| Repository script mutation | Every target declared by `test/scripts/mutation.targets.psd1` |
| Companion mutation | The selected companion's mutation campaign declared in `build/companions.yaml` |
| Companion profiling | Profiles the selected companion's test pass with PSProfiler. If mutation is selected for the same companion, the profiler runs during that mutation pass. |
| Sequential mutation workers | Serial companion checks, serial shards within each matrix and one worker per shard |
| ReadyToRun | A/A noise control and an IL/ReadyToRun comparison for the same revision on each existing target |
| PowerShell Preview | Core qualification with the locked Windows Preview hosts in addition to the production matrix |

The diff controls obligatory qualification. Checked options add work, and a change to the description starts a fresh PR run. The standard Core profiling follows Core qualification. ReadyToRun requires complete measurements when selected. Either direction of the performance result is valid. A manual ReadyToRun run remains informational.

For mutation or companion profiling results, open the GitHub Actions run summary and download the campaign artifact. Open `report.html` in a browser for offline charts or `report.md` in a Markdown viewer with Mermaid support. Both reports show the original campaign outcome. The artifact also contains the available JSON evidence. [Campaign report evidence](scripts/lib/CampaignReports.md)

The required check records the PR, source SHA, tested merge SHA, normalized choices and attempt. Use [Merge-PullRequest.ps1](scripts/Merge-PullRequest.md) or the scripted commit or release flow to require fresh evidence. A green check for a different selection cannot authorize scripted merge. For existing PRs, rerun on the updated workflow to obtain the receipt. The GitHub merge button can still display the previous conclusion while the new run starts. GitHub's merge API pins the source SHA.

To qualify product suites manually, dispatch `companions-ci.yml` with `suites`. For a smoke or build, dispatch `ci.yml` with the suite, mode and optional tooling disabled.

```powershell
gh workflow run companions-ci.yml -f suites=Core,Git
gh workflow run ci.yml -f suite=Git -f qualification_mode=smoke -f run_tooling=false
```

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
