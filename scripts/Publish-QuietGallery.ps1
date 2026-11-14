#requires -Version 7.6
<#
.SYNOPSIS
Publishes a prepared release once, with version and destination checks and no automatic retry.
.PARAMETER PackageDirectory
Prepared package-set.json and its unchanged selected business-module nupkg.
.PARAMETER Version
Required exact tag or manually requested version.
.PARAMETER ValidateOnly
Performs local validation without using a key or contacting PSGallery.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]param([Parameter(Mandatory)][string]$PackageDirectory,[Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+(?:-[A-Za-z][A-Za-z0-9-]*)?$')][string]$Version,[switch]$ValidateOnly)
$ErrorActionPreference='Stop';Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop;Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Gallery.psm1')) -DisableNameChecking
$directory=[IO.Path]::GetFullPath($PackageDirectory,$PWD.Path)
$plan=Test-QuietGalleryPackageSet $directory -Version $Version
if($ValidateOnly){[pscustomobject]@{State='Validated';Version=$Version;Modules=$plan.Packages.Module;Published=$false};return}
if($WhatIfPreference){foreach($name in $plan.Packages.Module){$null=$PSCmdlet.ShouldProcess(('PSGallery/'+$name+'/'+$Version),'Publish verified PowerShell module')};return}
if([string]::IsNullOrWhiteSpace($env:PSGALLERY_API_KEY)){throw 'PSGALLERY_API_KEY is required in the environment; never pass it on the command line.'}
$repository=Get-PSResourceRepository -Name PSGallery -ErrorAction Stop
if($repository.Uri.AbsoluteUri.TrimEnd('/') -cne 'https://www.powershellgallery.com/api/v2'){throw 'PSGalleryRepositoryUriMismatch'}
foreach($package in $plan.Packages){if(Get-QuietGalleryRemoteIdentity $package.Module $Version){throw ('GalleryVersionAlreadyExists: '+$package.Module+' '+$Version+'; no overwrite or automatic retry is performed.')}}
$receipt=@{SchemaVersion=1;Version=$Version;Repository='PSGallery';State='Prepared';Modules=@();StartedUtc=[DateTimeOffset]::UtcNow.ToString('o')}
$receiptPath=[IO.Path]::Combine($directory,'publication.json')
try{
    foreach($name in $plan.Packages.Module){
        $package=$plan.Packages|Where-Object Module -CEQ $name
        if($PSCmdlet.ShouldProcess(('PSGallery/'+$name+'/'+$Version),'Publish verified PowerShell module')){
            $receipt.State='Publishing';$receipt.PendingModule=$name;Write-WorkspaceJson $receiptPath $receipt
            $publishOptions=@{NupkgPath=([IO.Path]::Combine($directory,$package.File));Repository='PSGallery';ApiKey=$env:PSGALLERY_API_KEY;ErrorAction='Stop'}
            Publish-PSResource @publishOptions
            $receipt.Modules+=@(@{Module=$name;SHA256=$package.SHA256;State='Published'})
            $receipt.PendingModule=$null
            Write-WorkspaceJson $receiptPath $receipt
        }
    }
    $receipt.State=if($receipt.Modules.Count -eq 1){'Published'}else{'NotPublished'}
}catch{
    $receipt.State='Failed';$receipt.ErrorCode=$_.Exception.GetType().Name;$receipt.EffectStatus=if($receipt.PendingModule){'Unknown'}else{'Known'}
    Write-WorkspaceJson $receiptPath $receipt
    throw 'Gallery publication failed; see the receipt for modules already published. Do not retry a partial release blindly.'
}finally{$receipt.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o');Write-WorkspaceJson $receiptPath $receipt}
[pscustomobject]@{State=$receipt.State;Version=$Version;Modules=$receipt.Modules;Receipt=$receiptPath}
