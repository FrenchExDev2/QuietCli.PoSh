# Migration.DotNet.psm1

The source-tree pass also excludes the observed `.fake`, `.packages`, `.coverage` and `.integration-results` caches. An initial developer-tree traversal hit its bound in Docker's large scrape/help corpus, starting no build. Discovery now uses filesystem name masks before materializing file metadata; its bound counts directories and matching build entries, not irrelevant help payloads. Case-insensitive enumeration includes uppercase extensions on every host. Regression fixtures retain ignored generated projects so caches cannot be mistaken for product entry points.

Exports `Get-DotNetMigrationBuildPlan`, `Invoke-DotNetMigrationBuild` and `Format-DotNetMigrationBuildTable`. The [facade](../Test-DotNetMigrationBuild.md) supplies the default policy and output format. Code consumers call the functions directly and receive typed reports.

The planner reads only the selected source tree and policy: .slnx/.sln/.csproj, stable target ordering, input hashes, whitelist association, exact target filters and literal argument vectors. It excludes .git/.vs/bin/obj/.tools/.quality-gate/StrykerOutput/coverage-results/TestResults and known caches. Reparse directories/files are refused or reported as discovery gaps. A visited-entry bound stops unbounded inventories. Explicit empty, unknown, escaped or non-whitelisted target selections are refused. AllDiscovered is an explicit assessment override, not a migration decision.

The executor owns ShouldProcess; WhatIf returns Mode=WhatIf without native calls, files or processes. Real execution delegates to the [worker](../workers/Invoke-DotNetMigrationBuild.md), using the shared supervisor and visible monitor. It saves build-results.json and optionally a new JsonPath. Failed/crashed/timed-out workers are not promoted to success; missing completed reports retain incomplete target states. The JSON holds full paths while the table clips display cells only. Configuration is always Release; there is no Debug parameter to select accidentally.

Table rendering reuses compact duration formatting, measures Unicode grapheme widths including combining marks/CJK/emoji, strips control sequences, and sizes at each static rendering. Narrow widths use a compact vertical presentation; redirected output uses width 110. Persistent progress uses the existing monitor, which redraws on resize. Console-font ambiguity is not a source of build success/failure; JSON preserves full identifiers.

Critical findings: [source](../../../scripts/lib/Migration.DotNet.psm1) separates discovery, execution and presentation; no shell command is constructed. Input target hashes and policy are rechecked by the worker. A target hash alone is not a snapshot of every C# source/import/package: final migration still needs evaluated dependency/behavior/package/recovery evidence. Custom MSBuild targets can have broader effects than default bin/obj writes; this is explicit build execution, not source-only inspection. Current local monitoring launcher is Windows-only; read-only discovery is portable. Verdict: qualified tooling scope, not full software migration qualification.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
