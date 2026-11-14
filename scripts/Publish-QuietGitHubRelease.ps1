#requires -Version 7.6
<#
.SYNOPSIS
Creates per-module GitHub releases from exact packages already published on PowerShell Gallery.
.PARAMETER TriggerTag
Original module tag owning this release workflow.
.PARAMETER Revision
Exact qualified workflow commit.
.PARAMETER PackageDirectory
Downloaded unchanged Gallery packages and publication receipts.
.PARAMETER ReleaseTagsJson
Optional validated annotated batch; empty selects the standalone trigger tag.
.PARAMETER WorkspaceRoot
Checkout whose literal manifests own the release tags.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$TriggerTag,[Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Revision,
    [Parameter(Mandatory)][string]$PackageDirectory,[string]$ReleaseTagsJson='',[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/GalleryRelease.psm1')) -DisableNameChecking
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Gallery.psm1')) -DisableNameChecking
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/GitHubRelease.psm1')) -DisableNameChecking
$tags=@($TriggerTag)
if($ReleaseTagsJson){
    if($ReleaseTagsJson.Length -gt 32768 -or !$ReleaseTagsJson.TrimStart().StartsWith('[')){throw 'GalleryReleaseBatchInvalid'}
    $tags=@($ReleaseTagsJson|ConvertFrom-Json)
}
$batch=Resolve-QuietGalleryReleaseBatch -WorkspaceRoot $WorkspaceRoot -Tag $TriggerTag -Revision $Revision -Tags $tags
if(!$batch.IsLeader){throw 'GalleryReleaseBatchLeaderRequired'}
if(!$PSCmdlet.ShouldProcess($TriggerTag,'Publish GitHub releases for verified Gallery packages')){return}
if($env:GITHUB_REPOSITORY -cne 'FrenchExDev2/QuietCli.PoSh' -or $env:GITHUB_EVENT_NAME -cne 'push' -or $env:GITHUB_REF -cne ('refs/tags/'+$TriggerTag) -or $env:GITHUB_SHA -cne $Revision){throw 'GitHubReleaseWorkflowContextRequired'}
$directory=[IO.Path]::GetFullPath($PackageDirectory,$PWD.Path)
$prepared=@(foreach($release in $batch.Releases){
    $packageDirectory=if($ReleaseTagsJson){[IO.Path]::Combine($directory,$release.Module)}else{$directory}
    $plan=Test-QuietGalleryPackageSet $packageDirectory -Version $release.Version
    if($plan.Module -cne $release.Module){throw 'GalleryReleaseTagPackageMismatch'}
    $receiptPath=[IO.Path]::Combine($packageDirectory,'publication.json')
    $file=Get-Item -LiteralPath $receiptPath -Force
    if($file.Length -gt 32768 -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'GitHubReleasePublicationReceiptInvalid'}
    $receipt=Get-Content -LiteralPath $receiptPath -Encoding utf8 -Raw|ConvertFrom-Json
    if($receipt.SchemaVersion -ne 1 -or $receipt.Repository -cne 'PSGallery' -or $receipt.State -cne 'Published' -or $receipt.Version -cne $release.Version -or @($receipt.Modules).Count -ne 1 -or $receipt.Modules[0].Module -cne $release.Module -or $receipt.Modules[0].State -cne 'Published' -or $receipt.Modules[0].SHA256 -cne $plan.Packages[0].SHA256){throw 'GitHubReleasePublicationReceiptInvalid'}
    @{Tag=$release.Tag;Version=$release.Version;Assets=@(([IO.Path]::Combine($packageDirectory,$plan.Packages[0].File)),([IO.Path]::Combine($packageDirectory,'package-set.json')),$receiptPath)}
})
foreach($release in $prepared){Publish-QuietGitHubRelease @release -Revision $Revision -Confirm:$false}
