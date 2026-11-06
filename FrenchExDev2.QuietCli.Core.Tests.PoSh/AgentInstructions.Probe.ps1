#requires -Version 7.6
<#
.SYNOPSIS
Checks an installed-layout Core without access to repository instruction fallbacks.
.PARAMETER Manifest
Owned staged Core manifest.
.PARAMETER Project
Owned project to initialize.
.PARAMETER ExpectedHash
Independent digest of the canonical production instructions.
#>
param([string]$Manifest,[string]$Project,[string]$ExpectedHash)
$ErrorActionPreference='Stop'
Import-Module $Manifest -ErrorAction Stop
$core=Get-Module FrenchExDev2.QuietCli.Core.PoSh
if($core.ModuleBase -ne (Split-Path $Manifest -Parent)){throw 'AgentProbeWrongModule'}
$text=Get-QuietAgentInstruction
$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text)))
if($hash -cne $ExpectedHash){throw 'AgentProbeInstructionsMismatch'}
$installation=Add-QuietAgentInstruction -Path $Project -Agents
if($installation.Files[0].Status -ne 'Created' -or ($null -ne [FrenchExDev2.QuietCli.QuietSession]::Engine)){throw 'AgentProbeInstallationOrInertness'}
foreach($name in @('Get-QuietAgentInstruction','Add-QuietAgentInstruction')){
    if(!(Get-Help $name).Synopsis){throw 'AgentProbeHelpMissing'}
}
[Console]::Out.WriteLine('@@AGENT@@'+(ConvertTo-Json @{Success=$true;Module=$core.Path;Hash=$hash;EngineStarted=$false} -Compress))
