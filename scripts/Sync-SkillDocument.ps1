<#
.SYNOPSIS
Regenerates docs/agents/SKILL.md from docs/agents/AGENTS.md.
.DESCRIPTION
SKILL.md carries the skill front matter plus the AGENTS.md body, byte for byte. Run this after any
change to AGENTS.md. Writes UTF-8 without BOM and LF line endings.
.PARAMETER WorkspaceRoot
QuietCli monorepo root; defaults to the parent of this script directory.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent))
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Sync-SkillDocument')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/AgentDocuments.psm1')) -DisableNameChecking -ErrorAction Stop
$utf8=[Text.UTF8Encoding]::new($false,$true)
$directory=[IO.Path]::Combine($WorkspaceRoot,'docs/agents')
$agents=[IO.File]::ReadAllTextAsync(([IO.Path]::Combine($directory,'AGENTS.md')),$utf8).GetAwaiter().GetResult()
if(!$agents.Length -or $agents.Contains("`r")){throw 'AgentsDocumentMustBeNonemptyUtf8Lf'}
$skill=New-QuietSkillDocumentText -AgentsText $agents
[void][IO.File]::WriteAllTextAsync(([IO.Path]::Combine($directory,'SKILL.md')),$skill,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
