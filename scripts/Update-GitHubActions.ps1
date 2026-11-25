#requires -Version 7.6
<#
.SYNOPSIS
Reports, and with -Apply writes, the latest release of every action referenced by the GitHub workflows and composite actions.
.DESCRIPTION
Reads .github/workflows/*.yml|yaml and .github/actions/**/action.yml|yaml, resolves the latest release of each
distinct remote action through the GitHub API (GH_TOKEN or GITHUB_TOKEN when set, anonymous otherwise) or a
reviewed -ReleaseCatalogPath, and prints one row per action and current ref.
A commit pin stays a commit pin: it moves to the release commit and its '# vX.Y.Z' comment to the release tag.
A version tag moves to the release tag. Branches, pins above the latest release and repositories without a
release are reported and left alone; local (./) and docker:// references are ignored.
Without -Apply nothing is written. With -Apply, each changed workflow or action and its optional receipt
share a ShouldProcess decision. -WhatIf previews the paths and -Confirm asks once per update. Every release
is resolved and every change validated before the first write.
.PARAMETER WorkspaceRoot
Checkout whose .github directory is read and updated. Defaults to this script's workspace root.
.PARAMETER Apply
Writes the updates; without it the run only reports. Appy is an alias.
.PARAMETER Include
Wildcards over owner/repository selecting the actions to update, for example actions/*.
.PARAMETER Exclude
Wildcards over owner/repository excluded after Include.
.PARAMETER ReleaseCatalogPath
JSON catalog {"owner/repository": {"Tag": "v1.2.3", "Sha": "<commit>"}} used instead of the GitHub API.
.PARAMETER RefreshWorkflowReceipts
Also moves each written workflow's documentation receipt (docs/ci/github/script-<name>.md) to its new hash,
only when the receipt recorded the file before this pin-only edit.
.EXAMPLE
./scripts/Update-GitHubActions.ps1
Lists every action reference with its latest release, without writing.
.EXAMPLE
./scripts/Update-GitHubActions.ps1 -Apply -WhatIf
Shows each file that -Apply would write.
.EXAMPLE
./scripts/Update-GitHubActions.ps1 -Apply -RefreshWorkflowReceipts -Confirm
Asks once for each changed workflow and its receipt.
.EXAMPLE
./scripts/Update-GitHubActions.ps1 -Apply -Include 'actions/*' -Exclude 'actions/cache'
Updates the actions/* references except actions/cache.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [Alias('Appy')][switch]$Apply,
    [string[]]$Include=@('*'),
    [string[]]$Exclude=@(),
    [string]$ReleaseCatalogPath,
    [switch]$RefreshWorkflowReceipts
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Update-GitHubActions.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptUpdateGitHubActions @PSBoundParameters
