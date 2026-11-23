#requires -Version 7.6
<#
.SYNOPSIS
Runs a profile-validated build, grouped smoke or full workspace-component qualification.
.PARAMETER WorkspaceRoot
Selected checkout.
.PARAMETER Suite
Companion name, or SmokeBatch with explicit SuitesJson.
.PARAMETER QualificationMode
Full, smoke or build scope. Smokes never emit full qualification receipts.
.PARAMETER SuitesJson
Explicit array of companions for a grouped smoke.
.PARAMETER SolutionPath
Optional caller solution path validated against the catalogue.
.PARAMETER SourcePath
Optional caller source path.
.PARAMETER TestPath
Optional caller test path.
.PARAMETER RunDirectory
Optional owned report destination.
.PARAMETER ValidateOnly
Checks the mode and declared paths without building or running tests.
.PARAMETER Campaign
Selects normal qualification, mutation, profiling, or both mutation and profiling in the same pass.
.PARAMETER Parallel
Enables the normal worker budget. False restricts the requested campaign to one worker.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][string]$Suite,[ValidateSet('full','smoke','build')][string]$QualificationMode='full',[string]$SuitesJson='[]',[string]$SolutionPath,[string]$SourcePath,[string]$TestPath,[string]$RunDirectory,[switch]$ValidateOnly,[ValidateSet('qualification','mutation','profiling','profiled-mutation')][string]$Campaign='qualification',[switch]$Parallel)
if(!$PSCmdlet.ShouldProcess($Suite,('Run component '+$QualificationMode))){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CompanionWorkflows.psm1')) -DisableNameChecking -ErrorAction Stop
$suites=if($Suite -ceq 'SmokeBatch'){
    if($QualificationMode -cne 'smoke'){throw 'SmokeBatchRequiresSmokeMode'}
    $value=ConvertFrom-Json -InputObject $SuitesJson -NoEnumerate
    if($value -isnot [array] -or !$value.Count){throw 'SmokeBatchMustBeNonemptyArray'}
    @($value)
}else{@($Suite)}
$mutation=$null
$profileEnabled=$Campaign -cin @('profiling','profiled-mutation')
$mutate=$Campaign -cin @('mutation','profiled-mutation')
if($Campaign -cne 'qualification'){
    if($QualificationMode -cne 'full' -or $suites.Count -ne 1){throw 'ComponentCampaignRequiresOneFullSuite'}
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiCompanions.psm1')) -DisableNameChecking -ErrorAction Stop
    $catalogue=Read-QuietCiCompanions $WorkspaceRoot
    $capability=if($mutate){'Mutation'}else{'Companion'}
    $Suite=Get-QuietCompanions -Configuration $catalogue -Name $Suite -Capability $capability
    $suites=@($Suite)
    if($mutate){$mutation=$catalogue.Companions[$Suite].Mutation}
}
foreach($selected in $suites){
    Assert-QuietCompanionProfile -WorkspaceRoot $WorkspaceRoot -Suite $selected -SolutionPath $SolutionPath -SourcePath $SourcePath -TestPath $TestPath
}
if($ValidateOnly){return}
$entry=if($env:GITHUB_ACTIONS -ceq 'true'){'Invoke-GitHubCi.ps1'}else{'Invoke-WorkspaceCi.ps1'}
$launch=[IO.Path]::Combine($PSScriptRoot,$entry)
$budget=[Math]::Min(4,[Math]::Max(1,[Environment]::ProcessorCount))
if($PSBoundParameters.ContainsKey('Parallel') -and !$Parallel){$budget=1}
$mutationSuite=if($mutation){$mutation['suite']}
foreach($selected in $suites|Where-Object {!$mutationSuite}){
    $parameters=@{WorkspaceRoot=$WorkspaceRoot;Suite=$selected;ReuseVerifiedBuild=$true}
    if($selected -cne 'Distribution'){$parameters.RuntimeIdentifier=@([Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier)}
    & ([IO.Path]::Combine($PSScriptRoot,'Build-Workspace.ps1')) @parameters
}
if($QualificationMode -ceq 'build'){return}
if($QualificationMode -ceq 'smoke'){
    $parameters=@{WorkspaceRoot=$WorkspaceRoot;Suite='CompanionSmoke';SmokeSuitesJson=(ConvertTo-Json -InputObject @($suites) -Compress);SkipBuild=$true;Headless=($env:GITHUB_ACTIONS -ceq 'true')}
    if($RunDirectory){$parameters.RunDirectory=$RunDirectory}
    & ([IO.Path]::Combine($PSScriptRoot,'Invoke-WorkspaceCi.ps1')) @parameters
}else{
    $testSuite=if($mutationSuite){$mutationSuite}else{$Suite}
    $parameters=@{WorkspaceRoot=$WorkspaceRoot;Suite=$testSuite;SkipBuild=$true;SkipTty=$true}
    if($RunDirectory){$parameters.RunDirectory=$RunDirectory}
    if($Campaign -cne 'qualification'){$parameters.MaxConcurrency=$budget}
    $environment=@{}
    if($mutation -and $mutation['environment']){foreach($key in $mutation['environment'].Keys){$environment[$key]='1'}}
    if($mutate -and $RunDirectory){$environment.QUIETCLI_CAMPAIGN_REPORT_ROOT=[IO.Path]::Combine([IO.Path]::GetFullPath($RunDirectory,$PWD.Path),'mutation-evidence')}
    if($profileEnabled){$environment.QUIETCLI_PROFILE_COMPANION=$testSuite}
    $previous=@{}
    try {
        foreach($key in $environment.Keys){
            $previous[$key]=[Environment]::GetEnvironmentVariable($key)
            [Environment]::SetEnvironmentVariable($key,$environment[$key])
        }
        & $launch @parameters
    } finally {
        foreach($key in $previous.Keys){[Environment]::SetEnvironmentVariable($key,$previous[$key])}
    }
}
