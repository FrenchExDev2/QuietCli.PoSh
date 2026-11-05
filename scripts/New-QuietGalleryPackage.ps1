# Objectif : Préparer deux paquets PowerShell Gallery installables avec les six moteurs compilés embarqués.
#requires -Version 7.6
<#
.SYNOPSIS
Creates real nupkg packages for Core and Git without contacting or publishing to a repository.
.PARAMETER WorkspaceRoot
QuietCli2 workspace.
.PARAMETER OutputDirectory
New owned directory for package files and a hashed publication plan.
.PARAMETER Version
Optional required version; both manifests must match it.
#>
[CmdletBinding()]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][string]$OutputDirectory,[string]$Version)
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot 'Common.ps1');. (Join-Path $PSScriptRoot 'Gallery.ps1')
$WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path);$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory,$PWD.Path)
if(Test-Path -LiteralPath $OutputDirectory){throw 'GalleryOutputAlreadyExists'}
$names=@('FrenchExDev2.QuietCli.Core.PoSh','FrenchExDev2.QuietCli.Git.PoSh')
$manifests=@(foreach($name in $names){Import-PowerShellDataFile (Join-Path (Join-Path $WorkspaceRoot $name) ($name+'.psd1'))})
$release=[string]$manifests[0].ModuleVersion
if($release -notmatch '^\d+\.\d+\.\d+$' -or [string]$manifests[1].ModuleVersion -cne $release -or ($Version -and $Version -cne $release)){throw 'GalleryReleaseVersionMismatch'}
$dependency=@($manifests[1].RequiredModules|Where-Object ModuleName -CEQ $names[0])
if($dependency.Count -ne 1){throw 'GalleryCoreDependencyMissing'}
$stage=Join-Path $OutputDirectory workspace-packages
$null=& (Join-Path $PSScriptRoot 'New-WorkspacePackage.ps1') -WorkspaceRoot $WorkspaceRoot -OutputDirectory $stage
$modulePath=$env:PSModulePath;$packages=[Collections.Generic.List[object]]::new()
try{
    $env:PSModulePath=$stage+[IO.Path]::PathSeparator+$modulePath
    foreach($name in $names){
        $module=Join-Path $stage $name
        $compressed=Compress-PSResource -Path $module -DestinationPath $OutputDirectory -PassThru -ErrorAction Stop
        $path=if($compressed -is [IO.FileInfo]){$compressed.FullName}else{[string]$compressed}
        if(!(Test-Path -LiteralPath $path)){$path=Join-Path $OutputDirectory ($name+'.'+$release+'.nupkg')}
        $packages.Add(@{Module=$name;File=[IO.Path]::GetFileName($path);SHA256=(Get-FileHash $path -Algorithm SHA256).Hash;Bytes=(Get-Item $path).Length})
    }
}finally{$env:PSModulePath=$modulePath}
$plan=@{SchemaVersion=1;Version=$release;CoreDependencyVersion=[string]$dependency[0].ModuleVersion;Repository='https://www.powershellgallery.com/api/v2';Targets=@(Get-QuietRuntimeTargets $WorkspaceRoot);Packages=$packages.ToArray();SourceLockSHA256=(Get-FileHash (Join-Path $WorkspaceRoot repositories.lock.json) -Algorithm SHA256).Hash;Published=$false}
Write-WorkspaceJson (Join-Path $OutputDirectory package-set.json) $plan
$verified=Test-QuietGalleryPackageSet $OutputDirectory -Version $release
[pscustomobject]@{State='Prepared';Version=$verified.Version;Packages=$verified.Packages;Targets=$verified.Targets.Rid;Published=$false}
