# New-QuietPreviewTag.psm1

Implements [New-QuietPreviewTag.ps1](../New-QuietPreviewTag.md). Exports only "Invoke-QuietScriptNewQuietPreviewTag". Imported without name checking; import defines the command without running the operation.

## New-QuietPreviewTag.ps1

Version-mode annotations declare the release batch and exact commit. The operator releases one module per run, so its batches have a single member; multi-module batches come from [Invoke-QuietRelease.ps1](../Invoke-QuietRelease.md). Only a batch's dependency-ordered leader starts the release matrix; sibling tag runs stop after validating the plan. Publication is ordered within the batch and retains every module's own version/tag. PR qualification remains independent. Existing manually created tags without batch metadata retain standalone behavior; no existing tag is rewritten to adopt batching.

## Purpose and usage

[Invoke-QuietRelease.ps1](../Invoke-QuietRelease.md) runs both steps below, the pull request, the required check and the merge in one resumable command; it is the recommended path and the only one that releases several modules together. The steps remain available manually for one module.

With Version, release exactly one dynamically discovered business package in two separate steps, because the protected `develop` branch only receives pull requests and the operator never pushes a branch:

1. Version commit: on a `fix/*`, `feature/*` or `release/*` branch created from origin/develop, when selected versions differ from HEAD, edit the manifests and commit them through the checked workspace pipeline. No tag is created. Push the branch and merge its pull request with any merge method. Running this step on the delivery branch fails with `ReleaseCommitRequiresWorkBranch`.
2. Tags: on a checkout of the merged commit, rerun with the same base version and `-NextPreview -NoCommit` (versions now match HEAD; per-module preview counters are recomputed identically while no tag was created in between). The operator fetches the remote delivery branch, requires HEAD to be contained in it (`ReleaseRevisionNotOnDeliveryBranch` otherwise), creates annotated tags, then atomically pushes exactly those tags.

With PushTag, atomically push existing local annotated release tags, for example tags created earlier with NoPush. Every member of an annotated batch must be supplied; all tags must designate the same commit, which must already be contained in the remote delivery branch, and none may exist remotely.

```powershell
./scripts/New-QuietPreviewTag.ps1 -Module Git -Version 0.3.0 -NextPreview -WhatIf
./scripts/New-QuietPreviewTag.ps1 -Module Git -Version 0.3.0 -NextPreview -Confirm
./scripts/New-QuietPreviewTag.ps1 -Module Git -Version 0.3.0 -Preview $null -NoPush
./scripts/New-QuietPreviewTag.ps1 -Module Git -Version 0.3.0 -Preview 4 -NoPush
./scripts/New-QuietPreviewTag.ps1 -Module Git -Version 0.3.0-preview4 -NoCommit
./scripts/New-QuietPreviewTag.ps1 -Module Git -Version 0.3.0 -NextPreview -NoCommit
./scripts/New-QuietPreviewTag.ps1 -PushTag FrenchExDev2.QuietCli.Core.PoSh/v0.3.0-preview1,FrenchExDev2.QuietCli.Git.PoSh/v0.3.0-preview1 -WhatIf
```

## Parameters and discovery

Module accepts exactly one component alias or full package name. Several values or All fail with `PreviewTagRequiresOneModule` before any Git call; use the facade for a multi-module release. Existing WorkspaceProjects/manifests supply module names, dependencies and PrivateData.QuietCli.Publishable; test modules and disabled companions are excluded. build/companions.yml still owns CI suite/image declarations, without a duplicate publication YAML.

Version is a numeric base or complete Gallery version. A numeric base without Preview/NextPreview requests stable publication and clears the source prerelease label. NextPreview computes the numeric maximum plus one per package/base version from local and remote tags. Preview accepts a positive number or explicit null for NextPreview; PowerShell requires that nullable argument, so NextPreview is the argument-free spelling. Complete suffixed versions cannot also request Preview.

NoCommit requires a clean checkout with selected versions already committed. NoPush still checks remote collisions and creates local tags, but skips the delivery-branch check and the tag push. Remote defaults to origin; DeliveryBranch (develop by default) names the protected branch that must contain tagged commits; Message optionally overrides the commit message. WorkspaceRoot selects the repository.

Standard WhatIf/Confirm applies to a concrete batch. WhatIf permits dirty sources, reads no remote and writes no manifest, index, commit, tag or receipt. With PushTag, WhatIf validates the local tags and batch membership only; it neither fetches nor pushes. Its counter estimate has RemoteChecked=false and is provisional.

## Collisions, effects and recovery

An existing exact local or remote tag causes refusal before edits. There is no force, replacement, retry or rollback. The atomic selected-tag push can still fail on a concurrent update. A NoPush run creates real local tags, so the same release subsequently refuses them; push them with PushTag or use WhatIf for repeatable previews. Tags created before a squash or rebase merge designate a commit absent from the delivery branch: PushTag refuses them, so delete those local tags and rerun the tag step on the merged commit.

Execution requires clean sources. Only selected manifests enter Commit-Workspace -NoAll; no internal source-lock refresh is performed. Unrelated changed paths still block the release commit. Branch delivery stays with Push-Workspace and its feature/fix/release PR-comment contract. An ignored artifacts/releases/<id>/release.json records commit, created tags and completed pushes; partial failures retain owned work and this receipt.

## Dependencies and legacy mode

Uses exact local Core/Git modules for operator Git calls and [ReleaseTags](../lib/ReleaseTags.md) for policy/orchestration. No dependency installation, build or direct Gallery publication occurs. Tag pushes request qualified CI publication. Git requires a compatible Core dependency to be available; Core is imported into the global scope before Git, also under `-WhatIf`, so Git's handler registers; simultaneous tags do not guarantee completion order of independent remote workflows.

Without Version, legacy local-only timestamp tagging and -Release remain available; they never commit/push. Timestamped Core markers stay outside publication filters.

## Review and validation

Owned-repository tests cover seeded numeric counters, manifest-driven discovery, refusal of several modules or All without effects, version/GUID/dependency preservation, annotated tags, exact commit identities, local and remote collisions, a private bare remote, NoCommit, NoPush and WhatIf, refusal to commit on the delivery branch, refusal to tag or push an unmerged commit, partial-batch and missing-tag PushTag refusal, deferred PushTag delivery after a simulated merge, repeated-push refusal, and a delivery-guard mutant that must accept the unmerged counterexample. Hosted publication is separate evidence.



## Dependency and regression contract

Local module identity compares native paths composed from separate root, module-directory and filename components. Equivalent Windows separators must not reject the selected checkout as a different module.

Shared helper imports reuse loaded modules and preserve caller command visibility across repeated invocations.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Creates a local annotated timestamp preview tag or an exact module release tag.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
