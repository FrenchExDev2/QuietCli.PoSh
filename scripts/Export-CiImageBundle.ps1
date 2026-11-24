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
.PARAMETER CacheKey
Returns the exact recipe-set hash without contacting Docker or a registry.
.PARAMETER ReuseArchive
Verifies an exact cached archive and binds its receipt to the current run and revision.
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
    [Parameter(Mandatory,ParameterSetName='Key')][ValidateScript({$_.IsPresent})][switch]$CacheKey,
    [Parameter(Mandatory,ParameterSetName='Reuse')][ValidateScript({$_.IsPresent})][switch]$ReuseArchive
)
if(!$CacheKey){
    $action=if($ReuseArchive){'Verify and bind the cached CI image archive'}else{'Prepare and archive verified CI images'}
    if(!$PSCmdlet.ShouldProcess($OutputDirectory,$action)){return}
}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiCompanions.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiImages.psm1')) -DisableNameChecking -ErrorAction Stop
$root=[IO.Path]::GetFullPath('..',$PSScriptRoot)
$configuration=Read-QuietCiCompanions $root
if($CacheKey -or $ReuseArchive){
    $fingerprints=[string[]]@(foreach($name in $Suite){
        $selection=Resolve-QuietCiCompanions $configuration -Suite $name
        (Get-QuietCiSuiteImagePlan $root $selection $RuntimeIdentifier).Fingerprint
    })
    $fingerprints=[string[]]@($fingerprints | Sort-Object -CaseSensitive -Unique)
    if(!$fingerprints.Count){throw 'CiImageBundleEmpty'}
    if($CacheKey){
        $bytes=[Text.Encoding]::UTF8.GetBytes(($fingerprints -join "`n"))
        return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    $directory=[IO.Path]::GetFullPath($OutputDirectory,$PWD.ProviderPath)
    Export-QuietCiImageBundle -WorkspaceRoot $root -RuntimeIdentifier $RuntimeIdentifier -Directory $directory -Revision $Revision -RunId $RunId -CachedFingerprints $fingerprints
    return
}
$directory=[IO.Path]::GetFullPath($OutputDirectory,$PWD.ProviderPath)
if(Test-Path -LiteralPath $directory){throw 'CiImageBundleDirectoryExists'}
$selection=Invoke-QuietCiSuiteImages -WorkspaceRoot $root -Configuration $configuration -Suite $Suite -RuntimeIdentifier $RuntimeIdentifier -ContainerRuntime docker -RegistryCache -PublishCache:$PublishCache -Confirm:$false
Export-QuietCiImageBundle -WorkspaceRoot $root -RuntimeIdentifier $RuntimeIdentifier -Directory $directory -Revision $Revision -RunId $RunId -Receipts @($selection.Chains.Receipt)
