#requires -Version 7.6
<#
.SYNOPSIS
Builds the root CREDITS.md file by aggregating every business module's LICENSE_CREDITS.md.
.DESCRIPTION
Part of the module contract: every business module discovered by Get-QuietWorkspaceProjects
(Core, Git, Vagrant - never a .Tests companion) must ship its own LICENSE_CREDITS.md declaring
the third-party license(s) its native dependency uses, with reference links. The generated file
opens with a table of contents linking each module's heading, so it stays navigable as new
business modules are added. This script never reads CREDITS.md as a source; it always
recomputes it from the modules and compares. Default (no
-Apply) mode only reports each module's and the root file's compliance state and writes nothing.
-Apply writes the regenerated CREDITS.md, honoring -WhatIf/-Confirm through SupportsShouldProcess.
-Apply -WhatIf previews exactly what -Apply would write.
.PARAMETER WorkspaceRoot
Monorepo containing the immediate FrenchExDev2.QuietCli.*.PoSh project directories. Defaults to
this script's workspace root.
.PARAMETER CreditsPath
Path to the generated CREDITS.md file. Defaults to CREDITS.md at the workspace root.
.PARAMETER Apply
Writes the regenerated CREDITS.md when it is missing or stale. Without this switch the script
only reports; it never writes.
.EXAMPLE
./scripts/Sync-Credits.ps1
Reports whether every business module ships LICENSE_CREDITS.md and whether CREDITS.md matches.
.EXAMPLE
./scripts/Sync-Credits.ps1 -Apply -WhatIf
Previews exactly what -Apply would write to CREDITS.md, without writing it.
.EXAMPLE
./scripts/Sync-Credits.ps1 -Apply
Regenerates CREDITS.md from every business module's LICENSE_CREDITS.md.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WorkspaceRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$CreditsPath = ([IO.Path]::Combine((Split-Path $PSScriptRoot -Parent),'CREDITS.md')),
    [switch]$Apply
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Sync-Credits.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptSyncCredits @PSBoundParameters
