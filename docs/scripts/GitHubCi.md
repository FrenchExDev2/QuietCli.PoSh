# GitHubCi.ps1

Pure policy functions shared by GitHub matrix selection, the Linux aggregate gate and companion tests.

`Get-GitHubCiExecutionMatrix -Images $rows` requires exactly the four native Linux targets. A record
includes `Rid`, `Platform`, `Runner` and a verified immutable GHCR `Reference`, or null for a missing
image. It rejects duplicate/missing targets, wrong native runners and mutable/foreign references.
Accessible images select job containers; missing images select Docker fallback without publication.
Alpine ARM64 always selects fallback because GitHub's JavaScript action host supports Alpine on x64
only. Checkout/upload actions remain on Ubuntu ARM64 and the tests run inside the real musl container.

`Assert-GitHubCiLinuxResults` requires successful image selection and success for every selected
matrix. Only an unselected path may be skipped. No required target can disappear behind a skipped job.

Both functions are offline: no native process, registry access or publication. Tests enumerate cache
availability combinations, shuffled inputs, invalid references and terminal states, and use targeted
policy mutants. This is orchestration-policy evidence, not hosted ARM qualification.

Source: [GitHub runner Alpine support](https://github.com/actions/runner/blob/main/src/Runner.Worker/Handlers/StepHost.cs).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Partitions all four native Linux targets between verified GitHub containers and Docker fallback.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
