#requires -Version 7.6
<#
.SYNOPSIS
Creates one selected business-module nupkg without contacting or publishing to a repository.
.PARAMETER WorkspaceRoot
QuietCli2 workspace.
.PARAMETER OutputDirectory
New owned directory for package files and a hashed publication plan.
.PARAMETER Version
Optional expected package version; source manifests must match unless a staged Prerelease override is selected.
.PARAMETER Prerelease
Optional alphanumeric label applied only to staged manifests. Source versions, GUIDs and files stay unchanged.
.PARAMETER RequireReadyToRun
Requires verified Release ReadyToRun engines for every packaged RID and CLR before compression.
.PARAMETER Module
Discovered component alias or full package name; Core by default.
#>
[CmdletBinding(SupportsShouldProcess)]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][string]$OutputDirectory,[string]$Version,[string]$Prerelease,[switch]$RequireReadyToRun,[string]$Module='Core')
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: New-QuietGalleryPackage')){return}
$ErrorActionPreference='Stop';Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop;Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Gallery.psm1')) -DisableNameChecking
$WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path);$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory,$PWD.Path)
if(Test-Path -LiteralPath $OutputDirectory){throw 'GalleryOutputAlreadyExists'}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/GalleryRelease.psm1')) -DisableNameChecking
$target=@(Select-QuietGalleryReleaseTargets -WorkspaceRoot $WorkspaceRoot -Module $Module)
if($target.Count -ne 1){throw 'GallerySinglePackageRequired'}
$sourceName=$target[0].Project
$identity=Get-QuietGalleryModuleIdentity ([IO.Path]::Combine($WorkspaceRoot,"$sourceName/$sourceName.psm1"))
$publicName=$identity.Name
$manifest=Import-PowerShellDataFile ([IO.Path]::Combine(([IO.Path]::Combine($WorkspaceRoot,$sourceName)),($sourceName+'.psd1')))
$release=Get-QuietGalleryModuleVersion $manifest
$sourceVersion=$release
$releaseInfo=Get-QuietGalleryVersion $release
if($PSBoundParameters.ContainsKey('Prerelease')){
    if($Prerelease -cnotmatch '^[A-Za-z][A-Za-z0-9]*\z'){throw 'GalleryPreviewLabelInvalid'}
    $release=$releaseInfo.BaseVersion+'-'+$Prerelease
    $releaseInfo=Get-QuietGalleryVersion $release
}
if($Version -and $Version -cne $release){throw 'GalleryReleaseVersionMismatch'}
$stage=[IO.Path]::Combine($OutputDirectory,'workspace-packages')
$corePackage=$target[0].Component -ceq 'Core'
$null=& ([IO.Path]::Combine($PSScriptRoot,'New-WorkspacePackage.ps1')) -WorkspaceRoot $WorkspaceRoot -OutputDirectory $stage -Module $sourceName -RequireReadyToRun:($RequireReadyToRun -and $corePackage)
$publicStage=[IO.Path]::Combine($OutputDirectory,'public-modules')
[void][IO.Directory]::CreateDirectory($publicStage)
Copy-QuietGalleryCoreModule -SourceDirectory ([IO.Path]::Combine($stage,$sourceName)) -ModuleDirectory ([IO.Path]::Combine($publicStage,$publicName))
$modulePath=$env:PSModulePath;$packages=[Collections.Generic.List[object]]::new()
try{
    $env:PSModulePath=$publicStage+[IO.Path]::PathSeparator+$WorkspaceRoot+[IO.Path]::PathSeparator+$modulePath
    foreach($name in @($publicName)){
        $module=[IO.Path]::Combine($publicStage,$name)
        if($PSBoundParameters.ContainsKey('Prerelease')){Set-QuietGalleryStagedPrerelease -Path ([IO.Path]::Combine($module,($name+'.psd1'))) -Prerelease $Prerelease}
        $compressed=Compress-PSResource -Path $module -DestinationPath $OutputDirectory -PassThru -ErrorAction Stop
        $path=if($compressed -is [IO.FileInfo]){$compressed.FullName}else{[string]$compressed}
        if(!(Test-Path -LiteralPath $path)){$path=[IO.Path]::Combine($OutputDirectory,($name+'.'+$release+'.nupkg'))}
        $packages.Add(@{Module=$name;File=[IO.Path]::GetFileName($path);SHA256=(Get-FileHash $path -Algorithm SHA256).Hash;Bytes=(Get-Item $path).Length})
    }
}finally{$env:PSModulePath=$modulePath}
$plan=@{SchemaVersion=1;Module=$publicName;Version=$release;SourceVersion=$sourceVersion;BaseVersion=$releaseInfo.BaseVersion;ReadyToRun=[bool]($RequireReadyToRun -and $corePackage);Repository='https://www.powershellgallery.com/api/v2';Targets=@(if($corePackage){Get-QuietRuntimeTargets $WorkspaceRoot});Packages=$packages.ToArray();SourceLockSHA256=(Get-FileHash ([IO.Path]::Combine($WorkspaceRoot,'repositories.lock.json')) -Algorithm SHA256).Hash;Published=$false}
Write-WorkspaceJson ([IO.Path]::Combine($OutputDirectory,'package-set.json')) $plan
$verified=Test-QuietGalleryPackageSet $OutputDirectory -Version $release
[pscustomobject]@{State='Prepared';Version=$verified.Version;Packages=$verified.Packages;Targets=@($verified.Targets|ForEach-Object {$_.Rid});Published=$false}
