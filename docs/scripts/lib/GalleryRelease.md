# GalleryRelease.psm1

`Resolve-QuietGalleryReleaseBatch` validates bounded annotation JSON or explicit members against current publication policies and exact manifest versions. It rejects wrong revisions, duplicate modules, disabled/unknown owners and absent trigger membership, then uses workspace dependency order to elect one leader. It performs no Git/network operation; the release-plan entry point verifies all remote tag commits before starting qualification.

The schema version must be an integer, not a coercible boolean. The parser rejects duplicate fields, malformed JSON, non-array tags and oversized batches. Seeded member permutations preserve the same leader; a remote-revision guard mutant is rejected by the foreign-commit counterexample.

## Purpose and usage

Get-QuietGalleryReleaseTargets discovers business projects from existing WorkspaceProjects/manifests, derives identity through ModulePackage and checks the explicit boolean Publishable policy. IncludeDisabled exposes disabled business targets for diagnostics; test projects are always excluded.

Select-QuietGalleryReleaseTargets accepts component aliases, exact package names or All, rejects unknown/disabled targets, deduplicates selection and preserves dependency ordering. Core and Git are currently enabled; Vagrant is disabled.

Resolve-QuietGalleryReleaseTag accepts the exact package namespace and full version, then requires a unique discovered target, publication eligibility and an exact owning manifest version. It returns module/component/project/version metadata. No hardcoded Core/Git/Vagrant switch or second publication YAML is used.

## Dependencies and effects

Imports the pure ModulePackage reader and privately loads WorkspaceProjects inside discovery. Import declares/exports three functions only. Calls read literal manifests/source and return metadata; no product import, native command, write, network access or publication occurs. build/companions.yml continues to own test/image declarations and must cover new publication targets.

## Review and validation

CI optimization and release-tag tests cover malformed names, independent versions, disabled flags, dynamically added fixture modules and plan outputs. GalleryPreview separately verifies Core/Git package contents, dependencies and isolated imports. Discovery and a true publication flag do not establish remote Gallery availability or qualification of unexecuted commands/providers.

<!-- script-contract:begin -->
## Execution contract

Purpose: Discovers independently versioned business packages from the existing workspace manifests.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
