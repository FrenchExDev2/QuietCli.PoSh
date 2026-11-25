#requires -Version 7.6
<#
.SYNOPSIS
Prepares and transfers the verified Linux CI images for one native target.
.PARAMETER Suite
Suite names whose image chains are needed.
.PARAMETER RuntimeIdentifier
Native Linux target.
.PARAMETER OutputDirectory
New directory containing the image archive and its receipt.
.PARAMETER Revision
Revision under test.
.PARAMETER RunId
GitHub Actions run supplying the image.
.PARAMETER PublishCache
Allows the existing upstream develop GHCR publication policy.
.PARAMETER PassThru
Returns whether every image chain came from the verified registry cache after the archive has been written.
.PARAMETER CacheKey
Returns the exact recipe-set hash without contacting Docker or a registry.
.PARAMETER ReuseArchive
Verifies an exact cached archive and binds its receipt to the current run and revision.
.PARAMETER RestoredCacheKey
Records the exact Actions cache key for consumers after verifying the restored archive.
.PARAMETER TransferRegistryReferences
Writes only a digest receipt when all requested images are already verified in GHCR.
.PARAMETER RenewCache
Builds the selected image chains without reading or writing GHCR.
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Prepare')]
param(
    [Parameter(Mandatory)][string[]]$Suite,
    [Parameter(Mandatory)][ValidateSet('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string]$RuntimeIdentifier,
    [Parameter(Mandatory,ParameterSetName='Prepare')]
    [Parameter(Mandatory,ParameterSetName='Reuse')][string]$OutputDirectory,
    [Parameter(Mandatory,ParameterSetName='Prepare')]
    [Parameter(Mandatory,ParameterSetName='Reuse')][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Revision,
    [Parameter(Mandatory,ParameterSetName='Prepare')]
    [Parameter(Mandatory,ParameterSetName='Reuse')][ValidatePattern('\A[0-9]+\z')][string]$RunId,
    [Parameter(ParameterSetName='Prepare')][switch]$PublishCache,
    [Parameter(ParameterSetName='Prepare')][switch]$PassThru,
    [Parameter(ParameterSetName='Prepare')][switch]$TransferRegistryReferences,
    [Parameter(ParameterSetName='Prepare')][switch]$RenewCache,
    [Parameter(Mandatory,ParameterSetName='Key')][ValidateScript({$_.IsPresent})][switch]$CacheKey,
    [Parameter(ParameterSetName='Reuse')][string]$RestoredCacheKey,
    [Parameter(Mandatory,ParameterSetName='Reuse')][ValidateScript({$_.IsPresent})][switch]$ReuseArchive
)
if(!$CacheKey){
    $action=if($ReuseArchive){'Verify and bind the cached CI image archive'}else{'Prepare and archive verified CI images'}
    if(!$PSCmdlet.ShouldProcess($OutputDirectory,$action)){return}
}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiCompanions.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiImages.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
$root=[IO.Path]::GetFullPath('..',$PSScriptRoot)
$configuration=Read-QuietCiCompanions $root
if($CacheKey -or $ReuseArchive){
    $fingerprints=[string[]]@(foreach($name in $Suite){
        $selection=Resolve-QuietCiCompanions $configuration -Suite $name
        (Get-QuietCiSuiteImagePlan $root $selection $RuntimeIdentifier).Fingerprint
    })
    $fingerprints=[string[]]@($fingerprints | Sort-Object -CaseSensitive -Unique)
    if(!$fingerprints.Count){throw 'CiImageBundleEmpty'}
    if($CacheKey -or $RestoredCacheKey){
        $bytes=[Text.Encoding]::UTF8.GetBytes(($fingerprints -join "`n"))
        $fingerprint=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        if($CacheKey){return $fingerprint}
        if($RestoredCacheKey -cnotmatch "\Aquietcli-ci-archive-v1-$RuntimeIdentifier-$fingerprint(?:-renew-[0-9]+-[0-9]+)?\z"){throw 'CiImageBundleCacheKeyMismatch'}
    }
    $directory=[IO.Path]::GetFullPath($OutputDirectory,$PWD.ProviderPath)
    Export-QuietCiImageBundle -WorkspaceRoot $root -RuntimeIdentifier $RuntimeIdentifier -Directory $directory -Revision $Revision -RunId $RunId -CachedFingerprints $fingerprints
    if($RestoredCacheKey){
        Write-WorkspaceJson ([IO.Path]::Combine($directory,'handoff.json')) @{
            SchemaVersion=1;Revision=$Revision;RunId=$RunId;RuntimeIdentifier=$RuntimeIdentifier;CacheKey=$RestoredCacheKey
        }
    }
    return
}
$directory=[IO.Path]::GetFullPath($OutputDirectory,$PWD.ProviderPath)
if(Test-Path -LiteralPath $directory){throw 'CiImageBundleDirectoryExists'}
if($RenewCache -and $PublishCache){throw 'CiImageCacheRenewalCannotPublish'}
$selection=$null
if($TransferRegistryReferences -and !$RenewCache){
    $credential=$env:QUIETCLI_REGISTRY_TOKEN
    try{
        $selection=Invoke-QuietCiSuiteImages -WorkspaceRoot $root -Configuration $configuration -Suite $Suite -RuntimeIdentifier $RuntimeIdentifier -ContainerRuntime docker -RegistryCache -ProbeOnly -Confirm:$false
    }catch{
        if($PublishCache){throw}
        Write-Host 'Registry metadata probe unavailable. Preparing verified images through the normal image path.'
    }finally{$env:QUIETCLI_REGISTRY_TOKEN=$credential;$credential=$null}
}
if(!$selection -or !$selection.CacheHit){
    $selection=Invoke-QuietCiSuiteImages -WorkspaceRoot $root -Configuration $configuration -Suite $Suite -RuntimeIdentifier $RuntimeIdentifier -ContainerRuntime docker -RegistryCache:(!$RenewCache) -PublishCache:$PublishCache -Confirm:$false
}
if($TransferRegistryReferences -and $selection.CacheHit){
    $digests=[ordered]@{}
    foreach($receipt in $selection.Chains.Receipt){
        if($receipt.Fingerprint -cnotmatch '\A[a-f0-9]{64}\z' -or $receipt.RegistryDigest -cnotmatch '\Asha256:[a-f0-9]{64}\z'){throw 'CiImageRegistryHandoffInvalid'}
        $digests.Add($receipt.Fingerprint,$receipt.RegistryDigest)
    }
    Write-WorkspaceJson ([IO.Path]::Combine($directory,'handoff.json')) @{
        SchemaVersion=1;Revision=$Revision;RunId=$RunId;RuntimeIdentifier=$RuntimeIdentifier;RegistryDigests=$digests
    }
}else{
    Export-QuietCiImageBundle -WorkspaceRoot $root -RuntimeIdentifier $RuntimeIdentifier -Directory $directory -Revision $Revision -RunId $RunId -Receipts @($selection.Chains.Receipt)
}
if($PassThru){return [pscustomobject]@{CacheHit=$selection.CacheHit}}
