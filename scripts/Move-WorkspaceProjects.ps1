#requires -Version 7.6
<#
.SYNOPSIS
Migrates flat workspace modules to grouped src/test directories.
.PARAMETER WorkspaceRoot
Selected checkout; defaults to this script's repository.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent))
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,'Migrate workspace projects and repair references')){return}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/WorkspaceLayout.psm1')) -DisableNameChecking -ErrorAction Stop
Move-QuietWorkspaceProjects -WorkspaceRoot $WorkspaceRoot -WhatIf:$WhatIfPreference -Confirm:$false
Repair-QuietWorkspaceReferences -WorkspaceRoot $WorkspaceRoot -WhatIf:$WhatIfPreference -Confirm:$false
