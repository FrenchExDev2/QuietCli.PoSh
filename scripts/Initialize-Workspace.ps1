# Objectif : Vérifier un checkout unique et les quatre projets internes sans clone de dépôts enfants.
#requires -Version 7.6
<#
.SYNOPSIS
Verifies the monorepo structure; Restore checks committed source hashes instead of cloning child repositories.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER Restore
Verifies the existing source lock, without modifying source files or selecting a branch.
#>
[CmdletBinding()]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$Restore)
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot 'Common.ps1')
$WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path)
if(!(Test-Path -LiteralPath (Join-Path $WorkspaceRoot '.git'))){throw 'MonorepoGitMetadataMissing'}
$names=@('FrenchExDev2.QuietCli.Core.PoSh','FrenchExDev2.QuietCli.Core.Tests.PoSh','FrenchExDev2.QuietCli.Git.PoSh','FrenchExDev2.QuietCli.Git.Tests.PoSh')
foreach($name in $names){
    $path=Join-Path $WorkspaceRoot $name
    if(!(Test-Path -LiteralPath (Join-Path $path ($name+'.psd1')))){throw ('ProjectManifestMissing: '+$name)}
    if(Test-Path -LiteralPath (Join-Path $path .git)){throw ('NestedRepositoryUnsupported: '+$name)}
}
if($Restore){
    $lock=Get-Content (Join-Path $WorkspaceRoot repositories.lock.json) -Encoding utf8 -Raw|ConvertFrom-Json
    if($lock.SchemaVersion -ne 3 -or $lock.Layout -cne 'Monorepo'){throw 'MonorepoSourceLockRequired'}
    $identity=Get-QuietWorkspaceIdentity $WorkspaceRoot
    foreach($project in $identity.Projects){$expected=@($lock.Projects|Where-Object Name -CEQ $project.Name);if($expected.Count -ne 1 -or $expected[0].SourceSHA256 -cne $project.SourceSHA256){throw ('ProjectSourceLockMismatch: '+$project.Name)}}
    if($lock.Repository.SourceSHA256 -cne $identity.Repository.SourceSHA256){throw 'MonorepoSourceLockMismatch'}
}else{& (Join-Path $PSScriptRoot Update-WorkspaceLock.ps1) -WorkspaceRoot $WorkspaceRoot}
[pscustomobject]@{Layout='Monorepo';Repositories=1;Projects=4;Restored=$false;Verified=$true}
