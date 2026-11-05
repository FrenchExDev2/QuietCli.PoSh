# Objectif : Déclencher ou consulter explicitement un workflow GitHub du dépôt demandé.
#requires -Version 7.6
<#
.SYNOPSIS
Explicit GitHub Actions dispatch or status through the locally configured gh CLI.
.PARAMETER Repository
GitHub owner/repository.
.PARAMETER Workflow
Workflow filename, ci.yml by default.
.PARAMETER Ref
Required Git ref for dispatch.
.PARAMETER Status
Lists recent runs instead of dispatching.
.PARAMETER WorkspaceRoot
QuietCli2 root.
#>
[CmdletBinding()]param([Parameter(Mandatory)][ValidatePattern('^[\w.-]+/[\w.-]+$')][string]$Repository,[string]$Workflow='ci.yml',[string]$Ref,[switch]$Status,[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot 'Common.ps1')
if($Status){Invoke-WorkspaceNative gh @('run','list','--repo',$Repository,'--workflow',$Workflow,'--limit','10') $WorkspaceRoot}
else{if(!$Ref){throw 'ExplicitRefRequired'};Invoke-WorkspaceNative gh @('workflow','run',$Workflow,'--repo',$Repository,'--ref',$Ref) $WorkspaceRoot}
