# New-QuietPreviewTag.ps1

## Purpose and usage

With Version, create a release for one or more dynamically discovered business packages: edit selected versions, commit through the checked workspace pipeline, create annotated tags, push the branch through Push-Workspace, then atomically push exactly those tags.

```powershell
./scripts/New-QuietPreviewTag.ps1 -Module Core,Git -Version 0.3.0 -NextPreview -WhatIf
./scripts/New-QuietPreviewTag.ps1 -Module Git -Version 0.3.0 -NextPreview -Confirm
./scripts/New-QuietPreviewTag.ps1 -Module Git -Version 0.3.0 -Preview $null -NoPush
./scripts/New-QuietPreviewTag.ps1 -Module Git -Version 0.3.0 -Preview 4 -NoPush
./scripts/New-QuietPreviewTag.ps1 -Module Git -Version 0.3.0-preview4 -NoCommit
```

## Parameters and discovery

Module accepts component aliases, full package names or All. Existing WorkspaceProjects/manifests supply module names, dependencies and PrivateData.QuietCli.Publishable; test modules and disabled companions are excluded. build/companions.yml still owns CI suite/image declarations, without a duplicate publication YAML.

Version is a numeric base or complete Gallery version. A numeric base without Preview/NextPreview requests stable publication and clears the source prerelease label. NextPreview computes the numeric maximum plus one per package/base version from local and remote tags. Preview accepts a positive number or explicit null for NextPreview; PowerShell requires that nullable argument, so NextPreview is the argument-free spelling. Complete suffixed versions cannot also request Preview.

NoCommit requires a clean checkout with selected versions already committed. NoPush still checks remote collisions, commits version changes and creates local tags, but skips branch/tag pushes. Remote defaults to origin; Message optionally overrides the commit message. WorkspaceRoot selects the repository.

Standard WhatIf/Confirm applies to a concrete batch. WhatIf permits dirty sources, reads no remote and writes no manifest, index, commit, tag or receipt. Its counter estimate has RemoteChecked=false and is provisional.

## Collisions, effects and recovery

An existing exact local or remote tag causes refusal before edits. There is no force, replacement, retry or rollback. The atomic selected-tag push can still fail on a concurrent update; a prior branch push may already have succeeded. A NoPush run creates real local tags, so the same release subsequently refuses them; use WhatIf for repeatable previews.

Execution requires clean sources. Only selected manifests and the refreshed lock enter Commit-Workspace -NoAll. Push-Workspace retains the feature/fix PR-comment contract. An ignored artifacts/releases/<id>/release.json records commit, created tags and completed pushes; partial failures retain owned work and this receipt.

## Dependencies and legacy mode

Uses exact local Core/Git modules for operator Git calls and [ReleaseTags](lib/ReleaseTags.md) for policy/orchestration. No dependency installation, build or direct Gallery publication occurs. Tag pushes request qualified CI publication. Git requires a compatible Core dependency to be available; simultaneous tags do not guarantee completion order of independent remote workflows.

Without Version, legacy local-only timestamp tagging and -Release remain available; they never commit/push. Timestamped Core markers stay outside publication filters.

## Review and validation

Owned-repository tests cover seeded numeric counters, manifest-driven discovery, version/GUID/dependency preservation, annotated tags, exact commit identities, local and remote collisions, a private bare remote, NoCommit, NoPush and WhatIf. Hosted publication is separate evidence.

<!-- script-contract:begin -->
## Execution contract

Purpose: Creates a local annotated timestamp preview tag or an exact module release tag.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
