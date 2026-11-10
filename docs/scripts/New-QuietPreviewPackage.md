# New-QuietPreviewPackage.ps1

## Purpose and usage

Prepares a uniquely versioned, Core-only preview without publishing.

```powershell
./scripts/New-QuietPreviewPackage.ps1 -OutputDirectory <new-directory> -BuildNumber 42 -Attempt 1 -RequireReadyToRun
```

WorkspaceRoot defaults to the repository root. BuildNumber defaults to GITHUB_RUN_NUMBER; Attempt defaults to GITHUB_RUN_ATTEMPT or 1. QualifiedRevision, when supplied, must equal the checked-out HEAD and requires a clean checkout. This validates the qualified source snapshot, never the later develop branch head. RequireReadyToRun forwards the twelve-publication requirement to Gallery preparation.

## Dependencies and side effects

Uses Common.ps1, Gallery.ps1, New-QuietGalleryPackage.ps1 and Publish-QuietGallery.ps1 -ValidateOnly. Writes staged files, nupkg, package-set.json and preview.json. Source versions and GUIDs remain unchanged. No key, publication or remote branch query.

## Critical review

- `scripts/New-QuietPreviewPackage.ps1:48` propagates RequireReadyToRun. Preview qualification includes deterministic version properties, malformed counters, installation/publication fixtures and targeted mutations.
- The version suffix is `preview{run:D8}a{attempt:D4}`, with an alphanumeric Gallery prerelease label. Each qualified checkpoint may publish even after develop advances.
- A dirty developer checkout must omit QualifiedRevision for local fixtures; it cannot claim clean hosted qualification.

## Verdict

GitHub creates an immutable, uniquely versioned R2R preview artifact. Publication validates that checkpoint and those bytes independently.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Prepares and validates uniquely versioned Core-only preview packages without publishing or editing source manifests.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
