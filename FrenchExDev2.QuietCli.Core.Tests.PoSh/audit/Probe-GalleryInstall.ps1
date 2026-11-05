# Objectif : Installer les deux nupkg dans un chemin isolé et exécuter leur véritable moteur sans utiliser les sources.
#requires -Version 7.6
<#
.SYNOPSIS
Checks the installed nupkg layout and automatic Core dependency loading in an isolated profile-free child.
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
        $destination=Join-Path (Join-Path $root $package.Module) $plan.Version
        [void][IO.Directory]::CreateDirectory($destination)
        [void][IO.Compression.ZipFile]::ExtractToDirectoryAsync((Join-Path $PackageDirectory $package.File),$destination,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }
}
$env:PSModulePath=$root+[IO.Path]::PathSeparator+(Join-Path $PSHOME Modules)
$env:QUIETCLI2_DATABASE=Join-Path $root measurements.sqlite
Import-Module FrenchExDev2.QuietCli.Git.PoSh -ErrorAction Stop
try{
    $core=Get-Module FrenchExDev2.QuietCli.Core.PoSh;$git=Get-Module FrenchExDev2.QuietCli.Git.PoSh
    if(!$core.Path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal) -or !$git.Path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)){throw 'SourceModuleWasLoadedInsteadOfPackage'}
    $repository=Join-Path $root repository
    $init=quiet -AsObject -Output {param($e,$r)} -FilePath git -ArgumentList @('init','--quiet',$repository)
    if($init.Outcome -ne 'Success'){throw 'GalleryFixtureInitializationFailed'}
    $status=quiet -AsObject -WorkingDirectory $repository git status
    if($status.Outcome -ne 'Success' -or !$status.Completeness.Source -or !$status.Completeness.Analysis){throw 'InstalledGalleryGitFailed'}
    $identity=Get-QuietEngine
    if($identity.Engine.BuildRuntimeIdentifier -cne [Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier){throw 'InstalledGalleryRuntimeMismatch'}
    @{Installed=$true;CoreLoadedFromPackage=$true;GitLoadedFromPackage=$true;RuntimeIdentifier=$identity.Engine.RuntimeIdentifier;Version=$core.Version.ToString();GitStatus=$status.Outcome}|ConvertTo-Json -Compress
}finally{Stop-QuietEngine}
