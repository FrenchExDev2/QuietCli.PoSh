# Test-LocalGalleryContainer.ps1

`DependencyStrategy` is a closed ValidateSet: `Automatic` exercises native preview dependency resolution; `PinnedClosure` explicitly publishes with dependency precheck bypassed, restores the known dependency at its exact preview identity, then restores the exact consumer with recursive resolution disabled. The latter still imports all real modules and verifies behavior/hashes; it is **not** evidence that automatic dependency resolution works. No silent fallback occurs between the modes. This distinction is needed for the observed PSResourceGet 1.2.0 preview dependency limitation.

Explicit exploratory BaGet compatibility probe. The [library](lib/LocalGallery.Probe.md) owns ShouldProcess and the monitored child worker. Both Image and LinuxClientImage are mandatory, not a built-in provider inventory.

```powershell
./scripts/Test-LocalGalleryContainer.ps1 -Image loicsharma/baget:latest -LinuxClientImage '<existing-local-image-with-pwsh>' -WhatIf
```

Executing without WhatIf may pull the selected server image, resolve both images to local immutable IDs, create disposable named resources, publish fixture previews on a loopback-bound feed and restore/import from isolated Windows/Linux clients. LinuxClientImage must already be available locally and contain PowerShell/PSResourceGet. RunDirectory must be new and external. The printed Watch-Tests command reopens saved progress/results.

The client verifies draft1 and dev1 plus a preview dependency and function result 42. Every client has its own result/identity; failed Windows means Linux is NotRun. This is not the full PSREG1 lifecycle, restart/backup, malformed-package, mutation or platform qualification. A tag is allowed for exploration; the observed image IDs are recorded, and the future product profile must pin its selected image/digest.

Dependencies: Windows PowerShell 7.6+ host, working Docker-compatible CLI/context, BaGet image access, existing Linux PowerShell image, PSResourceGet and shared CI process/monitor helpers. The worker keeps native execution independent from QuietCli. No public package publication occurs.

Critical review: [source](../../scripts/lib/LocalGallery.Probe.psm1:20) refuses an existing report directory and gates all setup by ShouldProcess. The actual server/provider is tested, not simulated. Runtime/container-network compatibility is environmental; failures remain evidence gaps. Verdict: reproducible exploratory probe; never a full registry qualification pass.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
