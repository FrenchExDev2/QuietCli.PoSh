#requires -Version 7.6
<#
.SYNOPSIS
Checks and applies NuGet updates for Directory.Packages.props per package and target framework, honoring CPM conditions.
.DESCRIPTION
Every tracked project is evaluated by MSBuild once per target framework, so each PackageVersion
Condition is resolved exactly as restore resolves it. Each resulting package x framework row is
checked against nuget.org: a newer version is proposed only if its catalog assets (lib/, ref/,
runtimes/*/lib/, else its dependency groups) are compatible with that framework. An element used
by several frameworks receives the highest version compatible with all of them.
Without -Apply the updates are listed and chosen interactively. -WhatIf runs the whole analysis,
selects every compatible update and prints it without prompting or writing. -Apply writes the
selected versions, then runs dotnet restore on the referencing projects and restores the original
file if restore fails (for example NU1202). In GitHub Actions the table is also appended to the job
summary.
.PARAMETER WorkspaceRoot
Repository whose tracked .csproj files are evaluated. Defaults to this script's workspace root.
.PARAMETER PropsPath
Central package management file to update. Defaults to Directory.Packages.props at WorkspaceRoot.
.PARAMETER Apply
Applies every compatible update without prompting.
.PARAMETER IncludePrerelease
Also proposes pre-release versions (always the case for a package already pinned to a pre-release).
.PARAMETER ParallelMax
Maximum number of concurrent MSBuild evaluations and nuget.org requests.
.PARAMETER NoRestore
Skips the dotnet restore check after writing.
.EXAMPLE
./scripts/Update-Packages.ps1 -WhatIf
Shows every package x framework row and the updates that would be written, without prompting or writing.
.EXAMPLE
./scripts/Update-Packages.ps1
Lists the compatible updates and asks which ones to write.
.EXAMPLE
./scripts/Update-Packages.ps1 -Apply
Writes every compatible update, then checks it with dotnet restore.
.EXAMPLE
./scripts/Update-Packages.ps1 -Apply -IncludePrerelease -ParallelMax 8
Also considers pre-release versions, with more concurrent requests.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WorkspaceRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$PropsPath = '',
    [switch]$Apply,
    [switch]$IncludePrerelease,
    [ValidateRange(1, 32)][int]$ParallelMax = 4,
    [switch]$NoRestore
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Update-Packages.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptUpdatePackages @PSBoundParameters
