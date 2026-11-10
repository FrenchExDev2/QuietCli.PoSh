# LocalGallery.Probe.psm1

Optional `DependencyStrategy` is Automatic or PinnedClosure. The explicit mode is forwarded unchanged to both clients and retained in evidence. PinnedClosure is an explicit fixture lock/restore strategy, not a qualification of automatic transitive preview resolution. The server's local image ID is used for the actual run; it must not be confused with a registry manifest digest when constructing a future pull reference.

Exports `Test-LocalGalleryContainer -Image <ref> -LinuxClientImage <existing-ref> [-RunDirectory <new>] [-WorkspaceRoot <tooling>]`. The [facade](../Test-LocalGalleryContainer.md) forwards parameters/common options. Image references are bounded to literal CLI-safe reference characters, never evaluated as shell code. WhatIf stops before report/process/network/container creation.

The library uses the common normal-profile background worker, visible monitor and supervisor. The worker records real image/client identities, per-client evidence and cleanup outcomes. Native qualification commands use Ci.Process, never the product engine. The monitor closes automatically after saved terminal results.

Critical findings: [launcher](../../../scripts/lib/LocalGallery.Probe.psm1:22) currently supports Windows local monitoring, while its Linux guest is a separate real client. This is an exploratory tooling harness, not the future provider/lifecycle package. No automatic provider fallback, retries, global config changes, engine rebuild or public publication. An outer process timeout can interrupt cleanup; owned resource names remain in the saved request/receipt for explicit investigation. Verdict: bounded compatibility evidence with explicit lifecycle and qualification gaps.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
