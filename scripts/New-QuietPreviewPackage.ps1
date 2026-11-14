#requires -Version 7.6
<#
.SYNOPSIS
Prepares and validates uniquely versioned Core-only preview packages without publishing or editing source manifests.
.PARAMETER WorkspaceRoot
Built QuietCli2 checkout.
.PARAMETER OutputDirectory
New destination for the nupkg files, publication plan and preview provenance.
.PARAMETER BuildNumber
Monotonic build counter; defaults to GITHUB_RUN_NUMBER in GitHub Actions.
.PARAMETER Attempt
Packaging attempt; defaults to GITHUB_RUN_ATTEMPT, or 1 outside GitHub Actions.
.PARAMETER QualifiedRevision
Optional exact revision returned by the qualification gate; requires matching HEAD and a clean source checkout.
.PARAMETER RequireReadyToRun
Requires all six Release ReadyToRun distributions before preparing the preview.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$BuildNumber=$env:GITHUB_RUN_NUMBER,
    [string]$Attempt=$(if($env:GITHUB_RUN_ATTEMPT){$env:GITHUB_RUN_ATTEMPT}else{'1'}),
    [string]$QualifiedRevision,
    [switch]$RequireReadyToRun
)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: New-QuietPreviewPackage')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Gallery.psm1')) -DisableNameChecking
$WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path)
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory,$PWD.Path)
# This list only forbids writing generated artifacts inside source modules. It never selects public packages;
# New-QuietGalleryPackage.ps1 stages only Core under the existing name inferred from its .psm1 and manifest.
foreach($name in (Get-QuietWorkspaceProjects $WorkspaceRoot).Name){
    $moduleRoot=([IO.Path]::Combine($WorkspaceRoot,$name))+[IO.Path]::DirectorySeparatorChar
    if($OutputDirectory.StartsWith($moduleRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'GalleryPreviewOutputInsideModule'}
}
$manifest=[IO.Path]::Combine($WorkspaceRoot,'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
$base=[string](Import-PowerShellDataFile -LiteralPath $manifest).ModuleVersion
$version=New-QuietGalleryPreviewVersion -BaseVersion $base -BuildNumber $BuildNumber -Attempt $Attempt
$info=Get-QuietGalleryVersion $version
$revision=Read-QuietRepositoryValue $WorkspaceRoot @('rev-parse','--verify','HEAD')
if($QualifiedRevision -and ($QualifiedRevision -cnotmatch '^[a-fA-F0-9]{40}\z' -or $revision -cne $QualifiedRevision)){throw 'GalleryPreviewRevisionMismatch'}
if($QualifiedRevision){
    $dirty=Read-QuietRepositoryValue $WorkspaceRoot @('status','--porcelain=v1','--untracked-files=normal')
    if($dirty){throw 'GalleryPreviewQualifiedCheckoutDirty'}
}
$prepared=& ([IO.Path]::Combine($PSScriptRoot,'New-QuietGalleryPackage.ps1')) -WorkspaceRoot $WorkspaceRoot -OutputDirectory $OutputDirectory -Version $version -Prerelease $info.Prerelease -RequireReadyToRun:$RequireReadyToRun
$null=& ([IO.Path]::Combine($PSScriptRoot,'Publish-QuietGallery.ps1')) -PackageDirectory $OutputDirectory -Version $version -ValidateOnly
Write-WorkspaceJson ([IO.Path]::Combine($OutputDirectory,'preview.json')) @{Version=$version;BaseVersion=$base;BuildNumber=$BuildNumber;Attempt=$Attempt;SourceRevision=$revision;QualifiedRevision=$QualifiedRevision;Published=$false}
$prepared
