#requires -Version 7.6
<#
.SYNOPSIS
Lists or removes origin branches whose current tip matches a pull request merged into develop.
.PARAMETER WorkspaceRoot
Checkout with a github.com origin.
.PARAMETER Limit
Maximum merged pull requests to read from GitHub.
.PARAMETER Apply
Requests deletion of eligible branches, subject to confirmation.
.EXAMPLE
./scripts/Remove-QuietMergedOriginBranches.ps1
.EXAMPLE
./scripts/Remove-QuietMergedOriginBranches.ps1 -Apply -Confirm
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$WorkspaceRoot = (Split-Path $PSScriptRoot -Parent),
    [ValidateRange(1, 1000)][int]$Limit = 1000,
    [switch]$Apply
)

Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Remove-QuietMergedOriginBranches.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptRemoveQuietMergedOriginBranches @PSBoundParameters
