# Objectif : Exécuter les modules de tests compagnons dans un processus isolé et publier chaque résultat.
#requires -Version 7.6
<#
.SYNOPSIS
Background worker for the companion suites; always persists a terminal report.
.PARAMETER WorkspaceRoot
QuietCli2 workspace root.
.PARAMETER RunDirectory
Private output directory for this run.
.PARAMETER Suite
Core, Git or All.
.PARAMETER ExpectedRuntimeIdentifier
Required native architecture for both the PowerShell host and the separate engine.
#>
[CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory,[ValidateSet('Core','Git','All')][string]$Suite='All',[string]$ExpectedRuntimeIdentifier)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$env:PSModulePath=$WorkspaceRoot+[IO.Path]::PathSeparator+$env:PSModulePath
$env:QUIETCLI2_DATABASE=Join-Path $RunDirectory 'measurements.sqlite'
$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh';Task='Tests compagnons';Workspace=$WorkspaceRoot;ProjectDirectory=(Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh');Platform=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;State='Running';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');ProcessId=$PID;Passed=0;Failed=0;Case='Starting';FinishedUtc=$null;Error=$null}
$statusPath=Join-Path $RunDirectory 'status.json'
Write-WorkspaceJson $statusPath $state
$summaries=[Collections.Generic.List[object]]::new()
$sourceIdentity=$null;$engineIdentity=$null
try{
    if($env:QUIETCLI2_EXPECT_RUNTIME_MAJOR -and [Environment]::Version.Major -ne [int]$env:QUIETCLI2_EXPECT_RUNTIME_MAJOR){throw 'PowerShellRuntimeMajorMismatch'}
    if($env:QUIETCLI2_EXPECT_HOST_VERSION -and $PSVersionTable.PSVersion.ToString() -cne $env:QUIETCLI2_EXPECT_HOST_VERSION){throw 'PowerShellVersionMismatch'}
    if($ExpectedRuntimeIdentifier -and $state.Platform -cne $ExpectedRuntimeIdentifier){throw "HostRuntimeMismatch: expected $ExpectedRuntimeIdentifier, observed $($state.Platform)"}
    $sourceIdentity=Get-QuietWorkspaceIdentity $WorkspaceRoot -IncludeBinaries
    Write-WorkspaceJson (Join-Path $RunDirectory 'source-identity.json') $sourceIdentity
    Import-Module (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1') -Force
    $engineIdentity=Get-QuietEngine
    if($env:QUIETCLI2_EXPECT_ENGINE_MODE -and $engineIdentity.Mode -cne $env:QUIETCLI2_EXPECT_ENGINE_MODE){throw 'EngineHostingModeMismatch'}
    if($env:QUIETCLI2_EXPECT_RUNTIME_MAJOR -and $engineIdentity.Mode -eq 'InProcess'){
        $framework='.NETCoreApp,Version=v'+$env:QUIETCLI2_EXPECT_RUNTIME_MAJOR+'.0'
        if($engineIdentity.Mode -cne 'InProcess' -or $engineIdentity.Engine.ProcessId -ne $PID -or $engineIdentity.Engine.TargetFramework -cne $framework){throw 'IntegratedEngineIdentityMismatch'}
        if($engineIdentity.ProtocolInputBytes -ne 0 -or $engineIdentity.ProtocolOutputBytes -ne 0){throw 'IntegratedEngineUnexpectedPipeTraffic'}
    }
    if($ExpectedRuntimeIdentifier -and $engineIdentity.Engine.RuntimeIdentifier -cne $ExpectedRuntimeIdentifier){throw "EngineRuntimeMismatch: expected $ExpectedRuntimeIdentifier, observed $($engineIdentity.Engine.RuntimeIdentifier)"}
    if($ExpectedRuntimeIdentifier -and $engineIdentity.Mode -ne 'InProcess' -and $engineIdentity.Engine.BuildRuntimeIdentifier -cne $ExpectedRuntimeIdentifier){throw 'EnginePublicationRuntimeMismatch'}
    foreach($selected in $(if($Suite -eq 'All'){@('Core','Git')}else{@($Suite)})){
        $project="FrenchExDev2.QuietCli.$selected.PoSh"
        $state.Project=$project;$state.ProjectDirectory=Join-Path $WorkspaceRoot $project
        Import-Module (Join-Path $WorkspaceRoot "FrenchExDev2.QuietCli.$selected.Tests.PoSh/FrenchExDev2.QuietCli.$selected.Tests.PoSh.psd1") -Force
        $basePassed=$state.Passed;$baseFailed=$state.Failed
        $progress={param($name,$caseState,$passed,$failed)$state.Case=$name;$state.Passed=$basePassed+$passed;$state.Failed=$baseFailed+$failed;Write-WorkspaceJson $statusPath $state}
        $command=Get-Command "Invoke-Quiet$($selected)Tests"
        $summary=& $command -WorkspaceRoot $WorkspaceRoot -OnProgress $progress
        $summaries.Add($summary)
    }
    $state.State=if($state.Failed){'Failed'}else{'Success'}
}catch{$state.State='Crash';$state.Error=$_.ToString();$state.Failed++}
finally{
    if($sourceIdentity){
        try{
            $after=Get-QuietWorkspaceIdentity $WorkspaceRoot -IncludeBinaries
            $drift=@(foreach($before in $sourceIdentity.Projects){$current=@($after.Projects|Where-Object Name -CEQ $before.Name)[0];if($current.SourceSHA256 -cne $before.SourceSHA256){$before.Name}};if($sourceIdentity.Repository.SourceSHA256 -cne $after.Repository.SourceSHA256){'Monorepo'})
            if($drift.Count){$state.State='Failed';$state.Failed++;$state.Case='Sources changed during the run';$state.Error=$drift -join ', '}
            Write-WorkspaceJson (Join-Path $RunDirectory 'source-identity-final.json') $after
            $engineIdentity=Get-QuietEngine
            if($ExpectedRuntimeIdentifier -and $engineIdentity.Engine.RuntimeIdentifier -cne $ExpectedRuntimeIdentifier){throw 'FinalEngineRuntimeMismatch'}
        }catch{$state.State='Failed';$state.Failed++;$state.Error='Build/source identity verification failed: '+$_.Exception.Message}
    }
    try{Stop-QuietEngine}catch{}
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') @{State=$state;Suites=$summaries.ToArray();EngineIdentity=$engineIdentity;HostRuntime=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription;PowerShellVersion=$PSVersionTable.PSVersion.ToString();OSArchitecture=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString();ProcessArchitecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString();OSDescription=[Runtime.InteropServices.RuntimeInformation]::OSDescription;MachineName=[Environment]::MachineName;ExpectedRuntimeIdentifier=$ExpectedRuntimeIdentifier;RunnerImage=$env:ImageOS;RunnerImageVersion=$env:ImageVersion}
    Write-WorkspaceJson $statusPath $state
}
if($state.State -ne 'Success'){exit 1}
