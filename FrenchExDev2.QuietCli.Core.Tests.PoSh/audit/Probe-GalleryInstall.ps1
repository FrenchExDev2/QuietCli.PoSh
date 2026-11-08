# Objective: Install the Core nupkg in an isolated path and execute its embedded engine.
#requires -Version 7.6
<#
.SYNOPSIS
Checks the installed public Core nupkg layout and native execution in an isolated profile-free child.
.PARAMETER PackageDirectory
Already validated package set.
.PARAMETER InstallationDirectory
New owned module directory and native repository fixture.
.PARAMETER ExistingInstallation
Loads modules already downloaded by PSResourceGet, without extracting local archives.
#>
[CmdletBinding()]param([string]$PackageDirectory,[string]$InstallationDirectory,[switch]$ExistingInstallation)
$ErrorActionPreference='Stop'
$utf8=[Text.UTF8Encoding]::new($false);[Console]::InputEncoding=$utf8;[Console]::OutputEncoding=$utf8;$OutputEncoding=$utf8
$root=[IO.Path]::GetFullPath($InstallationDirectory)
if($ExistingInstallation){
    if(!(Test-Path -LiteralPath $root)){throw 'SavedGalleryInstallationMissing'}
}else{
    if(Test-Path -LiteralPath $root){throw 'GalleryInstallFixtureExists'}
    [void][IO.Directory]::CreateDirectory($root)
    $plan=Get-Content (Join-Path $PackageDirectory package-set.json) -Encoding utf8 -Raw|ConvertFrom-Json
    foreach($package in $plan.Packages){
        $destination=Join-Path (Join-Path $root $package.Module) $plan.BaseVersion
        [void][IO.Directory]::CreateDirectory($destination)
        [void][IO.Compression.ZipFile]::ExtractToDirectoryAsync((Join-Path $PackageDirectory $package.File),$destination,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }
}
$env:PSModulePath=$root+[IO.Path]::PathSeparator+(Join-Path $PSHOME Modules)
. (Join-Path $PSScriptRoot '../../scripts/TestConfiguration.ps1')
Initialize-QuietTestConfiguration -DatabasePath (Join-Path $root measurements.sqlite)
Import-Module FrenchExDev2.QuietCli.Core.PoSh -ErrorAction Stop
try{
    $core=Get-Module FrenchExDev2.QuietCli.Core.PoSh
    if(!$core.Path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)){throw 'SourceModuleWasLoadedInsteadOfPackage'}
    if(Get-Module FrenchExDev2.QuietCli.Git.PoSh){throw 'UnpublishedGitModuleLoaded'}
    $execution=quiet -AsObject -RecordDelimiter "`n" -Data @{Markers=0} -Output {
        param($event,$runtime)
        if($event.Stream -eq 'stdout' -and $event.Text.TrimEnd([char[]]"`r`n") -ceq 'quietcli-package-ready'){$runtime.Data.Markers++}
    } -Complete {param($runtime)$runtime.Data} -FilePath (Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})) -ArgumentList @('-NoProfile','-Command',"[Console]::WriteLine('quietcli-package-ready')")
    if($execution.Outcome -ne 'Success' -or !$execution.Completeness.Source -or !$execution.Completeness.Analysis -or $execution.Data.Markers -ne 1){throw 'InstalledGalleryCoreFailed'}
    $identity=Get-QuietEngine
    $actual=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier
    $expectedBuild=if($identity.Mode -eq 'InProcess'){'portable'}else{$actual}
    if($identity.Engine.RuntimeIdentifier -cne $actual -or $identity.Engine.BuildRuntimeIdentifier -cne $expectedBuild){throw 'InstalledGalleryRuntimeMismatch'}
    $packageVersion=$core.Version.ToString()
    if($core.PrivateData.PSData.ContainsKey('Prerelease') -and $core.PrivateData.PSData.Prerelease){$packageVersion+='-'+$core.PrivateData.PSData.Prerelease}
    @{Installed=$true;CoreLoadedFromPackage=$true;GitModuleLoaded=$false;RuntimeIdentifier=$identity.Engine.RuntimeIdentifier;Version=$core.Version.ToString();PackageVersion=$packageVersion;NativeExecution=$execution.Outcome}|ConvertTo-Json -Compress
}finally{Stop-QuietEngine}
