# Test-MigrationGate.ps1

Read-only facade of `Test-MigrationQualification` in [Migration.Dependencies](lib/Migration.Dependencies.md). It returns a MigrationQualification assessment and throws on any missing/failed prerequisite. It never migrates files or creates remote resources.

Inputs are explicit saved DependencyReportPath, complete ToolingSummaryPath, optional ExportSummaryPath array and product AcceptanceReceiptPath. The checker itself must appear with its current dependency/export library source hashes in the successful tooling summary, with nonempty successful property/fuzz/mutation categories. Dependency evidence must pass and match current source/policy/checker hashes. Each selected psm1 needs a real-import export-contract summary for that module's source/hash; a manifest wildcard or static function list is insufficient.

The acceptance receipt binds `DependencyReportSha256` to the exact saved report, with `Tests`, `Restore`, `Recovery` objects each containing `State: Passed` and nonempty `Artifacts` (Path/Sha256 pairs). The library rechecks these files. Semantic adequacy and actual provenance of product execution remain the responsible reviewer's decision; matching hashes and declared states do not prove the business need. Missing evaluated .NET evidence remains a blocker in the upstream dependency report.

Critical review: [gate](../../scripts/lib/Migration.Dependencies.psm1) fails closed on unreadable/stale evidence and counts qualification of its own tooling. It validates evidence coherence/freshness rather than rerunning product tests. Companion controls verify failed checker and missing product evidence are explicit blockers. Verdict: necessary migration gate; no cutover authorization or product implementation is implied.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
