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
.PARAMETER CompanionPackageDirectory
Optional independently validated Git package to install alongside the Core dependency.
#>
[CmdletBinding()]param([string]$PackageDirectory,[string]$InstallationDirectory,[switch]$ExistingInstallation,[string]$CompanionPackageDirectory)
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
if($CompanionPackageDirectory){
    $companionPlan=Get-Content (Join-Path $CompanionPackageDirectory package-set.json) -Raw -Encoding utf8|ConvertFrom-Json
    foreach($package in $companionPlan.Packages){
        $destination=Join-Path (Join-Path $root $package.Module) $companionPlan.BaseVersion
        [void][IO.Directory]::CreateDirectory($destination)
        [void][IO.Compression.ZipFile]::ExtractToDirectoryAsync((Join-Path $CompanionPackageDirectory $package.File),$destination,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }
}
$env:PSModulePath=$root+[IO.Path]::PathSeparator+(Join-Path $PSHOME Modules)
Import-Module (Join-Path $PSScriptRoot '../../scripts/lib/TestConfiguration.psm1') -DisableNameChecking -ErrorAction Stop
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
    if($core.Name -cne 'FrenchExDev2.QuietCli.Core.PoSh' -or [FrenchExDev2.QuietCli.QuietSession]::ModuleName -cne $core.Name){throw 'InstalledGalleryModuleNameMismatch'}
    $generated=quiet -Script (Join-Path $root 'generated-call.ps1') -AsObject -Data @{Markers=0} -Output {
        param($event,$runtime)
        if($event.Stream -eq 'stdout' -and $event.Text.Trim() -ceq 'generated-package-ready'){$runtime.Data.Markers++}
    } -Complete {param($runtime)$runtime.Data} -FilePath (Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})) -ArgumentList @('-NoProfile','-Command',"[Console]::WriteLine('generated-package-ready')")
    $generatedText=[IO.File]::ReadAllTextAsync($generated.FullName,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
    if(!$generatedText.Contains($core.Name+'\Invoke-QuietCli') -or $generatedText.Contains('QuietCli\Invoke-QuietCli')){throw 'InstalledGeneratedScriptUsesWrongIdentity'}
    $generatedResult=& $generated.FullName
    if($generatedResult.Outcome -cne 'Success' -or $generatedResult.Data.Markers -ne 1){throw 'InstalledGeneratedScriptFailed'}
    $companion=New-QuietModule -Name Package.Sample -Binary package-fixture -OutputPath (Join-Path $root 'generated-modules')
    $companionManifest=Import-PowerShellDataFile (Join-Path $companion.Module 'Package.Sample.psd1')
    if($companionManifest.RequiredModules.Count -ne 1 -or $companionManifest.RequiredModules[0].ModuleName -cne $core.Name){throw 'InstalledScaffoldUsesWrongDependency'}
    Import-Module (Join-Path $companion.Module 'Package.Sample.psd1') -ErrorAction Stop
    Remove-Module Package.Sample -ErrorAction Stop
    $identity=Get-QuietEngine
    $actual=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier
    $expectedBuild=$actual
    if($identity.Mode -eq 'InProcess'){
        $base=if([Environment]::Version.Major -ge 11){'lib/engine'}else{'lib/inprocess'}
        $receipt=Get-Content -LiteralPath (Join-Path $core.ModuleBase ($base+'/build-manifest.json')) -Encoding utf8 -Raw|ConvertFrom-Json
        $slots=if($receipt.PSObject.Properties['ReadyToRunTargets']){@($receipt.ReadyToRunTargets)}else{@()}
        $expectedBuild=if($actual -cin $slots){$actual}else{'portable'}
    }
    if($identity.Engine.RuntimeIdentifier -cne $actual -or $identity.Engine.BuildRuntimeIdentifier -cne $expectedBuild){throw 'InstalledGalleryRuntimeMismatch'}
    $packageVersion=$core.Version.ToString()
    if($core.PrivateData.PSData.ContainsKey('Prerelease') -and $core.PrivateData.PSData.Prerelease){$packageVersion+='-'+$core.PrivateData.PSData.Prerelease}
    $gitLoaded=$false;$gitExecution=$null
    if($CompanionPackageDirectory){
        Import-Module FrenchExDev2.QuietCli.Git.PoSh -ErrorAction Stop
        $git=Get-Module FrenchExDev2.QuietCli.Git.PoSh
        if(!$git.Path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)){throw 'GitLoadedFromSourcesInsteadOfPackage'}
        $repository=Join-Path $root 'git-fixture';[void][IO.Directory]::CreateDirectory($repository)
        $initialized=quiet -AsObject -WorkingDirectory $repository -Output {param($e,$n)} -Complete {param($n)$n.Data} -FilePath git -ArgumentList @('init','--quiet')
        if($initialized.Outcome -cne 'Success'){throw 'InstalledGitFixtureInitFailed'}
        $gitResult=quiet -AsObject -WorkingDirectory $repository -FilePath git -ArgumentList @('status','--porcelain=v2','--branch','-z')
        if($gitResult.Outcome -cne 'Success' -or !$gitResult.Completeness.Source -or !$gitResult.Completeness.Analysis -or $null -eq $gitResult.Data){throw 'InstalledGitHandlerFailed'}
        $gitLoaded=$true;$gitExecution=$gitResult.Outcome
    }
    @{Installed=$true;ModuleName=$core.Name;CoreLoadedFromPackage=$true;GitModuleLoaded=$gitLoaded;GitNativeExecution=$gitExecution;GeneratedScript=$true;ScaffoldDependency=$companionManifest.RequiredModules[0].ModuleName;RuntimeIdentifier=$identity.Engine.RuntimeIdentifier;Version=$core.Version.ToString();PackageVersion=$packageVersion;NativeExecution=$execution.Outcome}|ConvertTo-Json -Compress
}finally{Stop-QuietEngine}
