# Update-DotNetRuntimeFrameworkVersion.ps1

## Purpose

Update RuntimeFrameworkVersion properties for a selected framework without changing
other frameworks or broadly replacing matching strings.

## Usage and parameters

```powershell
./scripts/Update-DotNetRuntimeFrameworkVersion.ps1 -WhatIf
$plans = ./scripts/Update-DotNetRuntimeFrameworkVersion.ps1 -PlanOnly
./scripts/Update-DotNetRuntimeFrameworkVersion.ps1 -Version 11.0.0 -Confirm
```

WorkspaceRoot defaults to this checkout. Version is an exact runtime version, not an SDK
version; omitted derives the runtime paired with global.json's SDK. Path selects exact
project/props files, otherwise generated/toolchain directories are pruned during discovery.
Framework defaults to net11.0. Preleases and AllowDowngrade are explicit policy choices.
PlanOnly resolves/validates plans without writing; WhatIf makes no metadata request.

## Dependencies and effects

Uses scripts/lib/DotNetLocks.psm1 and official runtime/release metadata. The approved
operation validates all selected XML first, creates unique original-byte backups and
atomically replaces changed files. No compilation or image build occurs.

## Findings

- scripts/Update-DotNetRuntimeFrameworkVersion.ps1:25 guards delegation. The planner at
  scripts/lib/DotNetLocks.psm1:210 rejects outside-root paths, links, DTDs, unsupported
  XML forms and ambiguous multi-target/condition semantics.
- Explicit target-framework property/group conditions and single-target project pins
  are supported. Literal property values are changed by source spans, preserving XML
  formatting, comments and other target-framework values.
- This updates source, not existing binaries/runtimeconfig files. Rebuild and qualify
  those outputs before relying on the new pin. Multi-file writes are not a transaction.

## Verdict

Use for explicit runtime-source maintenance with offline preservation, malformed-XML,
downgrade, idempotence and targeted mutation checks. Complex MSBuild conditions remain
manual-review boundaries.

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [DotNetLocks.psm1](lib/DotNetLocks.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Updates unambiguous RuntimeFrameworkVersion properties for one target framework.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
