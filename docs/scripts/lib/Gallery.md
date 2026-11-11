# Gallery.psm1

## Purpose and usage

Shared package preparation and verification functions for Core and publishable companions. Consumers import `scripts/lib/Gallery.psm1`; the former `scripts/Gallery.ps1` entry is removed.

The explicit exports cover identity reading, staging, literal archive manifests, Gallery version/preview formatting, staged prerelease changes, XML reading, package-set validation and remote identity lookup. Import declares/exports functions only; it starts no engine, native process, network request or publication.

## Dependencies and effects

Identity and target discovery use the sibling ModulePackage/GalleryRelease modules. Runtime-target data is loaded privately when validating Core. Caller entry points own ShouldProcess and filesystem/publication effects. Staging copies source filenames/bytes unchanged; only an explicitly requested staged prerelease label is rewritten.

Each package set contains exactly one selected business package. Its name, version, GUID, dependency IDs/minimum versions and nuspec must agree with the owning manifest. Unsafe ZIP paths, extra packages, missing build receipts and modified declared binaries are rejected. Core additionally requires six RID payloads and verifies ReadyToRun headers when requested. Git contains its declared net10.0/net11.0 parser outputs and retains its Core dependency; it does not embed Core.

Remote lookups accept only currently publishable discovered packages and distinguish not-found from service failure. Publication keeps Publish-PSResource's dependency checks and never passes a skip-dependency flag.

## Review and validation

GalleryPreview tests validate malformed manifests, unchanged identities/bytes, selected staging mutations, Core/Git preparation, isolated installation and a real Git handler call. Publication fixtures use aliases and a non-secret placeholder. Local results do not establish hosted qualification or public availability of a compatible dependency version. Source, generated resource inventory and mirrored workflow contracts are checked together.

<!-- script-contract:begin -->
## Execution contract

Purpose: Reads the shared package identity from a script module and its literal sibling manifest.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
