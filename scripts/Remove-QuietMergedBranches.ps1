#requires -Version 7.6
<#
.SYNOPSIS
Deletes the local branches whose pull request was merged into develop on GitHub, and lists the branches it keeps.
.DESCRIPTION
A branch is deleted only when its latest merged pull request contains its tip, so squash merges are recognized
and unpushed commits are never lost. Checked-out and protected branches are always kept. Remote branches are
never touched.
.PARAMETER WorkspaceRoot
Checkout whose local branches are cleaned.
.PARAMETER BaseBranch
Branch the pull requests were merged into, develop by default; never deleted.
.PARAMETER Remote
Configured remote whose github.com URL names the repository; <Remote>/<BaseBranch> tells which branches are already in the base.
.PARAMETER Repository
Expected GitHub owner/repository; the remote must point to it. Defaults to the remote's own repository.
.PARAMETER PullRequestsPath
JSON file saved from gh pr list --state merged --json number,headRefName,headRefOid,baseRefName,mergedAt,isCrossRepository,
read instead of calling gh. The remote is then not checked.
.PARAMETER Limit
Maximum number of merged pull requests requested from gh, 1000 by default.
.PARAMETER Protected
Other branch names that are never deleted, develop, main and master by default.
.PARAMETER IncludeContainedInBase
Also deletes branches without a merged pull request whose tip is already in <Remote>/<BaseBranch>.
.PARAMETER PlanOnly
Returns the decisions without deleting anything.
.EXAMPLE
./scripts/Remove-QuietMergedBranches.ps1 -PlanOnly
.EXAMPLE
./scripts/Remove-QuietMergedBranches.ps1 -IncludeContainedInBase
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [string]$BaseBranch='develop',
    [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Remote='origin',
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository,
    [string]$PullRequestsPath,
    [ValidateRange(1,10000)][int]$Limit=1000,
    [AllowEmptyCollection()][string[]]$Protected=@('develop','main','master'),
    [switch]$IncludeContainedInBase,
    [switch]$PlanOnly
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Remove-QuietMergedBranches.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptRemoveQuietMergedBranches @PSBoundParameters
