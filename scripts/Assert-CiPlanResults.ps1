#requires -Version 7.6
<#
.SYNOPSIS
Checks workflow results against the selected plan and saves a scoped receipt.
.PARAMETER NeedsJson
Actual GitHub needs JSON.
.PARAMETER OutputDirectory
Owned receipt directory.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$NeedsJson,[string]$OutputDirectory='./artifacts/ci-plan-results')
if(!$PSCmdlet.ShouldProcess($OutputDirectory,'Validate and save selected CI results')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiPlanResults.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/WorkspaceJson.psm1')) -DisableNameChecking -ErrorAction Stop
$needs=$NeedsJson|ConvertFrom-Json -AsHashtable
$receipt=Assert-QuietCiPlanResults -Needs $needs
[void][IO.Directory]::CreateDirectory($OutputDirectory)
Write-WorkspaceJson ([IO.Path]::Combine($OutputDirectory,'receipt.json')) @{Revision=$env:GITHUB_SHA;RunId=$env:GITHUB_RUN_ID;RunAttempt=$env:GITHUB_RUN_ATTEMPT;Result=$receipt;PublicationQualified=$false}
