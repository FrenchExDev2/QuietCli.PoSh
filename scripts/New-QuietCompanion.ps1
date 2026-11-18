#requires -Version 7.6
<#
.SYNOPSIS
Creates and registers a new QuietCli companion on a work branch.
.PARAMETER Name
Companion group, for example Packer.
.PARAMETER Executable
Native executable name. Defaults to the lowercase group name.
.PARAMETER NativeLicensePath
UTF-8 Markdown containing the native tool's license references and a level-two heading.
.PARAMETER WorkspaceRoot
QuietCli checkout. Defaults to the checkout containing this script.
.PARAMETER WithCSharp
Adds a parser project targeting .NET 10 and 11.
.PARAMETER GitBranch
Optional branch suffix or complete companion/ branch name.
.PARAMETER NoGitBranch
Keeps an already active companion/ branch without pulling or shelving.
.EXAMPLE
./scripts/New-QuietCompanion.ps1 -Name Packer -NativeLicensePath ./packer-credits.md -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Create')]
param(
    [Parameter(Mandatory)][string]$Name,
    [string]$Executable,
    [Parameter(Mandatory)][Alias('LicenseCreditsPath')][string]$NativeLicensePath,
    [string]$WorkspaceRoot = [IO.Path]::GetDirectoryName($PSScriptRoot),
    [switch]$WithCSharp,
    [Parameter(ParameterSetName='Create')][ValidateNotNullOrEmpty()][string]$GitBranch,
    [Parameter(Mandatory, ParameterSetName='Current')][switch]$NoGitBranch
)

Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/New-QuietCompanion.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptNewQuietCompanion @PSBoundParameters
