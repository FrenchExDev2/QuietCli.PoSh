#requires -Version 7.6
<#
.SYNOPSIS
Loads the verified image for a test suite from the current run's Linux image bundle.
.PARAMETER Suite
Suite whose image must be present.
.PARAMETER RuntimeIdentifier
Native Linux target.
.PARAMETER Directory
Downloaded bundle directory.
.PARAMETER Revision
Revision under test.
.PARAMETER RunId
GitHub Actions run supplying the image.
.PARAMETER GetCacheKey
Returns the exact Actions cache key from a verified current-run handoff, when present.
.PARAMETER ArchiveDirectory
Directory holding the restored Actions archive when the current-run artifact supplied only its receipt.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Suite,
    [Parameter(Mandatory)][ValidateSet('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string]$RuntimeIdentifier,
    [Parameter(Mandatory)][string]$Directory,
    [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Revision,
    [Parameter(Mandatory)][ValidatePattern('\A[0-9]+\z')][string]$RunId,
    [switch]$GetCacheKey,
    [string]$ArchiveDirectory
)
if(!$GetCacheKey -and !$PSCmdlet.ShouldProcess($Directory,'Load the verified Linux CI image')){return}
$ErrorActionPreference='Stop'
$directoryPath=[IO.Path]::GetFullPath($Directory,$PWD.ProviderPath)
$handoffPath=[IO.Path]::Combine($directoryPath,'handoff.json')
$handoff=$null
if(Test-Path -LiteralPath $handoffPath -PathType Leaf){
    $handoff=Get-Content -LiteralPath $handoffPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    if($handoff.SchemaVersion -ne 1 -or $handoff.Revision -cne $Revision -or $handoff.RunId -cne $RunId -or $handoff.RuntimeIdentifier -cne $RuntimeIdentifier){throw 'CiImageHandoffIdentityMismatch'}
    if($handoff.CacheKey -and $handoff.CacheKey -cnotmatch "\Aquietcli-ci-archive-v1-$RuntimeIdentifier-[a-f0-9]{64}(?:-renew-[0-9]+-[0-9]+)?\z"){throw 'CiImageHandoffCacheKeyInvalid'}
    if([bool]$handoff.CacheKey -eq [bool]$handoff.RegistryDigests){throw 'CiImageHandoffSourceInvalid'}
}
if($GetCacheKey){
    if($handoff){return $handoff.CacheKey}
    return
}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiImages.psm1')) -DisableNameChecking -ErrorAction Stop
$plan=& ([IO.Path]::Combine($PSScriptRoot,'New-CiSuiteImage.ps1')) -Suite $Suite -RuntimeIdentifier $RuntimeIdentifier -PlanOnly
if($handoff.RegistryDigests){
    $expectedDigest=$handoff.RegistryDigests[$plan.Fingerprint]
    if($expectedDigest -cnotmatch '\Asha256:[a-f0-9]{64}\z'){throw 'CiImageHandoffExpectedDigestMissing'}
    $root=[IO.Path]::GetFullPath('..',$PSScriptRoot)
    $receipt=Invoke-QuietCiImageBuild -Plan $plan -ContextDirectory ([IO.Path]::Combine($root,'.github/containers')) -WorkspaceRoot $root -ArtifactPrefix ('handoff-'+$RuntimeIdentifier) -RegistryCache -CacheOnly -ContainerRuntime docker
    if(!$receipt -or $receipt.RegistryDigest -cne $expectedDigest){throw 'CiImageHandoffRegistryDigestMismatch'}
    return $receipt.Image
}
if($handoff.CacheKey){
    if(!$ArchiveDirectory){throw 'CiImageHandoffCacheArchiveMissing'}
    $restored=[IO.Path]::GetFullPath($ArchiveDirectory,$PWD.ProviderPath)
    Copy-Item -LiteralPath ([IO.Path]::Combine($directoryPath,'bundle.json')) -Destination ([IO.Path]::Combine($restored,'bundle.json')) -Force
    $directoryPath=$restored
}
Import-QuietCiImageBundle -Directory $directoryPath -Plan $plan -Revision $Revision -RunId $RunId
