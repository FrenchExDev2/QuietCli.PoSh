#requires -Version 7.6
<#
.SYNOPSIS
Shelves pending work, fast-forwards the base branch and restores the shelf on a new work branch.
.DESCRIPTION
Creates a fix/, feature/, chore/ or companion/ branch from the freshly pulled delivery branch (develop by default),
never from the current branch, without tracking it. Pending changes follow through a retained stash.
.PARAMETER Branch
New work branch, for example feature/script-tests; an existing branch is never reset.
.PARAMETER Kind
Work branch kind (fix, feature, chore or companion), used with Name instead of Branch.
.PARAMETER Name
Branch name after the kind, for example script-tests.
.PARAMETER WorkspaceRoot
Checkout containing the pending work and configured remote.
.PARAMETER BaseBranch
Existing local delivery branch to update using a fast-forward-only pull; never a work branch.
.PARAMETER Remote
Configured remote supplying the base branch, without fetching tags.
.PARAMETER ShelfName
Optional message identifying the retained Git stash.
.EXAMPLE
./scripts/Start-QuietWorkBranch.ps1 -Kind feature -Name script-tests
.EXAMPLE
./scripts/Start-QuietWorkBranch.ps1 -Branch fix/suite-image-concurrency -WhatIf
#>
[CmdletBinding(SupportsShouldProcess,DefaultParameterSetName='Branch')]
param(
    [Parameter(Mandatory,ParameterSetName='Branch')][string]$Branch,
    [Parameter(Mandatory,ParameterSetName='Kind')][ArgumentCompletions('fix','feature','chore','companion')][string]$Kind,
    [Parameter(Mandatory,ParameterSetName='Kind')][string]$Name,
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [string]$BaseBranch='develop',
    [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Remote='origin',
    [string]$ShelfName
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Start-QuietWorkBranch.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptStartQuietWorkBranch @PSBoundParameters
