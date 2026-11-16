#requires -Version 7.6
<#
.SYNOPSIS
Verifies the Git monorepo structure and optionally restores Core's pinned third-party resources.
Internal projects are discovered from their manifests; no committed source snapshot is required.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER Restore
Restores and verifies Core's pinned third-party resources without modifying internal source files
or selecting a branch.
#>
[CmdletBinding(SupportsShouldProcess)]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$Restore)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/WorkspaceLayout.psm1')) -DisableNameChecking -ErrorAction Stop

if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Initialize-Workspace')){return}
$ErrorActionPreference='Stop';Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
$WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path)
if(!(Test-Path -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'.git')))){throw 'MonorepoGitMetadataMissing'}
$names=@((Get-QuietWorkspaceProjects $WorkspaceRoot).Name)
foreach($name in $names){
    $path=(Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $name)
    if(!(Test-Path -LiteralPath ([IO.Path]::Combine($path,($name+'.psd1'))))){throw ('ProjectManifestMissing: '+$name)}
    if(Test-Path -LiteralPath ([IO.Path]::Combine($path,'.git'))){throw ('NestedRepositoryUnsupported: '+$name)}
}
if($Restore){
    & ([IO.Path]::Combine($PSScriptRoot,'Restore-CoreResources.ps1')) -WorkspaceRoot $WorkspaceRoot
}
[pscustomobject]@{Layout='Monorepo';Repositories=1;Projects=$names.Count;Restored=[bool]$Restore;Verified=$true}
