#requires -Version 7.6
<#
.SYNOPSIS
Merges a checked workspace pull request and deletes its source branch by default.
.PARAMETER PullRequest
Number of an open pull request targeting develop in the workspace remote.
.PARAMETER WorkspaceRoot
Checkout whose GitHub remote owns the pull request.
.PARAMETER Remote
Configured GitHub remote, origin by default.
.PARAMETER ExpectedHead
Exact pull request head SHA to merge. If omitted, the observed head is pinned.
.PARAMETER NoRebase
Use a merge commit.
.PARAMETER NoBranchDelete
Keep the source branch.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
    [Parameter(Mandatory, Position=0)][ValidateRange(1, [int]::MaxValue)][int]$PullRequest,
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._-]*\z')][string]$Remote='origin',
    [ValidatePattern('\A[a-f0-9]{40}\z')][string]$ExpectedHead,
    [switch]$NoRebase,
    [switch]$NoBranchDelete
)
$method=if($NoRebase){'merge commit'}else{'rebase'}
$branchAction=if($NoBranchDelete){'preserve the source branch'}else{'delete the source branch'}
if(!$PSCmdlet.ShouldProcess("workspace pull request #$PullRequest via $Remote","Merge with $method and $branchAction")){return}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Merge-PullRequest.psm1')) -DisableNameChecking -ErrorAction Stop
$PSBoundParameters.Confirm=$false
Invoke-QuietMergePullRequest @PSBoundParameters
