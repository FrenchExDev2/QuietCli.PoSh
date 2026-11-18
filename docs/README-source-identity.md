# Internal sources and external dependency locks

QuietCli has one Git repository. Git commits and trees identify committed internal sources,
including project manifests, automation and build configuration. Projects and their dependency
order are discovered from the manifests; contributors do not regenerate a committed workspace
snapshot after editing an internal file.

## External inputs

Keep reviewed versions, origins, licenses and integrity hashes for inputs obtained outside this
repository. Existing contracts include Core's `resources/dependencies.lock.json`, the SDK/image
and workstation locks under `build/`, and `build/powershell-hosts.lock.json`. SDK and NuGet
declarations remain in `global.json` and `Directory.Packages.props`; those declarations alone
are not a checksum lock of every transitive package. See [resource integrity](../readmes/README-resources.md)
for the download and verification boundaries.

Vendored upstream sources also retain their original provenance and license evidence, even when
their imported bytes are tracked by Git. Git records our changes; it does not establish the
upstream origin, authenticity or security of a downloaded dependency.

## Build, test and package evidence

`Get-QuietWorkspaceIdentity` records the available Git revision and committed tree, dirty state,
and hashes of the actual selected tracked and non-ignored untracked source files. On a dirty
checkout the Git tree identifies the committed baseline, not the modified working content.
Source hashes remain necessary to identify that content and detect drift during execution.

Build manifests still bind compiled files to their actual compiler inputs. Tests reject stale
or modified binaries, including with `-SkipBuild`. Test reports and package manifests retain
their source evidence as generated artifacts, without asking each PR to commit another global
source hash. A source snapshot or a successful local checkpoint is not platform qualification.
Transported checkouts without Git metadata retain their explicit transport-origin receipt;
missing revision/tree values remain unknown. Use that receipt for the original Git and dirty
state; local repository fields do not establish the cleanliness of an upstream checkout.

## Contributor commands

- `scripts/Initialize-Workspace.ps1` validates the discovered monorepo structure. Add `-Restore`
  to restore and verify the pinned external Core resources.
- `scripts/Invoke-WorkspaceChecks.ps1` runs the shared source and documentation policy checks.
- `scripts/Commit-Workspace.ps1 -Message '...'` runs those checks, stages changes and commits once.
  `-NoAll` validates only an exported prepared index and preserves unstaged work. Neither mode
  creates a source lock or launches companion tests.
- `scripts/Invoke-WorkspaceCi.ps1` runs an explicitly selected test campaign with its monitor
  and saved evidence. It does not commit. There is no `Commit-WorkspaceCi.ps1` entry point.

The former `repositories.lock.json` and `Update-WorkspaceLock.ps1` are retired. Existing
external dependency locks remain reviewed source inputs and are changed only when their
corresponding external inputs change. Required PR and release qualification remains in GitHub CI.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
