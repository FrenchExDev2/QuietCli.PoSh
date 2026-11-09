# Preview versions and GitHub publication

Keep the package name, GUID and numeric target release stable while iterating on a preview. For a target `0.2.0`,
the packaging workflow produces identities such as:

```text
0.2.0-preview00000042a0001
0.2.0-preview00000042a0002
0.2.0-preview00000043a0001
0.2.0
```

The eight-digit number is `GITHUB_RUN_NUMBER`; the four-digit attempt is `GITHUB_RUN_ATTEMPT`. The label is
alphanumeric and zero-padded for lexical ordering. A rerun that prepares packages gets a new identity. Keep the
workflow's counter continuity; if the workflow is replaced/reset, select a new target release rather than reusing
existing identities. Counters outside 1..99999999 and attempts outside 1..9999 fail explicitly.

The numeric version represents the target product release, not the number of CI attempts. Change it intentionally
for the next feature release or patch. The stable release removes the prerelease label. Gallery-compatible prerelease
labels do not use `preview1.42` or `+build42`; the numeric `ModuleVersion` stays separate from `PSData.Prerelease`.
See Microsoft's [module prerelease contract](https://learn.microsoft.com/powershell/gallery/concepts/module-prerelease-support)
and [NuGet ordering rules](https://learn.microsoft.com/nuget/concepts/package-versioning).

## Create a local timestamped Git tag

From the repository root, preview the name or create an annotated tag on the current commit:

```powershell
./scripts/New-QuietPreviewTag.ps1 -WhatIf
$tag = ./scripts/New-QuietPreviewTag.ps1
$tag.Tag
```

The script reads `ModuleVersion` from the Core `.psd1` in the selected repository. For version `0.2.0`,
an example is `v0.2.0-preview20261108T1330001234567Z`: UTC date/time followed by seven fractional-second
digits. `-Timestamp <DateTimeOffset>` supplies a reproducible instant; `-WorkspaceRoot <path>` selects another
QuietCli2 repository root. The default repository is the script's checkout, regardless of the current directory.
Creation requires a clean working tree and targets the exact observed HEAD. `-WhatIf` also works in a dirty
checkout and returns `Clean=false`. Existing tags are rejected without replacement or retry. Nothing is pushed
or published, and manifests are unchanged. These local Git tags are independent of the CI package counter below;
creating or pushing a tag does not trigger the develop-branch publication workflow.

The monitored `GalleryPreview` suite includes owned-repository lifecycle tests, seeded timestamp properties,
malformed version inputs and targeted tag identity mutations.

## Prepare and validate without publication

From a built checkout, PowerShell 7.6+:

```powershell
$packages = Join-Path ([IO.Path]::GetTempPath()) 'quietcli-preview-42-1'
./scripts/New-QuietPreviewPackage.ps1 -OutputDirectory $packages -BuildNumber 42 -Attempt 1
./scripts/Publish-QuietGallery.ps1 -PackageDirectory $packages -Version '0.2.0-preview00000042a0001' -ValidateOnly
```

The destination must be new. The scripts create the public Core `.nupkg`, `package-set.json` and `preview.json`.
They need no key and do not contact PSGallery. `-QualifiedRevision <sha>` optionally requires the actual checkout HEAD
to match a qualification receipt. Source manifests are unchanged: only copied package manifests receive the generated
label. Their numeric versions and GUIDs are preserved. Git remains a development companion and is never included in public packages.
Package preparation does not mark a release as published.

Use the dedicated offline qualification suite, with the shared visible monitor:

```powershell
./scripts/Invoke-WorkspaceCi.ps1 -Suite GalleryPreview -SkipBuild
```

Microsoft recommends a local/private repository for testing the publication process. Public previews are actual
releases for consumption and feedback, rather than disposable publication-test objects.

## Automatic previews and manual artifacts

`preview-psgallery.yml` runs on applicable source/infrastructure pushes to `develop` in the original repository.
It calls `publish-psgallery.yml`, which reuses `ci.yml` with `suite=All`. Only the exact `qualified_sha` may be packaged
and published. GitHub CI excludes native TTY/PTY execution, fuzzing and mutation; receipts record that scope explicitly. Local TTY campaigns remain available. Builds cover all embedded runtime distributions; the packaging job checks its actual build again.

The packaging job has no Gallery key. It uploads the Core nupkg and its plans as a run/version/attempt-specific
artifact. The publication job checks out the qualified revision, downloads that exact artifact and verifies its hashes,
version and the Core-only package set before publishing Core. It never rebuilds between artifact creation and publication.
Automatic previews whose `develop` head has advanced are skipped before publication.

For artifact-only CI, dispatch **QuietCli2 automatic develop previews** on `develop` with `publish=false` (the default).
For a manual release, dispatch **QuietCli2 qualified PowerShell Gallery release** with the exact source-manifest version;
publication remains an explicit boolean choice. PRs, forks and pushes to other branches do not publish automatically.

## Repository setup and receipts

- Keep `PSGALLERY_API_KEY` only in the existing `psgallery` GitHub environment. Never add it to source, command arguments,
  artifact contents or logs. GHCR continues to use its separate ephemeral `GITHUB_TOKEN`.
- That environment must allow deployments from `develop`. If approval protection is configured, previews wait for it;
  the workflow does not remove or bypass account settings. Stable releases still require manual workflow dispatch.
- The workflow files must be committed and pushed before GitHub can run them. A local test does not activate remote CI
  or prove that an environment secret, branch policy or public package is available.
- Publication receipts distinguish Prepared, Publishing, Published and Failed, including unknown effects and the modules
  already confirmed. A published version is never overwritten or retried automatically. After a partial publication,
  inspect the receipt and use a fresh packaging attempt; rerunning only the failed publication job reuses the old artifact
  and deliberately fails if that identity already exists.
- A full workflow rerun increments the attempt and prepares a new preview identity. `GITHUB_RUN_NUMBER` does not increase
  for a rerun, which is why the attempt is part of the suffix.

GitHub documents the [run counters](https://docs.github.com/actions/reference/workflows-and-actions/variables)
and [deployment environment settings](https://docs.github.com/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
