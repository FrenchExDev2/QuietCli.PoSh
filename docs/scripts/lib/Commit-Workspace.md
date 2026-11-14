# Commit-Workspace.psm1

## Purpose and exported operation

Implements [Commit-Workspace.ps1](../Commit-Workspace.md) through the single exported
`Invoke-QuietScriptCommitWorkspace` command. Importing this library defines commands without
running checks, staging files or creating a commit. Internal helpers share the operation's
parameter scope. Dependencies are explicit imports from `scripts/lib` with
`-DisableNameChecking -ErrorAction Stop`; paths use `System.IO.Path`.

## Usage

Use the entry point from the repository root:

```powershell
./scripts/Commit-Workspace.ps1 -Message 'Enforce automation layout'
./scripts/Commit-Workspace.ps1 -Message 'Preview checkpoint' -WhatIf
./scripts/Commit-Workspace.ps1 -Message 'Commit prepared index' -NoAll
```

`WorkspaceRoot` selects the repository. `Repository` accepts only `Workspace`.
`CoAuthoredBy` is opt-in and deduplicates trailers already present in the message.
No build, companion campaign, push, tag, PR creation or publication is implicit.

## Shared checks

The [shared registry](../Invoke-WorkspaceChecks.md) validates ScriptLayout, TestCaseMetadata,
ScriptsReadme, GitHubWorkflowDocs, ScriptShouldProcess, Resources, ScriptContracts,
DocsCredits and Credits. ScriptLayout rejects invalid Verb-Noun names, functions in entry
points, misplaced modules, Join-Path and imports lacking DisableNameChecking. Legacy preview
waivers do not waive this policy. Check failures stop the commit.

The default mode checks the working tree, refreshes its source lock, stages all changes and
creates one commit. `NoAll` preserves the working tree and index, exports an isolated prepared
index snapshot, verifies its own source lock and checks that snapshot. Unstaged fixes cannot
qualify a bad prepared index. Temporary snapshots are removed from their checked owned root.

`SkipCheck` explicitly omits named checks. The compatibility switches are
`NoScriptsReadmeCheck`, `NoDocsCreditsCheck`, `NoCreditsCheck`, `NoGitHubWorkflowDocsCheck`,
`NoScriptShouldProcessCheck`, `NoResourcesCheck` and `NoScriptContractsCheck`.
`NoSyncChecks` skips documentation checks while retaining ScriptLayout and ScriptShouldProcess.
An omitted check is reported as skipped, never as successful.

## Warnings and parameters

The script/doc drift warning compares changed `.ps1` and `.psm1` paths with their mirrored
Markdown documents. `NoScriptDocDriftWarning` suppresses it. The binary/size warning reads
pending paths through the local built QuietCli Core/Git modules, samples file content and
checks `.gitattributes`. `MaxChangedFileSize` defaults to `500KB` and uses
[Common.psm1](Common.md)'s byte-count parser. `NoCommitFileSnifferWarning` suppresses it.
Both warnings are informational and do not independently block a commit. Business output is
not automatically captured; orchestration retains bounded failure diagnostics.

## Preview and effects

Standard WhatIf/Confirm guards lock refresh, staging and commit. WhatIf still runs the
check registry and warnings, but does not refresh the lock, stage or commit. NoAll preview
also validates an exported index. Read-only checks may prepare a missing checksum-pinned
YAML parser only through its own guarded resource contract; preview options cross library
boundaries explicitly. Detailed process/Git failures remain failures and are not retried.

The optional warning uses the checkout's existing verified Core/Git binaries; importing this
library does not rebuild or install them. Native CI orchestration uses the independent
Ci.Process library. This command does not infer authorization for a push or publication.

## Validation and limits

The Tooling companion uses disposable Git repositories for commit-once behavior, source-lock
checks, prepared-index isolation, WhatIf, explicit omissions and warnings. Generated filename
and size cases and targeted mutations verify meaningful failures. Layout policy assertions
also include malformed PowerShell, nested functions, filters and import variants. Local,
filtered development runs remain partial evidence; they do not qualify the hosted matrix.

<!-- script-contract:begin -->
## Execution contract

Purpose: Commits the monorepo once, either staging all changes or preserving a prepared index; never pushes.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

## Fresh-session product loading

Core is bound to process-global scope before importing Git, because Git registration resolves Core commands there. Both modules must come from this checkout; a conflicting loaded path requires a fresh session. No profile is changed and imports do not rebuild binaries. The Tooling layout regression previews Commit-Workspace in a clean, profile-disabled child and rejects missing-registration or skipped-sniffer warnings.

Command binding temporarily disables preview/confirmation only while importing inert product definitions, then restores both preferences before business operations. This lets the read-only sniffer bind the exported quiet alias during preview without weakening lock, staging, commit or branch guards.
