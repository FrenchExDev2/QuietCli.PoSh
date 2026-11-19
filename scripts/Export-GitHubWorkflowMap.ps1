#requires -Version 7.6
<#
.SYNOPSIS
Exports a navigable Markdown map of GitHub Actions triggers, jobs and local calls.
.PARAMETER WorkspaceRoot
Checkout containing .github/workflows and optionally .github/actions.
.PARAMETER OutputPath
Destination Markdown file. Defaults to artifacts/github-workflows.md under WorkspaceRoot.
.EXAMPLE
./scripts/Export-GitHubWorkflowMap.ps1
.EXAMPLE
./scripts/Export-GitHubWorkflowMap.ps1 -OutputPath ./artifacts/ci-map.md -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WorkspaceRoot = ([IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))),
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkspaceRoot)
$destination = if ($OutputPath) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
} else {
    [IO.Path]::Combine($root,'artifacts','github-workflows.md')
}
if ([IO.Path]::GetExtension($destination) -ine '.md') { throw 'WorkflowMapOutputMustBeMarkdown' }
if (!$PSCmdlet.ShouldProcess($destination,'Write GitHub Actions Markdown map')) { return }

Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/GitHubWorkflowMap.psm1')) -DisableNameChecking -ErrorAction Stop
$report = New-QuietGitHubWorkflowMap -WorkspaceRoot $root -OutputPath $destination
$directory = [IO.Path]::GetDirectoryName($destination)
[void][IO.Directory]::CreateDirectory($directory)
$temporary = [IO.Path]::Combine($directory,'.workflow-map-'+[guid]::NewGuid().ToString('N')+'.tmp')
try {
    [IO.File]::WriteAllText($temporary,$report.Markdown,[Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temporary,$destination,$true)
} finally {
    [IO.File]::Delete($temporary)
}
[pscustomobject]@{ Path = $destination; Workflows = $report.Workflows; Actions = $report.Actions }
