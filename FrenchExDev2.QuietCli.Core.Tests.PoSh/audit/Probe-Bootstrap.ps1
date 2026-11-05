# Objectif : Vérifier le bootstrap sans autoload dans un processus isolé, avec une longue ligne synthétique.
#requires -Version 7.6
<#
.SYNOPSIS
Checks that the profile-free fallback rejects a long unterminated record while retaining bounded managed memory.
.PARAMETER WorkspaceRoot
QuietCli2 workspace.
#>
[CmdletBinding()]param([string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
$utf8=[Text.UTF8Encoding]::new($false);[Console]::InputEncoding=$utf8;[Console]::OutputEncoding=$utf8;$OutputEncoding=$utf8
. (Join-Path $WorkspaceRoot 'scripts/Bootstrap.ps1')
$fixture=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture/QuietCli.Fixture.dll'
$before=[GC]::GetTotalMemory($true);$rejected=$false
try{$null=pump -AsObject -State @{} -OnOutput {param($e,$s)} -Complete {param($s)} dotnet $fixture emit 16777216}catch{$rejected=$_.Exception.Message -eq 'BootstrapRecordTooLarge'}
$delta=[GC]::GetTotalMemory($true)-$before
@{Rejected=$rejected;ManagedDeltaBytes=$delta;ExpectedNativeBytes=16777216}|ConvertTo-Json -Compress
