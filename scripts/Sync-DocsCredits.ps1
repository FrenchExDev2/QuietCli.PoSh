#requires -Version 7.6
<#
.SYNOPSIS
Checks or writes the mandatory CREDITS.md credits paragraph at the end of every docs/**/*.md and
root README*.md file.
.DESCRIPTION
Every docs/**/*.md file (recursively, by default) and every root README.md/README-*.md file must
end with a regex-identifiable block, surrounded by <!-- credits:begin --> / <!-- credits:end -->
markers, linking the mandatory CREDITS.md file. Default (no -Apply) mode only reports each file's
compliance state and writes nothing. -Apply writes the missing or stale block into every
non-compliant file, honoring -WhatIf/-Confirm through SupportsShouldProcess. -Apply -WhatIf
previews exactly what -Apply would write.
The distributed docs/agents/AGENTS.md and SKILL.md use the public absolute credits URL because
they must remain self-contained when copied into consumer projects; other docs use relative links.
.PARAMETER DocsPath
Documentation directory scanned for *.md files. Defaults to docs under this repository root.
Every docs/**/*.md file is scanned by default, including the agents, audits and ci subfolders; use
-NoRecurse to check only its direct children.
.PARAMETER RootPath
Repository root scanned for README.md and README-*.md files. Defaults to this script's
workspace root. Only its direct children are scanned; subdirectories (docs included) are never
matched by this pattern.
.PARAMETER CreditsPath
Path to the mandatory CREDITS.md file. Defaults to CREDITS.md at this repository root.
.PARAMETER NoRecurse
Checks only the direct children of docs/*.md, skipping the agents, audits and ci subfolders.
.PARAMETER Apply
Writes the missing or stale credits block into each non-compliant file. Without this switch the
script only reports; it never writes.
.EXAMPLE
./scripts/Sync-DocsCredits.ps1
Reports the compliance state of every docs/*.md and root README*.md file without writing.
.EXAMPLE
./scripts/Sync-DocsCredits.ps1 -Apply -WhatIf
Previews exactly which files -Apply would write and why, without writing them.
.EXAMPLE
./scripts/Sync-DocsCredits.ps1 -Apply
Writes the missing or stale credits block into every non-compliant file.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DocsPath = ([IO.Path]::Combine((Split-Path $PSScriptRoot -Parent),'docs')),
    [string]$RootPath = (Split-Path $PSScriptRoot -Parent),
    [string]$CreditsPath = ([IO.Path]::Combine((Split-Path $PSScriptRoot -Parent),'CREDITS.md')),
    [switch]$NoRecurse,
    [switch]$Apply
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Sync-DocsCredits.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptSyncDocsCredits @PSBoundParameters
