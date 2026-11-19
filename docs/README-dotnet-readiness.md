# .NET release readiness

Start with [SDK installation and global.json](../readmes/README-dotnet-and-global-dot-json.md).
The release checker queries published SDK archives, official MCR image/platform manifests,
installed SDK/runtime inventories and actual SDK resolution. It complements the existing
[SDK/Crossgen2 feasibility checker](scripts/Test-SdkReadiness.md).

```powershell
$report = ./scripts/Test-DotNetReadiness.ps1 -Channel 11.0
$report.Checks | Select-Object Category, Target, Status, Detail
./scripts/Test-DotNetReadiness.ps1 -Preleases -WhatIf
```

Stable is the default. Preleases includes preview and RC versions; semantic ordering
still permits stable versions. WhatIf makes no HTTP/native requests or file writes.
Unknown network/authentication/TLS evidence never counts as absence or success.
Archive HEAD availability is not archive integrity verification. Image manifests prove
requested OS/architecture availability, not local daemon health or application compatibility.

See [entry point](scripts/Test-DotNetReadiness.md),
[library](scripts/lib/DotNetReadiness.md) and [offline runner](scripts/Invoke-DotNetTests.md).
Native infrastructure uses Ci.Process.ps1 and requires no compiled product engine.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
