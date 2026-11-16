#requires -Version 7.6
<#
.SYNOPSIS
Computes the selected suite build cache key and optionally writes a GitHub output.
.PARAMETER WorkspaceRoot
Selected checkout.
.PARAMETER Suite
Suite whose technical dependency closure is fingerprinted.
.PARAMETER RuntimeIdentifier
Actual target RID.
.PARAMETER ReadyToRun
Requests precompiled publications.
.PARAMETER OutputPath
Optional GitHub output file; writes are explicit and previewable.
.PARAMETER SuitesJson
Explicit companion array when Suite is SmokeBatch.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][string]$Suite,[string]$RuntimeIdentifier=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier,[switch]$ReadyToRun,[string]$OutputPath,[string]$SuitesJson='[]')
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CompanionBuildCache.psm1')) -DisableNameChecking -ErrorAction Stop
$selected=if($Suite -ceq 'SmokeBatch'){@(ConvertFrom-Json $SuitesJson)}else{@($Suite)}
if(!$selected.Count){throw 'ComponentBuildKeyRequiresSuites'}
$keys=@(foreach($name in $selected|Sort-Object -Unique){Get-QuietCompanionBuildKey -WorkspaceRoot $WorkspaceRoot -Suite $name -RuntimeIdentifier $RuntimeIdentifier -ReadyToRun:$ReadyToRun})
$digest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($keys -join [char]10))))
$prefix='quietcli-component-v3-'+$RuntimeIdentifier+'-'+$Suite+'-'+$ReadyToRun.ToString().ToLowerInvariant()+'-'
$key=$prefix+$digest
if($OutputPath -and $PSCmdlet.ShouldProcess($OutputPath,'Append selected build cache key')){[IO.File]::AppendAllText($OutputPath,('cache_key='+$key+[char]10+'cache_prefix='+$prefix+[char]10),[Text.UTF8Encoding]::new($false))}
$key
