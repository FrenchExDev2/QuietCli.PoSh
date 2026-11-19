# Remove-QuietMergedOriginBranches.psm1

<!-- script-source:begin -->
Source file: [`lib/Remove-QuietMergedOriginBranches.psm1`](../../../scripts/lib/Remove-QuietMergedOriginBranches.psm1)
<!-- script-source:end -->

`Invoke-QuietScriptRemoveQuietMergedOriginBranches` implements the [origin cleanup](../Remove-QuietMergedOriginBranches.md). Import defines the command. It uses Git, GitHub CLI and the existing [process helper](Ci.Process.md), [merged pull request parser](MergedBranches.md) and [remote reference parser](WorkBranch.md). Authenticate GitHub CLI for the pull request query and configure Git authentication for `origin`.

## Plan and deletion

The library compares the effective fetch and push destinations of `origin` and requires one URL per direction for the same `github.com` repository. It reads live branch tips and the symbolic default branch with `git ls-remote`. It queries merged pull requests through `gh pr list`, scoped to that repository and `develop`. The pull request parser excludes forks and selects the highest-numbered merged pull request for each head branch. An absent PR or differing SHA keeps the branch. Each row includes the full ref and SHA for review.

The [orchestration](../../../scripts/lib/Remove-QuietMergedOriginBranches.psm1) sends all confirmed deletions in one atomic Git push, with an explicit expected SHA for every ref. The GitHub reference deletion API accepts a ref name and provides no expected SHA parameter. An updated tip, a GitHub protection rule or a server without atomic push support can reject the batch. After a tool failure, rerun the read-only plan to reconcile the remote before retrying. Git can update the corresponding local remote-tracking refs after a successful push. Local branch refs are preserved. [Git push reference](https://git-scm.com/docs/git-push) · [GitHub reference deletion API](https://docs.github.com/en/rest/git/refs#delete-a-reference).

## Validation scope

The evidence is the PR's merge record and the branch's current SHA. It does not test whether a later history rewrite removed that merge from `develop`. The query limit can omit older PRs, which keeps branches without available evidence. A branch recreated at the exact merged SHA has the same evidence as the original. Branch protection and permissions are enforced by the remote at push time.

[Unit tests](../../../test/scripts/unit/lib/Remove-QuietMergedOriginBranches.Tests.ps1) cover the policy with generated valid and malformed refs and verify the push arguments with module doubles. [Integration tests](../../../test/scripts/integration/entrypoints/Remove-QuietMergedOriginBranches.Tests.ps1) cover preview, destination validation and the effect of a stale SHA lease on a real atomic push to a local bare repository. The policy is registered as the `MergedOriginBranches` mutation target.

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs Git or gh and returns its bounded standard output on success.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
