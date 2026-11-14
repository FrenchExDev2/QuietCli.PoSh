# Shared pinned-resource preparation

## Library boundary

Located at `scripts/lib/Resources.psm1`. Load with `Import-Module ([IO.Path]::Combine($root,'scripts/lib/Resources.psm1')) -DisableNameChecking -ErrorAction Stop`. Import defines functions and explicit dependencies without running business operations. Paths use `System.IO.Path`. Effects remain owned by the calling operation and its preview contract.

Explicit export surface:

```powershell
Export-ModuleMember -Function 'Ensure-QuietResource'
```


## Usage

imported this library, then call `Ensure-QuietResource -RelativePath resources/yaml/YamlDotNet.dll -AssemblyType YamlDotNet.Serialization.DeserializerBuilder`.

## Dependencies and effects

Reads the resource lock; verifies bytes before reuse; delegates selected package preparation to Restore-CoreResources; optionally loads the pinned assembly. `-WhatIf` returns Planned without restoring. `-Confirm` controls preparation. Loaded assembly identity is checked by hash.

## Critical review and verdict

Source: [Resources.psm1:16](../../../scripts/lib/Resources.psm1#L16). A mismatching assembly already loaded into the process requires restart. Native source-built resources require an explicit build; product import does not call this helper.

Verdict: suitable within the documented boundary; qualification evidence belongs in the companion test reports.

<!-- script-contract:begin -->
## Execution contract

Purpose: Verifies a pinned resource, restores its package when necessary, and optionally loads a managed type.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
