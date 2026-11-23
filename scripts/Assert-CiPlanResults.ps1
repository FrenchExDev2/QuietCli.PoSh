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
$evidence=$null
if($env:GITHUB_EVENT_NAME -ceq 'pull_request'){
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/PullRequestCi.psm1')) -DisableNameChecking -ErrorAction Stop
    $planned=$needs.plan.outputs
    $evidence=@{
        Number=[int]$planned.pr_number; Head=$planned.pr_head; Base=$planned.pr_base; Revision=$env:GITHUB_SHA
        Options=$planned.pr_ci_options | ConvertFrom-Json -NoEnumerate
    }
    $current=Read-QuietPullRequestCiSnapshot (Split-Path $PSScriptRoot -Parent) $env:GITHUB_REPOSITORY $evidence.Number
    if(!(Test-QuietPullRequestCiSelection $current $evidence)){throw 'PullRequestCiCheckpointChanged'}
}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
Write-WorkspaceJson ([IO.Path]::Combine($OutputDirectory,'receipt.json')) @{Revision=$env:GITHUB_SHA;RunId=$env:GITHUB_RUN_ID;RunAttempt=$env:GITHUB_RUN_ATTEMPT;PullRequest=$evidence;Result=$receipt;PublicationQualified=$false}
