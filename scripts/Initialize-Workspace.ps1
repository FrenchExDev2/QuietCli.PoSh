#requires -Version 7.6
<#
.SYNOPSIS
Verifies the monorepo structure; Restore checks committed source hashes instead of cloning child
repositories, then restores Core's pinned third-party resources (see Restore-CoreResources.ps1) so a
fresh clone is ready to build.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER Restore
Verifies the existing source lock and restores Core's pinned third-party resources, without modifying
source files or selecting a branch.
#>
[CmdletBinding(SupportsShouldProcess)]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$Restore)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Initialize-Workspace')){return}
$ErrorActionPreference='Stop';Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
$WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path)
if(!(Test-Path -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'.git')))){throw 'MonorepoGitMetadataMissing'}
$names=@((Get-QuietWorkspaceProjects $WorkspaceRoot).Name)
foreach($name in $names){
    $path=[IO.Path]::Combine($WorkspaceRoot,$name)
    if(!(Test-Path -LiteralPath ([IO.Path]::Combine($path,($name+'.psd1'))))){throw ('ProjectManifestMissing: '+$name)}
    if(Test-Path -LiteralPath ([IO.Path]::Combine($path,'.git'))){throw ('NestedRepositoryUnsupported: '+$name)}
}
if($Restore){
    $lock=Get-Content ([IO.Path]::Combine($WorkspaceRoot,'repositories.lock.json')) -Encoding utf8 -Raw|ConvertFrom-Json
    if($lock.SchemaVersion -ne 3 -or $lock.Layout -cne 'Monorepo'){throw 'MonorepoSourceLockRequired'}
    $identity=Get-QuietWorkspaceIdentity $WorkspaceRoot
    foreach($project in $identity.Projects){$expected=@($lock.Projects|Where-Object Name -CEQ $project.Name);if($expected.Count -ne 1 -or $expected[0].SourceSHA256 -cne $project.SourceSHA256){throw ('ProjectSourceLockMismatch: '+$project.Name)}}
    if($lock.Repository.SourceSHA256 -cne $identity.Repository.SourceSHA256){throw 'MonorepoSourceLockMismatch'}
    & ([IO.Path]::Combine($PSScriptRoot,'Restore-CoreResources.ps1')) -WorkspaceRoot $WorkspaceRoot
}else{& ([IO.Path]::Combine($PSScriptRoot,'Update-WorkspaceLock.ps1')) -WorkspaceRoot $WorkspaceRoot}
[pscustomobject]@{Layout='Monorepo';Repositories=1;Projects=$names.Count;Restored=$false;Verified=$true}
