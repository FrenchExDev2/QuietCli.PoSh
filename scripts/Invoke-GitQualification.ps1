# Objectif : Vérifier la complétude réelle de la qualification Git et refuser un succès fondé sur le seul inventaire.
#requires -Version 7.6
<#
.SYNOPSIS
Qualification gate: fails explicitly while inventory, option or platform coverage is incomplete.
.PARAMETER ConfigurationPath
Prepared Podman/Dockur qualification configuration with capability evidence.
.PARAMETER WorkspaceRoot
QuietCli2 workspace.
#>
[CmdletBinding()]param([string]$ConfigurationPath,[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot 'Common.ps1')
$directory=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'qualification') ([DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss'))
[void][IO.Directory]::CreateDirectory($directory)
$env:PSModulePath=$WorkspaceRoot+[IO.Path]::PathSeparator+$env:PSModulePath
Import-Module (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1') -Force
$coverage=@(Get-QuietGitCoverage)
$missing=@($coverage|Where-Object{$_.Qualification -ne 'Qualified'})
$configurationAvailable=$ConfigurationPath -and (Test-Path -LiteralPath $ConfigurationPath)
$report=@{SchemaVersion=1;EntireInventoryQualified=$false;State='Incomplete';Commands=$coverage.Count;Unqualified=$missing.Count;ConfigurationAvailable=[bool]$configurationAvailable;Missing=@($missing);RequiredPlatforms=@('windows-dockur','debian-glibc','alpine-musl');Versions=@(40..56|ForEach-Object{"2.$_.0"});Reason='Full semantic handlers and per-option/platform evidence are not yet complete. Smoke suites are not a substitute for full qualification.'}
Write-WorkspaceJson (Join-Path $directory 'qualification.json') $report
if(!$configurationAvailable){throw "QualificationConfigurationMissing: see $directory/qualification.json"}
if($missing.Count){throw "QualificationIncomplete: $($missing.Count) inventoried commands still lack full qualification. See $directory/qualification.json"}
throw 'QualificationRunnerNotImplemented: refusing to certify unexecuted version/platform scenarios.'
