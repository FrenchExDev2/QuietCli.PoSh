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
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string[]]$Suite,
    [Parameter(Mandatory)][ValidateSet('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string]$RuntimeIdentifier,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Revision,
    [Parameter(Mandatory)][ValidatePattern('\A[0-9]+\z')][string]$RunId,
    [switch]$PublishCache
)
if(!$PSCmdlet.ShouldProcess($OutputDirectory,'Prepare and archive verified CI images')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiCompanions.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiImages.psm1')) -DisableNameChecking -ErrorAction Stop
$root=[IO.Path]::GetFullPath('..',$PSScriptRoot)
$directory=[IO.Path]::GetFullPath($OutputDirectory,$PWD.ProviderPath)
if(Test-Path -LiteralPath $directory){throw 'CiImageBundleDirectoryExists'}
$configuration=Read-QuietCiCompanions $root
$selection=Invoke-QuietCiSuiteImages -WorkspaceRoot $root -Configuration $configuration -Suite $Suite -RuntimeIdentifier $RuntimeIdentifier -ContainerRuntime docker -RegistryCache -PublishCache:$PublishCache -Confirm:$false
Export-QuietCiImageBundle -WorkspaceRoot $root -RuntimeIdentifier $RuntimeIdentifier -Directory $directory -Revision $Revision -RunId $RunId -Receipts @($selection.Chains.Receipt)
