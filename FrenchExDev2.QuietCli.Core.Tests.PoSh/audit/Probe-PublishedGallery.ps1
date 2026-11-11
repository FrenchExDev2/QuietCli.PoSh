# Objectif : Download public Core from PSGallery and execute the installed engine.
#requires -Version 7.6
<#
.SYNOPSIS
Checks the real public gallery in an owned installation directory; never registers a repository or installs globally.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER RunDirectory
Owned report and installation directory.
.PARAMETER Version
Published Core version to download.
#>
[CmdletBinding()]param([string]$WorkspaceRoot,[string]$RunDirectory,[string]$Version)
$ErrorActionPreference='Stop';. (Join-Path $WorkspaceRoot scripts/Common.ps1)
$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh';Task='Installation réelle PSGallery';Workspace=$WorkspaceRoot;ProjectDirectory=(Join-Path $WorkspaceRoot FrenchExDev2.QuietCli.Core.PoSh);Platform=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;ProcessId=$PID;State='Running';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null;Passed=0;Failed=0;Case='Downloading the public Core package from PSGallery';Error=$null}
$status=Join-Path $RunDirectory status.json;Write-WorkspaceJson $status $state
$proof=$null
try{
    $installation=Join-Path $RunDirectory modules
    [void][IO.Directory]::CreateDirectory($installation)
    $packageName=& (Join-Path $WorkspaceRoot scripts/Get-ModulePackageName.ps1) -Path (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psm1') -RequireManifest
    $saveOptions=@{Name=$packageName;Version=$Version;Repository='PSGallery';Path=$installation;TrustRepository=$true;PassThru=$true;Quiet=$true;ErrorAction='Stop'}
    if($Version.Contains('-')){$saveOptions.Prerelease=$true}
    $resources=@(Save-PSResource @saveOptions)
    $baseVersion=($Version -split '-',2)[0]
    foreach($name in @($packageName)){
        if(!(Test-Path (Join-Path (Join-Path (Join-Path $installation $name) $baseVersion) ($name+'.psd1')))){throw ('GalleryDependencyDownloadMissing: '+$name)}
    }
    $state.Passed=1;$state.Case='Executing only the modules downloaded from PSGallery';Write-WorkspaceJson $status $state
    Import-Module (Join-Path $WorkspaceRoot FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1) -Force
    . (Join-Path $WorkspaceRoot 'scripts/TestConfiguration.ps1')
    Initialize-QuietTestConfiguration -DatabasePath (Join-Path $RunDirectory transport.sqlite)
    $probe=Join-Path $PSScriptRoot Probe-GalleryInstall.ps1
    $r=quiet -AsObject -Role Infrastructure -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} pwsh -NoProfile -File $probe -InstallationDirectory $installation -ExistingInstallation
    if($r.Outcome -ne 'Success' -or !$r.Data.Installed -or !$r.Data.CoreLoadedFromPackage -or $r.Data.GitModuleLoaded -or $r.Data.NativeExecution -cne 'Success'){throw 'PublishedGalleryExecutionFailed'}
    $proof=@{DownloadedFrom='https://www.powershellgallery.com/api/v2';Version=$Version;Resources=@($resources|Select-Object Name,Version);Execution=$r.Data}
    $state.Passed=2;$state.State='Success';$state.Case='Public Core installation and installed engine verified'
}catch{$state.State='Failed';$state.Failed++;$state.Error=$_.Exception.Message}
finally{try{Stop-QuietEngine}catch{};$state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o');Write-WorkspaceJson (Join-Path $RunDirectory summary.json) @{State=$state;Proof=$proof};Write-WorkspaceJson $status $state}
if($state.State -ne 'Success'){exit 1}
