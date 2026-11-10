# Migration.Exports.psm1

Exports `Test-PowerShellModuleExports`; see the [facade parameter reference](../Test-PowerShellModuleExports.md). Code callers compose the exported function directly. It validates the selected whitelist item and explicit entry, rejects directory traversal and reparse ancestors, verifies the entry exists, then calls ShouldProcess before any import/process/report creation. Preview returns no fabricated observation.

One normal-profile child process imports the selected entry. The worker calls Get-Module afterwards and records **actual** ExportedFunctions/ExportedCmdlets/ExportedAliases/ExportedCommands, dependency modules and toolchain identities. Functions found by AST and a manifest wildcard are not an observed export contract. Optional ExpectedFunctions and ExpectedCmdlets are compared exactly, independently; the full migration gate requires both comparisons, including explicit empty sets when applicable. Visibility/function-body correctness still require separate tests. StageCopy imports a bounded hash-verified owned copy and reports original/staged identities; that location-sensitive observation does not certify the original installation.

The shared background worker supervisor owns timeout/crash handling; a visible read-only monitor covers the whole run and closes after terminal evidence. The command prints the reopening path and returns State/RunDirectory/Observation/Qualification. No retry occurs after a failed import. RunDirectory must be new. Windows-only local-monitor support is an explicit tooling limitation, not a crossplatform product pass.

Critical findings: [source](../../../scripts/lib/Migration.Exports.psm1:30) checks selection before launch; separate process isolation avoids contaminating the controller's module/assembly state but is not a sandbox for file/network effects. The module's behavior can write outside its directory; review before probing non-owned code. Entry and policy hashes are rechecked in the worker; whole dependency closure freshness belongs to the migration gate. Verdict: real export observation with explicit authorization and evidence, not automatic code trust.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
