# .NET migration — Release builds, preview, table and JSON

Date: 10 November 2026. Scope: migration-assessment tooling and real compilation evidence; no migration/cutover, publication or product test qualification.

The requested capability is available through [Test-DotNetMigrationBuild](../scripts/Test-DotNetMigrationBuild.md), its reusable Migration.DotNet library and the existing dependency validator's optional BuildDotNet mode. Discovery covers `.slnx`, `.sln` and `.csproj` under Net/FrenchExDev. It found **652 entries: 49 slnx, 1 sln and 602 csproj** on this developer tree. These counts exclude named generated/cache/mutation directories and do not approve any entry for migration.

Default build entry points follow the candidate whitelist; exact ItemId/Target filters narrow them. AllDiscovered explicitly extends assessment only. Each selected solution and project is built independently and sequentially with `dotnet build <file> --configuration Release`, SDK resolution from its own directory, bounded execution and no automatic retry or SDK installation. Default restore is the CLI's implicit restore; NoRestore is explicit. [Official CLI reference](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-build).

WhatIf returns a plan without native SDK/build calls, worker/monitor creation, restore, build outputs or report writes. Native compilation is guarded by ShouldProcess. Table output identifies project/task/workspace, shows selected entries and compact durations, and clips visible paths only. JSON retains the complete inventory, selection reasons, SDK, target hashes, literal arguments, state/exit/duration and bounded diagnostics/log paths. Json mode does not mix monitor/table text into the success stream.

## Executed source assessment

The real Result selection built **3 of 3 entries successfully** using SDK **11.0.100-rc.3.26522.148**:

| Entry relative to Net/FrenchExDev | State | Exit | Duration |
| --- | --- | --- | --- |
| Result/FrenchExDev.Net.Result.slnx | Success | 0 | 14.221s |
| Result/src/FrenchExDev.Net.Result/FrenchExDev.Net.Result.csproj | Success | 0 | 2.710s |
| Result/test/FrenchExDev.Net.Result.Tests/FrenchExDev.Net.Result.Tests.csproj | Success | 0 | 2.515s |

This compiled the test project; it did not run its tests. Repeated solution/project builds may reuse warm caches and incremental outputs. These durations are execution receipts, not performance benchmarks or cold-cache evidence. Full JSON/logs: `C:/Users/serard/AppData/Local/Temp/QuietCli2/874a99c9b658/migration-builds/5c6305068af14067a9030ae6fb8f2a1d/build-results.json`.

## Tooling qualification

Complete monitored campaign: **412 passed, 0 failed**, comprising 75 examples/fault controls, 283 property checks, 43 malformed/boundary controls and 11 targeted mutants killed, 0 surviving in this catalogue. Seed 20261110. Report: `C:/Users/serard/AppData/Local/Temp/QuietCli2/874a99c9b658/tests/roadmaps-20261110-105425-598b1e/summary.json`; SHA-256 `820B9E219EAF7F3AAD8B8D52F56F95A649284C7E35D92FA33E2FC96489841A1C`.

Independent cases cover whitelist/target boundaries, explicit empty selections, no-effect WhatIf, pure JSON, table width/Unicode, native outcome invariants, real Release compilation and deliberate compile/solution failures with continued execution. The three additional mutants affect Release selection, whitelist selection and native outcome interpretation. Expected fixture compiler errors remain saved as fixture failures while the assertions confirming their correct handling pass. This is bounded property/fuzz/mutation evidence, not exhaustive coverage.

Initial source-tree discovery hit its entry bound in Docker's large scrape/help corpus. It launched no build. Discovery now filters filesystem names before constructing file metadata, counts directories/build entries and excludes observed caches; irrelevant help text no longer consumes the build-entry budget. An earlier localized dotnet help invocation failed strict UTF-8 decoding. The owned build worker explicitly selects English CLI text and UTF-8 through child-only environment variables; no profile or parent environment change is required. [Environment variable reference](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-environment-variables).

The complete migration gate now additionally requires a successful complete real Release report for every selected .NET solution/project, matching target/policy hashes, and qualification of Migration.DotNet itself. A WhatIf plan or failed/missing entry cannot pass. Existing evaluated-graph, behavior, isolated package restore and recovery requirements remain; Release build evidence alone does not make MigrationQualification or ReleaseReady pass. Planning baseline: 21 roadmaps, 94 proposed requirements and 76 work items.

Reports/monitors use shared independent CI process supervision, with visible normal-profile PowerShell monitoring and saved terminal outcomes. Displayed process identity is the owned PowerShell worker; child dotnet PIDs are not fabricated. Detailed reports are temporary and may be removed by system cleanup. This audit retains the bounded results and limitations. Preexisting unrelated workspace changes are excluded from the checkpoint.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
