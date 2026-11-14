#requires -Version 7.6
<#
.SYNOPSIS
Removes all local and GitHub tags from one verified checkout, preserving a metadata receipt.
.PARAMETER WorkspaceRoot
QuietCli checkout whose local tag references are selected.
.PARAMETER Repository
GitHub owner/repository required to match the configured remote.
.PARAMETER Remote
Configured remote used only to verify the repository identity.
.PARAMETER PlanOnly
Lists tag metadata without deleting references or writing a receipt.
.PARAMETER ReportPath
New UTF-8 JSON receipt containing the original reference identities and deletion progress.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository='FrenchExDev2/QuietCli.PoSh',
    [ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$Remote='origin',
    [switch]$PlanOnly,
    [string]$ReportPath
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Remove-QuietTags.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptRemoveQuietTags @PSBoundParameters
