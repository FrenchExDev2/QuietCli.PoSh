#requires -Version 7.6
<#
.SYNOPSIS
Documentation gate: checks or writes docs/scripts/README.md, the table of contents that links every
script under scripts/ to its documentation file.
.DESCRIPTION
Every script file under scripts/ (*.ps1, *.psm1, recursively) must have a matching Markdown doc
under docs/scripts/, mirroring its subdirectory - scripts/lib/Foo.psm1 is documented at
docs/scripts/lib/Foo.md, scripts/RunProfiles/bar.profile.ps1 at docs/scripts/RunProfiles/bar.profile.md,
and a root scripts/Baz.ps1 at docs/scripts/Baz.md. This script never authors that content itself -
each doc is written by whoever reviews the script - but it is both the gate that fails the moment one
is missing and the generator of docs/scripts/README.md, the navigable index grouping every documented
script by its subdirectory.

Default (no -Apply) mode only reports: it throws ScriptsDocsMissing the moment any script has no doc,
and otherwise throws ScriptsReadmeNonCompliant if docs/scripts/README.md is missing or stale. It never
writes. -Apply regenerates docs/scripts/README.md when stale, honoring -WhatIf/-Confirm through
SupportsShouldProcess - but it still throws ScriptsDocsMissing first: a missing doc is never silently
tolerated, Apply or not, because the index cannot claim full coverage while it is false.
.PARAMETER ScriptsPath
Directory scanned for *.ps1/*.psm1 files, recursively. Defaults to this script's own directory
(scripts/). This script itself is always excluded from the scan.
.PARAMETER DocsPath
Directory the table of contents (README.md) is read from/written to, and under which each script's
mirrored doc is expected. Defaults to docs/scripts under this repository root.
.PARAMETER Apply
Writes docs/scripts/README.md when it is missing or stale. Without this switch the script only
reports and writes nothing.
.EXAMPLE
./scripts/Sync-ScriptsReadme.ps1
Reports documentation-coverage gaps and whether docs/scripts/README.md is up to date; writes nothing.
This is what the check workflow runs.
.EXAMPLE
./scripts/Sync-ScriptsReadme.ps1 -Apply -WhatIf
Previews exactly what -Apply would write, without writing it.
.EXAMPLE
./scripts/Sync-ScriptsReadme.ps1 -Apply
Writes docs/scripts/README.md when it is missing or stale.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ScriptsPath = $PSScriptRoot,
    [string]$DocsPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs/scripts'),
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ScriptsPath)) { throw "ScriptsPathMissing: $ScriptsPath" }

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$selfFullPath = $PSCommandPath
$readmePath = Join-Path $DocsPath 'README.md'

function New-ScriptsDocEntry {
    <#
    .SYNOPSIS
    Builds the doc-coverage entry for one script file: its mirrored doc path and whether it exists.
    .PARAMETER ScriptsRoot
    scripts/ directory the relative paths are computed from.
    .PARAMETER DocsRoot
    docs/scripts directory the mirrored doc is expected under.
    .PARAMETER File
    Script file to evaluate.
    #>
    param(
        [Parameter(Mandatory)][string]$ScriptsRoot,
        [Parameter(Mandatory)][string]$DocsRoot,
        [Parameter(Mandatory)][System.IO.FileInfo]$File
    )
    $scriptRelative = [System.IO.Path]::GetRelativePath($ScriptsRoot, $File.FullName).Replace('\', '/')
    $relativeDir = ([System.IO.Path]::GetDirectoryName($scriptRelative)).Replace('\', '/')
    if ([string]::IsNullOrEmpty($relativeDir)) { $relativeDir = '.' }
    $docRelative = if ($relativeDir -eq '.') { "$($File.BaseName).md" } else { "$relativeDir/$($File.BaseName).md" }
    $docFullPath = Join-Path $DocsRoot ($docRelative.Replace('/', [IO.Path]::DirectorySeparatorChar))
    [pscustomobject]@{
        ScriptRelative = $scriptRelative
        Group          = $relativeDir
        DocRelative    = $docRelative
        DocFullPath    = $docFullPath
        DocExists      = Test-Path -LiteralPath $docFullPath
    }
}

function New-ScriptsReadmeCreditsBlock {
    <#
    .SYNOPSIS
    Builds the same regex-identifiable credits block Sync-DocsCredits.ps1 expects, so the generated
    README never fights that script's own stale-check.
    .PARAMETER DocsRoot
    docs/scripts directory the generated README lives in.
    #>
    param([Parameter(Mandatory)][string]$DocsRoot)
    $moduleRoot = Split-Path (Split-Path $DocsRoot -Parent) -Parent
    $creditsPath = Join-Path $moduleRoot 'CREDITS.md'
    $creditsRelative = [System.IO.Path]::GetRelativePath($DocsRoot, $creditsPath).Replace('\', '/')
    $lines = @(
        '<!-- credits:begin -->',
        '## Credits',
        '',
        "This document is covered by the mandatory [CREDITS.md]($creditsRelative), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).",
        '<!-- credits:end -->'
    )
    return ($lines -join "`n")
}

function New-ScriptsReadmeContent {
    <#
    .SYNOPSIS
    Renders the full docs/scripts/README.md content for a fully-documented set of entries.
    .PARAMETER Entries
    Doc-coverage entries, as produced by New-ScriptsDocEntry; every one must have DocExists = $true.
    .PARAMETER ScriptsRoot
    scripts/ directory the script links are computed relative to.
    .PARAMETER DocsRoot
    docs/scripts directory the generated README lives in.
    #>
    param(
        [Parameter(Mandatory)][object[]]$Entries,
        [Parameter(Mandatory)][string]$ScriptsRoot,
        [Parameter(Mandatory)][string]$DocsRoot
    )
    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add('# Scripts documentation index')
    [void]$lines.Add('')
    [void]$lines.Add('Generated by [`Sync-ScriptsReadme.ps1`](../../scripts/Sync-ScriptsReadme.ps1): every script under')
    [void]$lines.Add('`scripts/` must have a matching doc here before this index can be regenerated - that')
    [void]$lines.Add('requirement is the gate the same script enforces. See')
    [void]$lines.Add('[README-scripts-have-docs.md](../README-scripts-have-docs.md) for the why/how. Do not edit this')
    [void]$lines.Add('file by hand, run:')
    [void]$lines.Add('')
    [void]$lines.Add('```powershell')
    [void]$lines.Add('./scripts/Sync-ScriptsReadme.ps1 -Apply')
    [void]$lines.Add('```')
    [void]$lines.Add('')

    $groups = @($Entries | Group-Object Group | Sort-Object @{ Expression = { if ($_.Name -eq '.') { '' } else { $_.Name } } })
    foreach ($group in $groups) {
        $heading = if ($group.Name -eq '.') { 'Root scripts' } else { "``scripts/$($group.Name)/``" }
        [void]$lines.Add("## $heading")
        [void]$lines.Add('')
        foreach ($entry in @($group.Group | Sort-Object ScriptRelative)) {
            $scriptFullPath = Join-Path $ScriptsRoot ($entry.ScriptRelative.Replace('/', [IO.Path]::DirectorySeparatorChar))
            $scriptLink = ([System.IO.Path]::GetRelativePath($DocsRoot, $scriptFullPath)).Replace('\', '/')
            [void]$lines.Add("- [``$($entry.ScriptRelative)``]($scriptLink) -> [documentation]($($entry.DocRelative))")
        }
        [void]$lines.Add('')
    }

    [void]$lines.Add((New-ScriptsReadmeCreditsBlock -DocsRoot $DocsRoot))
    return (($lines -join "`n").TrimEnd("`n") + "`n")
}

$scriptFiles = @(
    Get-ChildItem -LiteralPath $ScriptsPath -Recurse -File -Include '*.ps1', '*.psm1' |
        Where-Object { $_.FullName -ne $selfFullPath } |
        Sort-Object FullName
)

$entries = @($scriptFiles | ForEach-Object { New-ScriptsDocEntry -ScriptsRoot $ScriptsPath -DocsRoot $DocsPath -File $_ })

$missing = @($entries | Where-Object { -not $_.DocExists })
if ($missing.Count -gt 0) {
    $list = ($missing | ForEach-Object { $_.ScriptRelative }) -join '; '
    throw "ScriptsDocsMissing: $($missing.Count) script(s) have no doc under $DocsPath -> $list"
}

$expectedContent = New-ScriptsReadmeContent -Entries $entries -ScriptsRoot $ScriptsPath -DocsRoot $DocsPath
$currentContent = if (Test-Path -LiteralPath $readmePath) {
    [IO.File]::ReadAllTextAsync($readmePath, $utf8NoBom).GetAwaiter().GetResult()
} else {
    $null
}

$state = if ($null -eq $currentContent) { 'Missing' }
         elseif ($currentContent.Replace("`r`n", "`n") -ne $expectedContent) { 'Stale' }
         else { 'UpToDate' }

if ($state -ne 'UpToDate' -and $Apply -and $PSCmdlet.ShouldProcess($readmePath, "Write scripts README ($state)")) {
    if (-not (Test-Path -LiteralPath $DocsPath)) { New-Item -ItemType Directory -Path $DocsPath -Force | Out-Null }
    [void][IO.File]::WriteAllTextAsync($readmePath, $expectedContent, $utf8NoBom).GetAwaiter().GetResult()
    $state = "$state (Applied)"
}

[pscustomobject]@{ Path = $readmePath; State = $state; DocumentedScriptCount = $entries.Count }

if ($state -notin 'UpToDate' -and $state -notlike '* (Applied)') {
    throw "ScriptsReadmeNonCompliant: $readmePath ($state)"
}
