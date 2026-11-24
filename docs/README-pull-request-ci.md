# Pull requests and CI options

Use [Publish-WorkspacePullRequest.ps1](scripts/Publish-WorkspacePullRequest.md) to commit, push, publish the PR and monitor its CI from `develop`. Use [New-PullRequest.ps1](scripts/New-PullRequest.md) when the branch is already pushed. Both compose the standard checklist and optional Markdown footer. The GitHub PR form supplies the same checklist. The planner accepts the raw description as `-PullRequestBody`, including for [local working-tree previews](scripts/New-CiImpactPlanFile.md).

Click a checkbox in the PR description to request or clear an effect for its named target. The checklist groups the available effects by companion and includes repository scripts under **Scripts**. The final sequential option applies to every mutation target.

## Repository script mutation

Run every target declared by `test/scripts/mutation.targets.psd1`. Each target changes a script temporarily and checks whether its tests detect the change.

## Refresh the script mutation cache

Rerun the baselines and mutants for the selected script targets and save fresh verdicts. This applies to diff-selected targets or every target when repository script mutation is checked.

## Companion mutation

Run the selected companion's mutation campaign as declared in `build/companions.yaml`. The campaign checks whether the tests detect changes to the companion's behavior. The **Scripts** mutation checkbox selects all repository script mutation targets.

## Companion performance

Measure one unprofiled test run for the selected companion. The elapsed time starts after the build and includes the test harness and process startup. Each job publishes the duration, runtime identifier and worker count with the campaign reports. Use the ReadyToRun checkbox for the separate Core cold-start comparison.

## Companion profiling

Measure the selected companion's PowerShell test pass with PSProfiler. When mutation is checked for the same companion, the profiler runs during that mutation pass.

## Sequential mutation workers

Run companion checks and shards one at a time, with one worker per shard. Use this to diagnose failures that depend on concurrency.

## ReadyToRun performance

Run a paired IL/ReadyToRun cold-start comparison for the same revision on each existing target. Manual ReadyToRun
dispatches can enable an A/A control for calibration.

## PowerShell Preview

Qualify Core with the locked Windows Preview hosts alongside the production matrix.

## CI results

The diff controls obligatory qualification. Checked options add work, and a change to the description starts a fresh PR run. The standard Core profiling follows Core qualification. ReadyToRun requires complete measurements when selected. Either direction of the performance result is valid. A manual ReadyToRun run remains informational.

For mutation or companion profiling results, open the GitHub Actions run summary and download the campaign artifact. Open `report.html` in a browser or view the measurement tables in `report.md`. Both reports show the original campaign outcome. The artifact also contains the available JSON evidence. [Campaign report evidence](scripts/lib/CampaignReports.md)

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
