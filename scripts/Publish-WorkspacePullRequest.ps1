#requires -Version 7.6
<#
.SYNOPSIS
Commits and publishes a work branch, then monitors its pull request from develop.
.PARAMETER Message
Commit message. Its first line supplies the default title for a new pull request.
.PARAMETER Body
Pull request description in Markdown, with or without the standard checklist.
.PARAMETER Title
Optional title for a new pull request.
.PARAMETER Footer
Optional Markdown appended below the description and checklist.
.PARAMETER Mutation
Check Run extended mutation testing.
.PARAMETER ReadyToRun
Check Compare IL and ReadyToRun cold-start performance.
.PARAMETER Preview
Check Add PowerShell Preview hosts to the Core matrix.
.PARAMETER WorkspaceRoot
Checkout containing the active work branch and local develop.
.PARAMETER DiscoverySeconds
Maximum number of seconds to wait for GitHub to register the pull request workflow.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][ValidateNotNullOrWhiteSpace()][string]$Message,
    [Parameter(Mandatory)][ValidateNotNullOrWhiteSpace()][string]$Body,
    [ValidateNotNullOrWhiteSpace()][string]$Title,
    [string]$Footer,
    [switch]$Mutation,
    [switch]$ReadyToRun,
    [switch]$Preview,
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [ValidateRange(0,600)][int]$DiscoverySeconds=120
)
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,'Commit, push, publish the pull request, switch to develop and monitor CI')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Merge-PullRequest.psm1')) -DisableNameChecking -ErrorAction Stop
$options=@{}
foreach($name in 'Mutation','ReadyToRun','Preview'){
    if($PSBoundParameters.ContainsKey($name)){$options[$name.ToLowerInvariant()]=[bool]$PSBoundParameters[$name]}
}
Invoke-QuietPublishPullRequest -WorkspaceRoot $WorkspaceRoot -Message $Message -Body $Body -Title $Title -Footer $Footer -Options $options -DiscoverySeconds $DiscoverySeconds -Confirm:$false
