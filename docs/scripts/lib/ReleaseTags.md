# ReleaseTags.psm1

Every operator-created module tag annotation carries the same bounded `QuietCli-Release-Batch` JSON (schema, exact commit and selected tag names). The tag workflow validates every member and elects one dependency-ordered leader. A Core/Git operation therefore runs one release qualification and one packaging build, publishing Core before Git. It retains independent module versions/tags; a separate PR validation is not reused as release evidence. Legacy/manual tags without batch metadata still trigger standalone release qualification.

## Purpose and usage

Shared release planning and orchestration behind [New-QuietPreviewTag](../New-QuietPreviewTag.md).

- `Get-QuietNextPreviewNumber` accepts a package name, numeric base version and local/remote tag records. It matches the complete escaped `<package>/v<base>-preview<N>` expression and computes the numeric maximum plus one. Other modules, versions, timestamps, malformed suffixes and peeled refs do not change the counter; overflow fails.
- `Get-QuietReleaseManifestText` returns a literal AST-based ModuleVersion/Prerelease edit, preserving GUIDs, dependency declarations, unrelated text and UTF-8/LF.
- `Invoke-QuietModuleRelease` discovers selected business packages, validates local and remote collisions, confirms a concrete plan, commits version edits through the checked commit callback, creates annotated tags and delegates branch push/PR updates before an atomic push of exactly the selected tags.

## Effects and boundaries

The Git callback uses the operator's local QuietCli facade with bounded metadata. Commit and branch-push callbacks reuse Commit-Workspace and Push-Workspace. These callbacks are injectable for owned-repository integration tests; they are not public operator parameters.

`-WhatIf` reads local metadata only and writes no manifest, index, commit, tag or receipt. Its next-preview estimate is provisional with `RemoteChecked=false`. Every real invocation, including `-NoPush`, reads the configured remote's tag refs before changes. A failed remote read fails the operation. No existing local or remote tag is replaced; no force or automatic retry is used. A competing push can still reject the atomic tag push.

`-NoCommit` requires a clean checkout whose selected versions already match HEAD. `-NoPush` skips branch/tag pushes but still checks remote tags and creates local tags. After local tag creation, a repeated invocation for that identity refuses the existing tag; inspect the receipt and explicitly handle existing refs rather than forcing a retry.

Version edits are committed together; independently selected packages may receive different preview numbers. An ignored artifacts/releases/<id>/release.json records commits, created tags and completed pushes. BranchPushState/TagPushState distinguish NotRequested, Pending, Confirmed and Unknown. A client failure after an attempted push does not prove the server rejected it; inspect remote refs before any recovery. Failures retain owned changes/tags; an earlier branch push is not rolled back.

## Review and validation

The CI optimization case exercises seeded numeric preview properties, metadata-driven discovery, real disposable commits, annotated tags, pushes to a private local bare repository, local/remote collisions, NoCommit, NoPush and no-write preview. No public Gallery publication is a test. Import declares functions only and performs no business action.

<!-- script-contract:begin -->
## Execution contract

Purpose: Computes the next numeric preview from exact package/version tag names, independently of lexical ordering.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
