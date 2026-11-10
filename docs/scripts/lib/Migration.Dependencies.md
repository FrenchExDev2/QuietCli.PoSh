# Migration.Dependencies.psm1

Dynamic call operators are recorded from the command expression itself, never from a literal argument that happens to name an approved module. RequiredVersion (including inline named syntax) is compared to the declared pin; minimum/maximum constraints and #requires ModuleVersion ranges require evaluated resolution. These conservative cases have retained regression witnesses. This remains static declaration analysis, not a claim to resolve arbitrary PowerShell/MSBuild execution semantics.

Also exports `Test-MigrationQualification`; [Test-MigrationGate](../Test-MigrationGate.md) documents the full gate. It requires fresh dependency/policy/source hashes, qualification of this checker and Migration.Exports with property/fuzz/mutation evidence, actual module export-contract summaries and product tests/isolated-restore/recovery artifacts. This read-only gate checks required evidence coherence; it never performs cutover.

`Get-MigrationDependencyReport -SourceRoot <root> -PolicyPath <json> [-ItemId <ids>] [-MaximumFiles 30000]` inspects a deny-by-default candidate whitelist. `Export-MigrationDependencyReport -Report <object> -Path <new.json> [-WhatIf] [-Confirm]` saves evidence. The [facade](../Test-MigrationDependencies.md) composes both functions.

Policy items require unique bounded ID, relative contained path, Assess/Migrate/Create/Exclude intent and explicit boolean approval. Unknown requested IDs and duplicate paths are refused. External dependency decisions require kind/name/version/source; these are declarations, not verified installations. Omitted candidates are excluded. The scanner bounds visited files and each text/XML input, skips known build/cache/Git directories and refuses to traverse reparse directories. Files carry SHA-256; policy and checker identities are included.

PowerShell AST inspection records requires/using/import/dot-source, script invocations, manifest module/assembly dependencies and command usages. Scripts are not invoked. XML inspection records project/package/import declarations, solution and solution-XML project paths; DTD/entity resolution is prohibited. Conditional/computed declarations require evaluation. Required evaluated MSBuild graph evidence stays a blocker for csproj inputs; no restore/SDK or implicit-import completeness is claimed. Local function declarations do not prove command visibility or absence of shadowing. Reflection, aliases, constructed paths and native semantics still require independent review/runtime evidence.

An empty/.gitkeep-only tree is ScaffoldCandidate; a nonempty parent with empty subdirectories remains AssessmentCandidate. Creation is distinct from migration and never reports migrated behavior for an empty tree. Resolved local file edges are checked for cycles. Parsing failures and unresolved dependencies remain explicit. DependencyGate is distinct from MigrationQualification=NotAssessed; no item is cut over by this library.

Side effects: report export only, behind ShouldProcess; no source modifications, module loading of inspected code, MSBuild execution, Git operation or network. A filesystem race during inspection is not a transaction: recheck the exact source/policy/checker identities at the final gate. The whitelist is a scope policy, not a sandbox/security boundary against malicious concurrent writers. Current path comparisons follow Windows semantics; case-sensitive crossplatform qualification is still required.

Critical review: [scanner](../../../scripts/lib/Migration.Dependencies.psm1:39) keeps policy/inspection/evidence responsibilities separate from migration execution; [export](../../../scripts/lib/Migration.Dependencies.psm1) refuses existing report paths. Tests use independent fixtures, malformed AST/XML and whitelist cases, cycle controls, property variations and mutants. Verdict: conservative static dependency gate; evaluated .NET and runtime qualification remain mandatory gaps.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
