#requires -Version 7.6
<#
.SYNOPSIS
Updates project hashes without committing, pushing or trying to pin a repository to its own future commit.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
#>
[CmdletBinding(SupportsShouldProcess)]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent))
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Update-WorkspaceLock')){return}
$ErrorActionPreference='Stop';Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
$identity=Get-QuietWorkspaceIdentity $WorkspaceRoot
$dependencies=@{}
foreach($project in Get-QuietWorkspaceProjects $WorkspaceRoot){$dependencies[$project.Name]=$project.Dependencies}
$projects=@(foreach($project in $identity.Projects){@{Name=$project.Name;Path=$project.Path;Dependencies=$dependencies[$project.Name];SourceSHA256=$project.SourceSHA256}})
$sdk=(Get-Content -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'global.json')) -Raw -Encoding utf8|ConvertFrom-Json).sdk.version
[xml]$engine=Get-Content -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj')) -Raw -Encoding utf8
$runtime=@($engine.SelectNodes('//RuntimeFrameworkVersion')|Where-Object {$_.GetAttribute('Condition') -match "net11\.0"})
if($runtime.Count -ne 1){throw 'WorkspaceRuntimePinNotUnique'}
Write-WorkspaceJson ([IO.Path]::Combine($WorkspaceRoot,'repositories.lock.json')) @{SchemaVersion=3;Layout='Monorepo';SDK=$sdk;Runtime=$runtime[0].InnerText;Repository=@{Name=$identity.Repository.Name;Remote=$identity.Repository.Remote;SourceSHA256=$identity.Repository.SourceSHA256};Projects=$projects}
[pscustomobject]@{Repositories=1;Projects=$projects.Count;RevisionRecordedOnlyInBuildReports=$true;Published=$false}
