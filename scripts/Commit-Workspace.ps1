#requires -Version 7.6
<#
.SYNOPSIS
Commits the monorepo once, either staging all changes or preserving a prepared index; never pushes.
.DESCRIPTION
Before staging, runs Invoke-WorkspaceChecks.ps1: script layout/naming, script docs, workflow receipts/graphs/index,
new-script WhatIf/Confirm support, documentation credits and aggregate credits. The same registry
validates exported staged snapshots with NoAll. Explicit skip switches or SkipCheck report omissions;
NoSyncChecks skips documentation checks but retains independent script layout and safety checks.
Separately, warns (does not block) when a script file about to be committed (working tree, staged
or untracked, relative to $WorkspaceRoot) has no matching change to its mirrored doc under
docs/scripts/ - the doc Sync-ScriptsReadme.ps1 requires to exist, but whose content it never
inspects for staleness. Pass -NoScriptDocDriftWarning to override (silence) that warning; it never
blocks the commit on its own regardless.
Also warns (does not block) when a changed file - from its own `quiet git status` call, the one
intentional use of the quiet module in this otherwise quiet-independent script - is binary content
or larger than -MaxChangedFileSize, unless .gitattributes already marks it binary. Pass
-NoCommitFileSnifferWarning to override (silence) that warning; it never blocks the commit either.
Fully supports -WhatIf/-Confirm (SupportsShouldProcess): with -WhatIf, the sync gates and the drift
warning still run and report exactly as they would for a real commit, but the workspace lock is not
refreshed, nothing is staged and no commit is created.
With -NoAll, the working tree and index are never refreshed or staged. An isolated temporary index
snapshot supplies the source-lock and documentation checks, including during WhatIf preview.
.PARAMETER Message
Required commit message, without trailers.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER Repository
Only Workspace exists; retained to reject accidental requests for independent module commits.
.PARAMETER CoAuthoredBy
Opt-in, no trailer by default. Co-Authored-By trailers appended after the message, one per
contributing agent explicitly named by the caller; each entry is either `Name <email>` or a known
agent name from `$knownCoAuthors` (see docs/agents/README.md for the documented list). Skips an
entry already present verbatim in Message so a caller-supplied trailer is never duplicated.
.PARAMETER NoAll
Commits only the prepared index. Does not refresh the working-tree lock or stage any file.
Requires a repositories.lock.json matching the staged sources; validates an isolated index snapshot
before committing. Prepare and stage the matching lock together with the selected source changes.
.PARAMETER NoScriptsReadmeCheck
Skips the scripts/README documentation-coverage gate (Sync-ScriptsReadme.ps1).
.PARAMETER NoDocsCreditsCheck
Skips the docs credits-block gate (Sync-DocsCredits.ps1).
.PARAMETER NoCreditsCheck
Skips the aggregated CREDITS.md gate (Sync-Credits.ps1).
.PARAMETER NoSyncChecks
Skips documentation checks, including GitHub workflow, resource and script review documentation.
The ScriptLayout and ScriptShouldProcess checks remain active unless explicitly skipped.
.PARAMETER NoResourcesCheck
Skips generated resource inventory and dependency documentation validation.
.PARAMETER NoScriptContractsCheck
Skips obsolete objective-boilerplate detection and full script preview review validation.
.PARAMETER NoGitHubWorkflowDocsCheck
Skips workflow documentation receipts, generated job graphs and index validation.
.PARAMETER NoScriptShouldProcessCheck
Skips the new-script WhatIf/Confirm policy check.
.PARAMETER SkipCheck
Names in the shared Invoke-WorkspaceChecks registry to skip explicitly; each skip is reported.
.PARAMETER NoScriptDocDriftWarning
Overrides (silences) the script/doc drift warning described above. The warning is informational
only; it never blocks the commit whether this switch is passed or not.
.PARAMETER MaxChangedFileSize
Human-readable size (see Common.psm1's ConvertTo-QuietByteCount: "500KB", "1MiB", "2GiB", or a bare
integer for raw bytes) above which a changed file is flagged by the binary/size sniffer. Default
"500KB".
.PARAMETER NoCommitFileSnifferWarning
Overrides (silences) the binary/oversized-file warning described above. The warning is
informational only; it never blocks the commit whether this switch is passed or not.
.EXAMPLE
./scripts/Commit-Workspace.ps1 -Message "Add Build-Workspace DRY refactor" -CoAuthoredBy Claude
Runs every sync gate and the drift warning, then stages and commits as usual.
.EXAMPLE
./scripts/Commit-Workspace.ps1 -Message "Quick fix" -NoSyncChecks -NoScriptDocDriftWarning
Skips every documentation-sync gate and the drift warning; still refreshes the lock, stages and
commits.
.EXAMPLE
./scripts/Commit-Workspace.ps1 -Message "Preview" -WhatIf
Runs the gates and reports script/doc drift, but refreshes nothing, stages nothing and commits
nothing.
.EXAMPLE
./scripts/Commit-Workspace.ps1 -Message "Commit selected changes" -NoAll
Validates and commits the prepared index with its matching source lock; preserves unstaged changes.
.EXAMPLE
./scripts/Commit-Workspace.ps1 -Message "Vendor a tool" -MaxChangedFileSize 2MiB
Raises the binary/oversized-file sniffer's threshold to 2 MiB for this run only.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Message,
    [string]$WorkspaceRoot = (Split-Path $PSScriptRoot -Parent),
    [ValidateSet('Workspace')][string]$Repository = 'Workspace',
    [string[]]$CoAuthoredBy = $null,
    [switch]$NoAll,
    [switch]$NoScriptsReadmeCheck,
    [switch]$NoDocsCreditsCheck,
    [switch]$NoCreditsCheck,
    [switch]$NoSyncChecks,
    [switch]$NoGitHubWorkflowDocsCheck,
    [switch]$NoScriptShouldProcessCheck,
    [switch]$NoResourcesCheck,
    [switch]$NoScriptContractsCheck,
    [string[]]$SkipCheck=@(),
    [switch]$NoScriptDocDriftWarning,
    [string]$MaxChangedFileSize = '500KB',
    [switch]$NoCommitFileSnifferWarning
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Commit-Workspace.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptCommitWorkspace @PSBoundParameters
