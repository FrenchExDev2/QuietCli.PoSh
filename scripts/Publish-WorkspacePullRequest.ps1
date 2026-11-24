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
.PARAMETER ScriptMutation
Check mutation testing for the repository script catalogue.
.PARAMETER ScriptMutationNoInputCache
Check the option to rerun selected repository script mutants without reading the cache.
.PARAMETER RunProfile
Select one or more companions declared in build/companions.yaml for -Mutation and -Profiling.
.PARAMETER Mutation
Select the supported mutation campaign of every companion in RunProfile.
.PARAMETER RunProfileMutation
Select mutation campaigns directly for one or more companions with a declared mutation campaign.
.PARAMETER Profiling
Profile the PowerShell tests of the selected companions. Defaults on for -RunProfile with -Mutation; use -Profiling:$false for mutation only.
.PARAMETER Performance
Measure an unprofiled test run for the companions selected by -RunProfile.
.PARAMETER Parallel
Run mutation matrices and workers in parallel by default. Pass -Parallel:$false to run each matrix and worker sequentially.
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
    [switch]$ScriptMutation,
    [switch]$ScriptMutationNoInputCache,
    [AllowEmptyCollection()][string[]]$RunProfile,
    [switch]$Mutation,
    [AllowEmptyCollection()][string[]]$RunProfileMutation,
    [switch]$Profiling,
    [switch]$Performance,
    [switch]$Parallel,
    [switch]$ReadyToRun,
    [switch]$Preview,
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [ValidateRange(0,600)][int]$DiscoverySeconds=120
)
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,'Commit, push, publish the pull request, switch to develop and monitor CI')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Merge-PullRequest.psm1')) -DisableNameChecking -ErrorAction Stop
$options=@{}
$checkboxes=@{ScriptMutation='script-mutation';ScriptMutationNoInputCache='script-mutation-no-input-cache';ReadyToRun='readytorun';Preview='preview'}
foreach($name in $checkboxes.Keys){
    if($PSBoundParameters.ContainsKey($name)){$options[$checkboxes[$name]]=[bool]$PSBoundParameters[$name]}
}
$catalogue=$null
if($PSBoundParameters.ContainsKey('RunProfile') -or $PSBoundParameters.ContainsKey('RunProfileMutation')){
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiCompanions.psm1')) -DisableNameChecking -ErrorAction Stop
    $catalogue=Read-QuietCiCompanions $WorkspaceRoot
    $RunProfile=@(Get-QuietCompanions -Configuration $catalogue -Name @($RunProfile|Where-Object {$_}))
    $RunProfileMutation=@(Get-QuietCompanions -Configuration $catalogue -Name @($RunProfileMutation|Where-Object {$_}) -Capability Mutation)
    if($Mutation){$null=Get-QuietCompanions -Configuration $catalogue -Name $RunProfile -Capability Mutation}
}
if($PSBoundParameters.ContainsKey('RunProfileMutation')){
    foreach($companion in $catalogue.Companions.Values|Where-Object Mutation){
        $options['run-profile-mutation-'+$companion.Name.ToLowerInvariant()]=$companion.Name -in $RunProfileMutation
    }
}
if(($Mutation -or $Profiling) -and !$RunProfile.Count -and !$RunProfileMutation.Count){
    throw 'WorkspacePullRequestRunProfileRequired: choose at least one companion for mutation or profiling.'
}
if($Performance -and !$RunProfile.Count){throw 'WorkspacePullRequestRunProfileRequired: choose companions for performance.'}
foreach($companion in $RunProfile){
    $id=$companion.ToLowerInvariant()
    if($PSBoundParameters.ContainsKey('Mutation')){$options['run-profile-mutation-'+$id]=[bool]$Mutation}
    if($PSBoundParameters.ContainsKey('Performance')){$options['performance-'+$id]=[bool]$Performance}
    if($PSBoundParameters.ContainsKey('Profiling') -or $Mutation){$options['profiling-'+$id]=if($PSBoundParameters.ContainsKey('Profiling')){[bool]$Profiling}else{$true}}
}
if(!$RunProfile.Count -and $PSBoundParameters.ContainsKey('Profiling')){
    foreach($companion in $RunProfileMutation){$options['profiling-'+$companion.ToLowerInvariant()]=[bool]$Profiling}
}
if($PSBoundParameters.ContainsKey('Parallel')){$options['mutation-serial']=!$Parallel}
Invoke-QuietPublishPullRequest -WorkspaceRoot $WorkspaceRoot -Message $Message -Body $Body -Title $Title -Footer $Footer -Options $options -DiscoverySeconds $DiscoverySeconds -Confirm:$false
