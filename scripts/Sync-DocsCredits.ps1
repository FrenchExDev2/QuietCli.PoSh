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
    [string]$DocsPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs'),
    [string]$RootPath = (Split-Path $PSScriptRoot -Parent),
    [string]$CreditsPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'CREDITS.md'),
    [switch]$NoRecurse,
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'

$beginMarker = '<!-- credits:begin -->'
$endMarker = '<!-- credits:end -->'
$blockRegex = [System.Text.RegularExpressions.Regex]::new(
    [regex]::Escape($beginMarker) + '.*?' + [regex]::Escape($endMarker),
    [System.Text.RegularExpressions.RegexOptions]::Singleline)

if (-not (Test-Path -LiteralPath $DocsPath)) { throw "DocsPathMissing: $DocsPath" }
if (-not (Test-Path -LiteralPath $RootPath)) { throw "RootPathMissing: $RootPath" }
if (-not (Test-Path -LiteralPath $CreditsPath)) { throw "CreditsFileMissing: $CreditsPath" }
$creditsFullPath = (Resolve-Path -LiteralPath $CreditsPath).Path
$creditsName = Split-Path -Leaf $CreditsPath

function New-CreditsBlock {
    <#
    .SYNOPSIS
    Builds the regex-identifiable credits block for one docs/*.md file.
    .PARAMETER RelativePath
    Relative credits path, or the public absolute URL for distributed agent documents.
    #>
    param([Parameter(Mandatory)][string]$RelativePath)
    $lines = @(
        $beginMarker,
        '## Credits',
        '',
        "This document is covered by the mandatory [CREDITS.md]($RelativePath), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).",
        $endMarker
    )
    return ($lines -join "`n")
}

$files = @(
    Get-ChildItem -LiteralPath $DocsPath -Filter '*.md' -File -Recurse:(-not $NoRecurse)
    Get-ChildItem -LiteralPath $RootPath -Filter 'README*.md' -File
) | Where-Object { $_.FullName -ne $creditsFullPath } | Sort-Object FullName -Unique

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$portableAgentDocs = @('agents/AGENTS.md', 'agents/SKILL.md') | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $DocsPath $_)) }
$report = foreach ($file in $files) {
    $relativeDir = [System.IO.Path]::GetRelativePath($file.DirectoryName, (Split-Path -Parent $creditsFullPath)) -replace '\\', '/'
    $creditsRelative = if ($relativeDir -eq '.') { $creditsName } else { $relativeDir.TrimEnd('/') + '/' + $creditsName }
    $creditsTarget = if ($file.FullName -in $portableAgentDocs) {
        'https://github.com/FrenchExDev2/FrenchExDev2.QuietCli.PoSh/blob/HEAD/CREDITS.md'
    } else { $creditsRelative }
    $expectedBlock = New-CreditsBlock -RelativePath $creditsTarget

    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $match = $blockRegex.Match($content)
    $state = if (-not $match.Success) { 'Missing' }
             elseif ($match.Value.Trim() -ne $expectedBlock.Trim()) { 'Stale' }
             else { 'UpToDate' }

    if ($state -ne 'UpToDate' -and $Apply -and $PSCmdlet.ShouldProcess($file.FullName, "Write credits block ($state)")) {
        $newContent = if ($match.Success) {
            $content.Substring(0, $match.Index) + $expectedBlock + $content.Substring($match.Index + $match.Length)
        } else {
            $content.TrimEnd("`r", "`n") + "`n`n" + $expectedBlock + "`n"
        }
        [void][System.IO.File]::WriteAllTextAsync($file.FullName, $newContent, $utf8NoBom).GetAwaiter().GetResult()
        $state = "$state (Applied)"
    }

    [pscustomobject]@{ Path = $file.FullName; State = $state }
}

$report
$nonCompliant = $report | Where-Object { $_.State -notin 'UpToDate' -and $_.State -notlike '* (Applied)' }
if ($nonCompliant) {
    throw ('DocsCreditsNonCompliant: ' + (($nonCompliant | ForEach-Object { "$($_.Path) ($($_.State))" }) -join '; '))
}
