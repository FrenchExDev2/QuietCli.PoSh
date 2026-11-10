# DotNetLocks.psm1

## Purpose

Maintain SDK/CI source locks and runtime project pins through explicit metadata and file
policies. Exports Resolve-DotNetBaseImage, Get-DotNetBaseImageTags, Update-DotNetCiLock,
Get-DotNetRuntimeFrameworkPlan and Update-DotNetRuntimeFrameworkVersion.

## Usage and parameters

```powershell
Import-Module ./scripts/lib/DotNetLocks.psm1
$base = Resolve-DotNetBaseImage -Image debian -Tag bookworm-slim
$plans = Update-DotNetCiLock -IncludeDevelopmentLock -RefreshBaseImages -PlanOnly
$runtime = Get-DotNetRuntimeFrameworkPlan -Version 11.0.0
```

See the [user guide](../../../README-dotnet-and-global-dot-json.md) and mirrored entry
points for SDK/global.json, runtime/framework/path and optional image-tag parameters.
The planner is read-only; public network/write operations support WhatIf/Confirm.

## Dependencies and effects

Initialization only declares functions, strict mode and a sibling DotNetReadiness import.
Registry reads use bounded HTTPS requests, fixed official hosts and caller-local anonymous
bearer tokens. Tokens are not persisted or returned. SDK/runtime hashes come from the
existing official metadata reader. No SDK archives or container layers are downloaded.
Approved writes use original-byte backups, observed-source hash checks and atomic
per-file replacement. Import itself performs no business I/O.

## Findings

- scripts/lib/DotNetLocks.psm1:5 bounds registry responses/timeouts and rejects other hosts;
  :24 verifies exact index bytes/digest and required platforms. Auth/HTTP/malformed evidence
  throws before lock writes; no certificate bypass or automatic retry is used.
- :78 rejects duplicate JSON properties; :99 requires unique canonical archive records;
  :110 handles unchanged files, backups and source-change detection. There is no cross-file
  transaction or guarantee against every concurrent filesystem race.
- :128 preserves unrelated tool/version fields while aligning the exact global.json SDK
  across four Linux and optionally two Windows archives. OS tag changes are opt-in and
  remain unqualified until package compatibility and real image execution are tested.
- :210 edits only validated runtime property spans. DTDs, links, out-of-root files,
  unresolved/ambiguous framework conditions and implicit downgrades are rejected.
- Offline Locks fixtures cover real files/hashes and byte-digest checks with stubbed metadata,
  deterministic XML/source-label properties, malformed inputs and assertion-killed mutants.

## Verdict

A cohesive reviewed library under scripts/lib, with explicit exports and no import-time
network/business effects. Native image builds, product binaries and the hosted release
matrix require their own evidence after pin changes.

<!-- script-contract:begin -->
## Execution contract

Purpose: Resolves an official Docker Hub tag to its exact multi-platform index digest.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 4.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
