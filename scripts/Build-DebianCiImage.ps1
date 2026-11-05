# Objectif : Préparer une image Debian détenue avec Git vérifié, sans installer de logiciel sur l’hôte.
#requires -Version 7.6
<#
.SYNOPSIS
Builds the Debian qualification image from local bases; apt and the locked source download occur inside the image.
.PARAMETER WorkspaceRoot
QuietCli2 root.
.PARAMETER Tag
New local image tag.
.PARAMETER SdkImage
Existing SDK source image containing the pinned .NET RC and PowerShell.
.PARAMETER GitVersion
Version present in the official source lock.
#>
[CmdletBinding()]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$Tag='localhost/quietcli2-debian-net11:2.56.0',[ValidatePattern('^[a-zA-Z0-9./_:-]+@sha256:[a-f0-9]{64}$')][string]$SdkImage='mcr.microsoft.com/dotnet/sdk@sha256:9fc2f44fba54c579b9b650f6feea29beff050fb030d797eac697de85a94ad77f',[string]$GitVersion='2.56.0')
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot 'Common.ps1')
$lock=Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.PoSh/metadata/locks/UpstreamSources.json') -Encoding utf8 -Raw|ConvertFrom-Json
$source=@($lock.Sources|Where-Object Version -EQ $GitVersion)|Select-Object -First 1
if(!$source){throw 'GitVersionNotLocked'}
$state=@{Lines=0;Diagnostics=[Collections.Generic.Queue[string]]::new()}
$result=Invoke-CiProcess -FilePath podman -ArgumentList @('build','--pull=never','--jobs','1','--build-arg',"SDK_IMAGE=$SdkImage",'--build-arg',"GIT_VERSION=$GitVersion",'--build-arg',"GIT_SHA256=$($source.SHA256)",'-f',(Join-Path $WorkspaceRoot '.github/containers/Containerfile.debian'),'-t',$Tag,(Join-Path $WorkspaceRoot '.github/containers')) -TimeoutSeconds 1800 -WorkingDirectory $WorkspaceRoot -State $state -OnOutput {param($record,$state)$state.Lines++;if($state.Diagnostics.Count -ge 12){$null=$state.Diagnostics.Dequeue()};$state.Diagnostics.Enqueue($record.Text)}
[pscustomobject]@{Outcome=$result.Outcome;Lines=$state.Lines;Diagnostics=@($state.Diagnostics)}
if($result.Outcome -ne 'Success'){throw 'DebianImageBuildFailed'}
