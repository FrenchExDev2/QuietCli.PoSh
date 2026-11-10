# Invoke-LocalGalleryClient.ps1

DependencyStrategy is Automatic (default) or PinnedClosure, with no automatic fallback. PinnedClosure explicitly disables the publisher's dependency precheck, saves DevDependency at 0.0.1-dev1, then saves DevConsumer at the same exact identity with recursive dependency checks disabled. Actual module import/functional assertions still run. Evidence marks AutomaticDependencyResolution=NotQualified in this mode; it must not be described as successful automatic transitive resolution.

Internal real PSResourceGet client of [the localhost probe](../Test-LocalGalleryContainer.md). Uri selects the owned explicit feed, RunDirectory owns outputs and Publish selects the producer/client. ShouldProcess guards repository registration, fixture creation, publication and restore.

The worker registers OwnedProbe in the isolated child's user-data path, optionally creates/publishes DevDependency and DevConsumer at 0.0.1-dev1 plus DraftWitness at 0.0.1-draft1, then finds/saves/imports the exact preview packages from that feed. The consumer computes 42 through the dependency; the draft function returns draft1. Get-Module records actual loaded paths/exports and hashes. The client never contacts PSGallery as an implicit fallback.

Dependencies: PowerShell and real PSResourceGet already installed in the selected host/image. Preview packaging uses ModuleVersion plus manifest Prerelease. Package outputs and module installations live under the owned client directory; the caller isolates HOME/LOCALAPPDATA/XDG_DATA_HOME before process startup. No real user repository registrations are intentionally changed.

Critical review: [client](../../../scripts/workers/Invoke-LocalGalleryClient.ps1:24) catches failure into client-summary.json; a missing preview dependency remains a failure. Client environment/profile/provider behavior requires actual execution, not an inferred pass from these instructions. Qualification does not cover all malformed metadata or installation folders/version order. Verdict: functional compatibility witness only.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
