# Objective: Prepare the public Core nupkg with its six verified embedded engine distributions.
#requires -Version 7.6
<#
.SYNOPSIS
Creates the public Core nupkg without contacting or publishing to a repository.
.PARAMETER WorkspaceRoot
QuietCli2 workspace.
.PARAMETER OutputDirectory
New owned directory for package files and a hashed publication plan.
.PARAMETER Version
Optional expected package version; source manifests must match unless a staged Prerelease override is selected.
.PARAMETER Prerelease
Optional alphanumeric label applied only to staged manifests. Source versions, GUIDs and files stay unchanged.
#>
[CmdletBinding()]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][string]$OutputDirectory,[string]$Version,[string]$Prerelease)
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot 'Common.ps1');. (Join-Path $PSScriptRoot 'Gallery.ps1')
$WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path);$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory,$PWD.Path)
if(Test-Path -LiteralPath $OutputDirectory){throw 'GalleryOutputAlreadyExists'}
$names=@('FrenchExDev2.QuietCli.Core.PoSh')
$manifests=@(foreach($name in $names){Import-PowerShellDataFile (Join-Path (Join-Path $WorkspaceRoot $name) ($name+'.psd1'))})
$release=Get-QuietGalleryModuleVersion $manifests[0]
$sourceVersion=$release
$releaseInfo=Get-QuietGalleryVersion $release
if($PSBoundParameters.ContainsKey('Prerelease')){
    if($Prerelease -cnotmatch '^[A-Za-z][A-Za-z0-9]*\z'){throw 'GalleryPreviewLabelInvalid'}
    $release=$releaseInfo.BaseVersion+'-'+$Prerelease
    $releaseInfo=Get-QuietGalleryVersion $release
}
if($Version -and $Version -cne $release){throw 'GalleryReleaseVersionMismatch'}
$stage=Join-Path $OutputDirectory workspace-packages
$null=& (Join-Path $PSScriptRoot 'New-WorkspacePackage.ps1') -WorkspaceRoot $WorkspaceRoot -OutputDirectory $stage
$modulePath=$env:PSModulePath;$packages=[Collections.Generic.List[object]]::new()
try{
    $env:PSModulePath=$stage+[IO.Path]::PathSeparator+$modulePath
    foreach($name in $names){
        $module=Join-Path $stage $name
        if($PSBoundParameters.ContainsKey('Prerelease')){Set-QuietGalleryStagedPrerelease -Path (Join-Path $module ($name+'.psd1')) -Prerelease $Prerelease}
        $compressed=Compress-PSResource -Path $module -DestinationPath $OutputDirectory -PassThru -ErrorAction Stop
        $path=if($compressed -is [IO.FileInfo]){$compressed.FullName}else{[string]$compressed}
        if(!(Test-Path -LiteralPath $path)){$path=Join-Path $OutputDirectory ($name+'.'+$release+'.nupkg')}
        $packages.Add(@{Module=$name;File=[IO.Path]::GetFileName($path);SHA256=(Get-FileHash $path -Algorithm SHA256).Hash;Bytes=(Get-Item $path).Length})
    }
}finally{$env:PSModulePath=$modulePath}
$plan=@{SchemaVersion=1;Version=$release;SourceVersion=$sourceVersion;BaseVersion=$releaseInfo.BaseVersion;Repository='https://www.powershellgallery.com/api/v2';Targets=@(Get-QuietRuntimeTargets $WorkspaceRoot);Packages=$packages.ToArray();SourceLockSHA256=(Get-FileHash (Join-Path $WorkspaceRoot repositories.lock.json) -Algorithm SHA256).Hash;Published=$false}
Write-WorkspaceJson (Join-Path $OutputDirectory package-set.json) $plan
$verified=Test-QuietGalleryPackageSet $OutputDirectory -Version $release
[pscustomobject]@{State='Prepared';Version=$verified.Version;Packages=$verified.Packages;Targets=$verified.Targets.Rid;Published=$false}
