#requires -Version 7.6
<#
.SYNOPSIS
Compares real git status output against an independent runner using only the Core module.
.PARAMETER WorkspaceRoot
Explicit local QuietCli2 monorepo.
.PARAMETER RepositoryPath
Existing repository to inspect; no fixture or repository mutation is performed.
.PARAMETER RunDirectory
Private directory for this probe's telemetry.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RepositoryPath,[Parameter(Mandatory)][string]$RunDirectory)
$ErrorActionPreference='Stop'
$utf8=[Text.UTF8Encoding]::new($false)
[Console]::InputEncoding=$utf8;[Console]::OutputEncoding=$utf8;$OutputEncoding=$utf8
if(Get-Module FrenchExDev2.QuietCli.*){throw 'ContaminatedStatusProbe'}
. (Join-Path $WorkspaceRoot 'scripts/Ci.Process.ps1')
. (Join-Path $PSScriptRoot 'Status.Aggregation.ps1')
$env:QUIETCLI2_DATABASE=Join-Path $RunDirectory 'real-status.sqlite'
$env:GIT_OPTIONAL_LOCKS='0'
$env:GIT_TERMINAL_PROMPT='0'
$env:GIT_PAGER='cat'
$git=(Get-Command git -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
$manifest=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1'
$importWatch=[Diagnostics.Stopwatch]::StartNew()
Import-Module $manifest
$importWatch.Stop()
$module=Get-Module FrenchExDev2.QuietCli.Core.PoSh
if($module.Path -cne [IO.Path]::ChangeExtension([IO.Path]::GetFullPath($manifest),'.psm1')){throw 'UnexpectedRealStatusCorePath'}
if(@(Get-QuietHandler).Count -or (Get-Module FrenchExDev2.QuietCli.Git.PoSh)){throw 'UnexpectedRealStatusHandler'}

. (Join-Path $PSScriptRoot 'Status.Execution.ps1')
Invoke-QuietStatusComparison -RepositoryPath $RepositoryPath -GitPath $git -CoreImportMs $importWatch.Elapsed.TotalMilliseconds | ConvertTo-Json -Depth 12 -Compress
