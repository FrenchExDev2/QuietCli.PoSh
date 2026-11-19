#requires -Version 7.6
<#
.SYNOPSIS
Exports the QuietCli SQLite schema and source SQL to a Markdown document.
.PARAMETER DatabasePath
Optional QuietCli database to inspect read-only. By default, use a disposable database initialized from the checkout.
.PARAMETER OutputPath
Destination Markdown file. Defaults to docs/README-sqlite-schema-and-queries.md in this checkout.
.EXAMPLE
./scripts/Export-SqliteDocumentation.ps1
.EXAMPLE
./scripts/Export-SqliteDocumentation.ps1 -DatabasePath ./history.sqlite -OutputPath ./schema.md -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DatabasePath,
    [ValidateNotNullOrEmpty()][string]$OutputPath = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, '../docs/README-sqlite-schema-and-queries.md'))
)

$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetDirectoryName($PSScriptRoot)
$target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$database = if ($DatabasePath) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DatabasePath) }
if ($PSCmdlet.ShouldProcess($target, 'Export SQLite schema and source queries')) {
    Import-Module ([IO.Path]::Combine($PSScriptRoot, 'lib/SqliteDocumentation.psm1')) -DisableNameChecking -ErrorAction Stop
    Export-QuietSqliteDocumentation -WorkspaceRoot $workspace -OutputPath $target -DatabasePath $database -Confirm:$false
}
