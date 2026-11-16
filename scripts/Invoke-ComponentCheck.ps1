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
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][string]$Suite,[ValidateSet('full','smoke','build')][string]$QualificationMode='full',[string]$SuitesJson='[]',[string]$SolutionPath,[string]$SourcePath,[string]$TestPath,[string]$RunDirectory,[switch]$ValidateOnly)
if(!$PSCmdlet.ShouldProcess($Suite,('Run component '+$QualificationMode))){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CompanionWorkflows.psm1')) -DisableNameChecking -ErrorAction Stop
$suites=if($Suite -ceq 'SmokeBatch'){
    if($QualificationMode -cne 'smoke'){throw 'SmokeBatchRequiresSmokeMode'}
    $value=ConvertFrom-Json -InputObject $SuitesJson -NoEnumerate
    if($value -isnot [array] -or !$value.Count){throw 'SmokeBatchMustBeNonemptyArray'}
    @($value)
}else{@($Suite)}
foreach($selected in $suites){
    Assert-QuietCompanionProfile -WorkspaceRoot $WorkspaceRoot -Suite $selected -SolutionPath $SolutionPath -SourcePath $SourcePath -TestPath $TestPath
}
if($ValidateOnly){return}
foreach($selected in $suites){
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
    $entry=if($env:GITHUB_ACTIONS -ceq 'true'){'Invoke-GitHubCi.ps1'}else{'Invoke-WorkspaceCi.ps1'}
    $parameters=@{WorkspaceRoot=$WorkspaceRoot;Suite=$Suite;SkipBuild=$true;SkipTty=$true}
    if($RunDirectory){$parameters.RunDirectory=$RunDirectory}
    & ([IO.Path]::Combine($PSScriptRoot,$entry)) @parameters
}
