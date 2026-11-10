# Test-DotNetMigrationBuild.ps1

The table shows selected entries only, with discovered/selected counters; JSON retains the full discovered inventory and exclusion reasons. Its first lines identify the project/task and source workspace. This keeps a small assessment readable even when the source tree contains hundreds of unrelated entry points.

Discovers `.slnx`, `.sln` and `.csproj` under `<SourceRoot>/Net/FrenchExDev` and explicitly builds selected entry points with `dotnet build <file> --configuration Release`. The correct CLI option is lowercase `-c` or `--configuration`. [Official command reference](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-build).

```powershell
# Preview: no SDK invocation, restore, process, build output or report directory.
./scripts/Test-DotNetMigrationBuild.ps1 -SourceRoot C:/code/FrenchExDev/FrenchExDev_i2 -ItemId Result -WhatIf

# Real selected builds: Unicode table plus automatically retained JSON/logs.
./scripts/Test-DotNetMigrationBuild.ps1 -SourceRoot C:/code/FrenchExDev/FrenchExDev_i2 -ItemId Result

# Exact entry and pure JSON on the success stream; no table mixed into it.
./scripts/Test-DotNetMigrationBuild.ps1 -SourceRoot C:/code/FrenchExDev/FrenchExDev_i2 -ItemId Result -Target 'Result/FrenchExDev.Net.Result.slnx' -OutputFormat Json

# Explicit diagnostic assessment of all discovered entry points, without migration approval.
./scripts/Test-DotNetMigrationBuild.ps1 -SourceRoot C:/code/FrenchExDev/FrenchExDev_i2 -AllDiscovered -WhatIf -OutputFormat Json
```

`PolicyPath` selects the deny-by-default candidate list; `ItemId` and `Target` are exact configurable identifiers/relative paths, checked at execution rather than frozen in ValidateSet. `AllDiscovered` conflicts with ItemId and explicitly extends assessment only. `NoRestore` adds --no-restore; default build includes implicit restore. Every selected solution **and** project is built separately, even if a solution already includes a project; this produces individual receipts rather than inferred project success. Generated/cache/mutation directories are excluded and directory links are not traversed.

`TimeoutSeconds` bounds each target including SDK resolution; `TotalTimeoutSeconds` bounds the campaign. `RunDirectory` must be new; its default is outside sources under the shared temporary migration-builds category. `build-results.json` is always saved for a real run, with optional additional new `JsonPath`. Existing evidence files are refused. `OutputFormat` is Table (default), Json or Object. `RequireSuccess` throws after reporting on an incomplete/failed batch; ordinary diagnostic mode returns the failures. WhatIf returns a plan, never a success or an on-disk report.

Side effects are owned by [Invoke-DotNetMigrationBuild](lib/Migration.DotNet.md), which gates process/restore/build/report writes with ShouldProcess. Builds run sequentially in a normal-profile background process with the existing visible read-only resizing monitor. Reports include actual SDK version, target/hash/arguments, state, exit code, duration and bounded diagnostics/log paths. Native execution uses the independent CI helper; no product engine is loaded. The monitor uses the owned PowerShell worker identity; it does not invent the dotnet child PID.

Dependencies: Windows PowerShell 7.6+ for local visible monitoring, installed SDKs selected by each target directory's global.json, shared Common/Ci.Process/Watch-Tests tooling. There is no automatic SDK installation, source repair, retry, publication or Git operation. The optional implicit NuGet restore is part of the explicitly requested build.

Critical review: [facade](../../scripts/Test-DotNetMigrationBuild.ps1) delegates common parameters and returns pure JSON when requested; discovery/build/rendering are separate reusable functions. MSBuild can execute project-defined targets and referenced projects outside the whitelist: the whitelist scopes entry points, not a sandbox. A successful build is not test execution, cold-cache package consumption, evaluated-graph completeness or migration acceptance. Verdict: Release compilation evidence with explicit scope and remaining gates.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
