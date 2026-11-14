#requires -Version 7.6
<#
.SYNOPSIS
Shelves pending work, fast-forwards the base branch and restores the shelf on a new work branch.
.PARAMETER Branch
New feature or fix branch; an existing branch is never reset.
.PARAMETER WorkspaceRoot
Checkout containing the pending work and configured remote.
.PARAMETER BaseBranch
Existing local branch to update using a fast-forward-only pull.
.PARAMETER Remote
Configured remote supplying the base branch, without fetching tags.
.PARAMETER ShelfName
Optional message identifying the retained Git stash.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^(fix|feature)/[A-Za-z0-9._/-]+$')][string]$Branch,
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [ValidatePattern('^[A-Za-z0-9._/-]+$')][string]$BaseBranch='develop',
    [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Remote='origin',
    [string]$ShelfName
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Start-QuietWorkBranch.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptStartQuietWorkBranch @PSBoundParameters
