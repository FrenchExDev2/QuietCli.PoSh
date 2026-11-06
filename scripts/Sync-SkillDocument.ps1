<#
.SYNOPSIS
Regenerates docs/agents/SKILL.md from docs/agents/AGENTS.md.
.DESCRIPTION
SKILL.md carries the skill front matter plus the AGENTS.md body, byte for byte. Run this after any
change to AGENTS.md. Writes UTF-8 without BOM and LF line endings.
.PARAMETER WorkspaceRoot
QuietCli monorepo root; defaults to the parent of this script directory.
#>
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'AgentDocuments.ps1')
$utf8=[Text.UTF8Encoding]::new($false,$true)
$directory=Join-Path $WorkspaceRoot 'docs/agents'
$agents=[IO.File]::ReadAllTextAsync((Join-Path $directory 'AGENTS.md'),$utf8).GetAwaiter().GetResult()
if(!$agents.Length -or $agents.Contains("`r")){throw 'AgentsDocumentMustBeNonemptyUtf8Lf'}
$skill=New-QuietSkillDocumentText -AgentsText $agents
[void][IO.File]::WriteAllTextAsync((Join-Path $directory 'SKILL.md'),$skill,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
