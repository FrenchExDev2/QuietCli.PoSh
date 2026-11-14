#requires -Version 7.6
<#
.SYNOPSIS
Read-only resizing monitor; closes automatically after a saved terminal result.
.PARAMETER RunDirectory
Directory containing status.json and summary.json.
#>
[CmdletBinding()]param([Parameter(Mandatory)][string]$RunDirectory)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Watch-Tests.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptWatchTests @PSBoundParameters
