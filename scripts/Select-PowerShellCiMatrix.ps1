#requires -Version 7.6
<#
.SYNOPSIS
Writes the lock-derived Windows matrix and exact required profile count, with optional preview.
.PARAMETER WorkspaceRoot
Checkout supplying the reviewed PowerShell host lock.
.PARAMETER IncludePreview
Explicitly request the published next-version preview; missing archives fail closed.
.PARAMETER OutputPath
GitHub output file receiving windows_matrix and expected_reports.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$IncludePreview,[Parameter(Mandatory)][string]$OutputPath)
if(!$PSCmdlet.ShouldProcess($OutputPath,'Resolve and write the native Windows host matrix')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/GitHubCi.psm1')) -DisableNameChecking -ErrorAction Stop
$lock=Get-Content -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'build/powershell-hosts.lock.json')) -Raw -Encoding utf8|ConvertFrom-Json
$selection=Get-GitHubCiWindowsMatrix -HostLock $lock -IncludePreview:([bool]$IncludePreview)
$matrix=$selection.Matrix|ConvertTo-Json -Depth 6 -Compress
[IO.File]::AppendAllText([IO.Path]::GetFullPath($OutputPath,$PWD.Path),"windows_matrix=$matrix`nexpected_reports=$($selection.ExpectedReports)`n",[Text.UTF8Encoding]::new($false))
$selection
