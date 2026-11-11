#requires -Version 7.6
<#
.SYNOPSIS
Validates a prepared preview against its qualified immutable checkpoint without querying branch HEAD.
.PARAMETER PackageDirectory
Downloaded preview.json and package-set.json, whose nupkg hashes are checked by Publish-QuietGallery.
.PARAMETER QualifiedRevision
Exact revision emitted by this run's successful qualification gate.
.PARAMETER Version
Exact package version selected by this run's packaging job.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PackageDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}\z')][string]$QualifiedRevision,
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+-[A-Za-z][A-Za-z0-9-]*\z')][string]$Version)
$ErrorActionPreference='Stop'
$previewPath=Join-Path $PackageDirectory 'preview.json';$planPath=Join-Path $PackageDirectory 'package-set.json'
foreach($path in @($previewPath,$planPath)){if(!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -gt 131072){throw 'GalleryCheckpointMetadataMissingOrOversized'}}
$preview=Get-Content -LiteralPath $previewPath -Raw -Encoding utf8|ConvertFrom-Json
$plan=Get-Content -LiteralPath $planPath -Raw -Encoding utf8|ConvertFrom-Json
if($preview -isnot [pscustomobject] -or $plan -isnot [pscustomobject]){throw 'GalleryCheckpointMetadataObjectRequired'}
if($preview.SourceRevision -isnot [string] -or $preview.QualifiedRevision -isnot [string] -or $preview.Version -isnot [string] -or $plan.Version -isnot [string]){throw 'GalleryCheckpointScalarMetadataRequired'}
if($preview.SourceRevision -cne $QualifiedRevision -or $preview.QualifiedRevision -cne $QualifiedRevision){throw 'GalleryCheckpointRevisionMismatch'}
if($preview.Version -cne $Version -or $plan.Version -cne $Version){throw 'GalleryCheckpointVersionMismatch'}
[pscustomobject]@{State='CheckpointValidated';Version=$Version;QualifiedRevision=$QualifiedRevision;BranchHeadQueried=$false;Published=$false}
