#requires -Version 7.6
<#
.SYNOPSIS
Read-only GitHub polling worker, with durable success/failure/cancellation/timeout reports.
.PARAMETER RunId
Existing run identifier.
.PARAMETER Repository
GitHub owner/repository.
.PARAMETER WorkspaceRoot
Project workspace to identify in the monitor.
.PARAMETER RunDirectory
Private status and report directory.
#>
[CmdletBinding(SupportsShouldProcess)]param([long]$RunId,[string]$Repository,[string]$WorkspaceRoot,[string]$RunDirectory)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Invoke-GitHubRunWorker.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptInvokeGitHubRunWorker @PSBoundParameters
