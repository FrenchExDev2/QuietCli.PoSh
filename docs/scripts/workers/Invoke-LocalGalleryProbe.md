# Invoke-LocalGalleryProbe.ps1

Internal exploratory worker of [Test-LocalGalleryContainer](../Test-LocalGalleryContainer.md). WorkspaceRoot supplies the independent shared runner; RunDirectory contains the explicit request. ShouldProcess guards the probe before any writes or container effects.

Stages: observe Docker context/versions; resolve an existing Linux client image; pull/resolve the explicit server; create owned network/volume/server with port published only on 127.0.0.1; check feed health; run a normal-profile Windows client with isolated user paths; run a Linux client container on the same owned network; retain per-client results and bounded native diagnostics; clean up exact resources after saving diagnostics. The Linux client connects via the gallery network alias, not its own localhost.

Source contract is [BaGet's official Docker guide](https://loic-sharma.github.io/BaGet/installation/docker/). This tests BaGet's NuGet v3 endpoint against actual PSResourceGet; compatibility is determined by observed results. The fixture API key is nonsecret and used only on the owned transient loopback server. No user API keys are read.

Critical review: [worker](../../../scripts/workers/Invoke-LocalGalleryProbe.ps1:30) uses bounded Ci.Process operations and records failure rather than interpreting server Running/HTTP 200 as a roundtrip success. It removes only successfully acquired unique named resources. Unknown startup effects and outer timeouts may need explicit follow-up using saved identities. Logs and failed client results remain outside sources. Full lifecycle/restart, multiarchitecture and destructive-package campaigns are future PSREG1 gates. Verdict: exploratory real-provider probe, not production orchestration.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
