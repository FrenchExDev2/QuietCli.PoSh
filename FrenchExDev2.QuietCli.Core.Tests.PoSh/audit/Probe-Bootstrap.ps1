# Objectif : Vérifier le bootstrap sans autoload dans un processus isolé, avec une longue ligne synthétique.
#requires -Version 7.6
<#
.SYNOPSIS
Checks that the engine-independent CI process reader rejects an oversized unterminated record.
.PARAMETER WorkspaceRoot
QuietCli2 workspace.
#>
[CmdletBinding()]param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
$utf8=[Text.UTF8Encoding]::new($false);[Console]::InputEncoding=$utf8;[Console]::OutputEncoding=$utf8;$OutputEncoding=$utf8
. (Join-Path $WorkspaceRoot 'scripts/Bootstrap.ps1')
$fixture=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture/QuietCli.Fixture.dll'
$before=[GC]::GetTotalMemory($true);$rejected=$false
try{$null=Invoke-CiProcess -FilePath dotnet -ArgumentList @($fixture,'emit','16777216') -MaxRecordChars 8192 -OnOutput {param($e,$s)}}catch{$rejected=$_.Exception.Message -eq 'CiRecordTooLarge'}
$delta=[GC]::GetTotalMemory($true)-$before
@{Rejected=$rejected;ManagedDeltaBytes=$delta;ExpectedNativeBytes=16777216}|ConvertTo-Json -Compress
