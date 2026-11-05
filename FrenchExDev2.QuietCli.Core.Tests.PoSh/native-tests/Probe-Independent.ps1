# Objective: Prove native qualification works before any product engine or module is built.
#requires -Version 7.6
<#
.SYNOPSIS
Runs mandatory C validation in a source-only stage with forbidden AI commands trapped.
.PARAMETER WorkspaceRoot
Minimal staged source tree, without product assemblies or module manifests.
.PARAMETER RunDirectory
Owned report directory.
.PARAMETER ExpectedRuntimeIdentifier
Required native Linux architecture and libc.
#>
[CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory,[Parameter(Mandatory)][string]$ExpectedRuntimeIdentifier)
$ErrorActionPreference='Stop'
. (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
[void][IO.Directory]::CreateDirectory($RunDirectory)
$productFiles=@(Get-ChildItem $WorkspaceRoot -Recurse -File|Where-Object Extension -In @('.dll','.csproj','.psd1','.psm1'))
if($productFiles.Count){throw 'IndependentNativeProbeContainsProductBuildsOrModules'}
Remove-Item Alias:pump,Alias:quiet -ErrorAction SilentlyContinue
$script:forbiddenCalls=0
function pump {
    <#
    .SYNOPSIS
    Rejects any accidental AI command in native CI.
    #>
    $script:forbiddenCalls++;throw 'AICommandInvokedDuringCI'
}
function quiet {
    <#
    .SYNOPSIS
    Rejects any accidental AI command in native CI.
    #>
    $script:forbiddenCalls++;throw 'AICommandInvokedDuringCI'
}
$loaded=@(Get-Module -Name 'FrenchExDev2.QuietCli.*')
if($loaded.Count){throw 'ProductModuleLoadedBeforeIndependentNativeProbe'}
& (Join-Path $PSScriptRoot 'Invoke-PtyMutation.ps1') -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -CompilerPath gcc -RequireFuzz -ExpectedRuntimeIdentifier $ExpectedRuntimeIdentifier -Worker
$summary=Get-Content (Join-Path $RunDirectory 'summary.json') -Raw -Encoding utf8|ConvertFrom-Json
. (Join-Path $WorkspaceRoot 'scripts/Assert-PtyQualification.ps1')
Assert-PtyQualification $summary
$loaded=@(Get-Module -Name 'FrenchExDev2.QuietCli.*')
Write-WorkspaceJson (Join-Path $RunDirectory 'independence.json') @{ProductBuildFiles=$productFiles.Count;LoadedProductModules=$loaded.Count;ForbiddenAICommandCalls=$script:forbiddenCalls;Runtime=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier}
if($loaded.Count -or $script:forbiddenCalls){throw 'NativeQualificationUsedProductRuntime'}
