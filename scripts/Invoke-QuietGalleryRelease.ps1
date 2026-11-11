#requires -Version 7.6
<#
.SYNOPSIS
Prepares, validates or publishes an annotated release batch in dependency order after one shared qualification.
.PARAMETER ReleaseTagsJson
Validated JSON array of exact independently versioned module tags from the release plan.
.PARAMETER TriggerTag
Leader tag owning the workflow. Followers cannot prepare or publish a batch.
.PARAMETER Revision
Exact qualified commit; recorded and checked on every batch operation.
.PARAMETER PackageDirectory
Owned output containing one subdirectory per module and release-set.json.
.PARAMETER Operation
Prepare creates packages, Validate checks every package, Publish validates all before ordered publication.
.PARAMETER WorkspaceRoot
Checkout whose exact manifests own every module/version.
.PARAMETER RequireReadyToRun
Preserves all Core embedded distribution checks during preparation.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([Parameter(Mandatory)][string]$ReleaseTagsJson,[Parameter(Mandatory)][string]$TriggerTag,
    [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Revision,
    [Parameter(Mandatory)][string]$PackageDirectory,[ValidateSet('Prepare','Validate','Publish')][string]$Operation='Validate',
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$RequireReadyToRun)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/GalleryRelease.psm1')
Import-Module (Join-Path $PSScriptRoot 'lib/Gallery.psm1')
if($ReleaseTagsJson.Length -gt 32768 -or !$ReleaseTagsJson.TrimStart().StartsWith('[')){throw 'GalleryReleaseBatchInvalid'}
$tags=@($ReleaseTagsJson|ConvertFrom-Json)
$batch=Resolve-QuietGalleryReleaseBatch -WorkspaceRoot $WorkspaceRoot -Tag $TriggerTag -Revision $Revision -Tags $tags
if(!$batch.IsLeader){throw 'GalleryReleaseBatchLeaderRequired'}
$directory=[IO.Path]::GetFullPath($PackageDirectory,$PWD.Path)
if(!$PSCmdlet.ShouldProcess($directory,($Operation+' Gallery release batch '+($batch.Tags -join ', ')))){return}
$receiptPath=Join-Path $directory release-set.json
if($Operation -ceq 'Prepare'){
    if(Test-Path -LiteralPath $directory){throw 'GalleryOutputAlreadyExists'}
    [void][IO.Directory]::CreateDirectory($directory)
    foreach($release in $batch.Releases){
        $null=& (Join-Path $PSScriptRoot 'New-QuietGalleryPackage.ps1') -WorkspaceRoot $WorkspaceRoot -OutputDirectory (Join-Path $directory $release.Module) -Module $release.Module -Version $release.Version -RequireReadyToRun:$RequireReadyToRun -Confirm:$false
    }
    $receipt=@{SchemaVersion=1;Revision=$Revision;LeaderTag=$batch.LeaderTag;Tags=$batch.Tags;State='Prepared'}
    [IO.File]::WriteAllText($receiptPath,($receipt|ConvertTo-Json -Depth 5)+"`n",[Text.UTF8Encoding]::new($false))
}
$file=Get-Item -LiteralPath $receiptPath -Force
if($file.Length -gt 32768 -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'GalleryReleaseSetInvalid'}
$receipt=[IO.File]::ReadAllText($receiptPath,[Text.UTF8Encoding]::new($false,$true))|ConvertFrom-Json
if($receipt.SchemaVersion -ne 1 -or $receipt.Revision -cne $Revision -or $receipt.LeaderTag -cne $batch.LeaderTag -or ($receipt.Tags -join "`n") -cne ($batch.Tags -join "`n")){throw 'GalleryReleaseSetMismatch'}
# Reject every damaged/mismatching package before publishing the first module.
foreach($release in $batch.Releases){
    $plan=Test-QuietGalleryPackageSet (Join-Path $directory $release.Module) -Version $release.Version
    if($plan.Module -cne $release.Module){throw 'GalleryReleaseTagPackageMismatch'}
}
if($Operation -ceq 'Publish'){
    foreach($release in $batch.Releases){
        $null=& (Join-Path $PSScriptRoot 'Publish-QuietGallery.ps1') -PackageDirectory (Join-Path $directory $release.Module) -Version $release.Version -Confirm:$false
    }
}
[pscustomobject]@{State=$Operation;Revision=$Revision;Tags=$batch.Tags;Modules=@($batch.Releases.Module);Published=($Operation -ceq 'Publish')}
