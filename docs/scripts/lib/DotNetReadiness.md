# DotNetReadiness.psm1

## Purpose

Share release selection, manifest checks and typed native inventories for .NET tooling.
Exports Get-DotNetReadiness, Get-DotNetSdkRelease, Get-DotNetInstallation and
Invoke-DotNetContainerPull. [User guide](../../../README-dotnet-and-global-dot-json.md).

## Usage and parameters

```powershell
Import-Module ./scripts/lib/DotNetReadiness.psm1
$release = Get-DotNetSdkRelease -Channel 11.0 -Confirm:$false
$inventory = Get-DotNetInstallation -Confirm:$false
```

Release selection accepts Channel, optional Version, Preleases and metadata timeout.
Readiness additionally accepts archive RIDs, platforms, variant, project/report paths
and SkipLocal. Native inventory accepts an exact DotNetPath and a selected QuietCliRoot.
Container pulling requires an explicit client/image/platform after higher-level resolution.
All exported effectful probe/pull functions support standard WhatIf/Confirm.

## Dependencies and effects

Only declarative initialization and function definitions run at import. HTTP uses bounded
.NET requests, with normal TLS validation and no automatic retry. Native infrastructure
is loaded from the selected checkout's scripts/Ci.Process.ps1, not its product module.
The caller owns retained typed records; native business output is not automatically spooled.

## Findings

- scripts/lib/DotNetReadiness.psm1:4 bounds JSON reads; :34 selects SDKs semantically;
  :63 distinguishes absent image/platform evidence from failed transport/parsing.
- :170 uses the independent process helper with exact arguments and a 30-second query
  deadline. Parser exceptions propagate and non-success/exit-code results cannot establish readiness.
- Image pulls use the same process helper with a bounded deadline. Podman retries are disabled.
- Archive HEAD availability is not archive-byte integrity; manifests do not prove runtime
  execution or Windows host/build compatibility. The provisioning library verifies downloaded bytes.

## Verdict

A cohesive automation library with explicit exports and dependency boundaries. Offline
HTTP/record/native-adapter assertions cover its delivered scope; actual registry pulls
and all operating systems remain separate qualification work.

<!-- script-contract:begin -->
## Execution contract

Purpose: Reads bounded public HTTP evidence without retries or certificate bypasses.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 4.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
