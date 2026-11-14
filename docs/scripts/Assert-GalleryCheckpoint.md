# Assert-GalleryCheckpoint.ps1

Validates a downloaded preview's `SourceRevision`, `QualifiedRevision` and version against the exact
checkpoint emitted by this run's qualification and packaging jobs. It also requires the package-set
version to match. It never queries the current `develop` HEAD, contacts a registry, reads a key or
publishes. Moving `develop` forward does not invalidate an already qualified checkpoint.

```powershell
./scripts/Assert-GalleryCheckpoint.ps1 -PackageDirectory ./artifacts/gallery -QualifiedRevision $qualifiedRevision -Version $releaseVersion
```

All three parameters are mandatory. `-QualifiedRevision` requires a 40-character Git SHA;
`-Version` requires a Gallery-compatible prerelease version. Metadata files must exist and each be
at most 128 KiB. Revision/version mismatch, malformed JSON or missing metadata fails the step.
Success returns `CheckpointValidated`, the version/revision and `BranchHeadQueried=false`.
The adjacent `Publish-QuietGallery.ps1 -ValidateOnly` step independently verifies the prepared
`.nupkg` set and SHA-256 checksums before publication uses those same files.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Validates a prepared preview against its qualified immutable checkpoint without querying branch HEAD.

Boundary: **ReadOnly**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
