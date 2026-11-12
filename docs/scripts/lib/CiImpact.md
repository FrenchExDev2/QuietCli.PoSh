# CiImpact.psm1

Exports Get-QuietCiImpact and Test-QuietDevelopReceipt. Import is inert; no product module or native process starts.

Get-QuietCiImpact reads the validated YAML suite catalogue. Companion changes select all suites whose transitive requirements include that product. Core and shared/unknown changes select All plus tooling. Multiple affected suites share one matrix. Tooling.Tests belongs to its own campaign. Existing FrenchExDev application modules consume Core and separate executable companions; application membership does not qualify a CLI handler.

Test-QuietDevelopReceipt requires explicit booleans, exact tree/run/attempt identities and successful required Windows, Linux, performance, tooling and mutation outcomes. Missing fields fail closed.

The reviewed tooling-only boundary is exact: `scripts/New-RunProfile.ps1`, `scripts/Invoke-RunProfile.ps1`, `scripts/lib/RunProfileStore.psm1`, and restricted lowercase `scripts/RunProfiles/<name>.profile.ps1` definitions. These changes still require the complete tooling workflow. Shared profiler/encoding helpers, evidence reports, the impact resolver itself and unknown scripts retain All. Combining a tooling-only path with a product/shared path unions both requirements, independently of path order. CiScalability.Tests exercises generated names, malformed/sibling paths, mixed scopes and a targeted resolver mutation.

## Critical review and verdict

scripts/lib/CiImpact.psm1:1 favors a conservative full matrix over guessed dependencies. The caller supplies a complete no-rename diff. Companion manifests determine build closure; the YAML determines qualification/image requirements. Tests exercise known scopes, unknown paths, compound scopes, malformed paths, every required receipt field and stale identities. Hosted API and cache transfer behavior still require GitHub execution.

<!-- script-contract:begin -->
## Execution contract

Purpose: Selects product qualification from changed paths and transitive declared companion dependencies.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
