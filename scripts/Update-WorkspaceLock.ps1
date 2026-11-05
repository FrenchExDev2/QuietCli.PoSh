# Objectif : Verrouiller les sources et dépendances des quatre projets d’un seul monorepo.
#requires -Version 7.6
<#
.SYNOPSIS
Updates project hashes without committing, pushing or trying to pin a repository to its own future commit.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
#>
[CmdletBinding()]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot 'Common.ps1')
$identity=Get-QuietWorkspaceIdentity $WorkspaceRoot
$dependencies=@{
 'FrenchExDev2.QuietCli.Core.PoSh'=@()
 'FrenchExDev2.QuietCli.Core.Tests.PoSh'=@('FrenchExDev2.QuietCli.Core.PoSh')
 'FrenchExDev2.QuietCli.Git.PoSh'=@('FrenchExDev2.QuietCli.Core.PoSh')
 'FrenchExDev2.QuietCli.Git.Tests.PoSh'=@('FrenchExDev2.QuietCli.Git.PoSh','FrenchExDev2.QuietCli.Core.Tests.PoSh')
}
$projects=@(foreach($project in $identity.Projects){@{Name=$project.Name;Path=$project.Path;Dependencies=$dependencies[$project.Name];SourceSHA256=$project.SourceSHA256}})
Write-WorkspaceJson (Join-Path $WorkspaceRoot 'repositories.lock.json') @{SchemaVersion=3;Layout='Monorepo';SDK='11.0.100-rc.3.26522.148';Runtime='11.0.0-rc.3.26522.148';Repository=@{Name=$identity.Repository.Name;Remote=$identity.Repository.Remote;SourceSHA256=$identity.Repository.SourceSHA256};Projects=$projects}
[pscustomobject]@{Repositories=1;Projects=$projects.Count;RevisionRecordedOnlyInBuildReports=$true;Published=$false}
