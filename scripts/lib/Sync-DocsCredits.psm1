function Invoke-QuietScriptSyncDocsCredits {
#requires -Version 7.6
<#
.SYNOPSIS
Checks or writes the mandatory CREDITS.md paragraph in docs, root READMEs and readmes/ guides.
.DESCRIPTION
Every docs/**/*.md file (recursively, by default), root README*.md and readmes/README-*.md file must
end with a regex-identifiable block, surrounded by <!-- credits:begin --> / <!-- credits:end -->
markers, linking the mandatory CREDITS.md file. Default (no -Apply) mode only reports each file's
compliance state and writes nothing. -Apply writes the missing or stale block into every
non-compliant file, honoring -WhatIf/-Confirm through SupportsShouldProcess. -Apply -WhatIf
previews exactly what -Apply would write. Existing generated blocks are replaced by one footer
at the end of the file, preserving the Markdown around them.
The distributed docs/agents/AGENTS.md and SKILL.md use the public absolute credits URL because
they must remain self-contained when copied into consumer projects; other docs use relative links.
.PARAMETER DocsPath
Documentation directory scanned for *.md files. Defaults to docs under this repository root.
Every docs/**/*.md file is scanned by default, including the agents, audits and ci subfolders; use
-NoRecurse to check only its direct children.
.PARAMETER RootPath
Repository root scanned for README*.md files and readmes/README-*.md guides. Defaults to this
script's workspace root.
.PARAMETER CreditsPath
Path to the mandatory CREDITS.md file. Defaults to CREDITS.md at this repository root.
.PARAMETER NoRecurse
Checks only the direct children of docs/*.md, skipping the agents, audits and ci subfolders.
.PARAMETER Apply
Writes the missing or stale credits block into each non-compliant file. Without this switch the
script only reports; it never writes.
.EXAMPLE
./scripts/Sync-DocsCredits.ps1
Reports the compliance state of every covered Markdown file without writing.
.EXAMPLE
./scripts/Sync-DocsCredits.ps1 -Apply -WhatIf
Previews exactly which files -Apply would write and why, without writing them.
.EXAMPLE
./scripts/Sync-DocsCredits.ps1 -Apply
Writes the missing or stale credits block into every non-compliant file.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DocsPath = ([IO.Path]::Combine((Split-Path ([IO.Path]::GetDirectoryName($PSScriptRoot)) -Parent),'docs')),
    [string]$RootPath = (Split-Path ([IO.Path]::GetDirectoryName($PSScriptRoot)) -Parent),
    [string]$CreditsPath = ([IO.Path]::Combine((Split-Path ([IO.Path]::GetDirectoryName($PSScriptRoot)) -Parent),'CREDITS.md')),
    [switch]$NoRecurse,
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $DocsPath)) { throw "DocsPathMissing: $DocsPath" }
if (-not (Test-Path -LiteralPath $RootPath)) { throw "RootPathMissing: $RootPath" }
if (-not (Test-Path -LiteralPath $CreditsPath)) { throw "CreditsFileMissing: $CreditsPath" }
$creditsFullPath = (Resolve-Path -LiteralPath $CreditsPath).Path
$creditsName = Split-Path -Leaf $CreditsPath

$files = @(
    Get-ChildItem -LiteralPath $DocsPath -Filter '*.md' -File -Recurse:(-not $NoRecurse)
    Get-ChildItem -LiteralPath $RootPath -Filter 'README*.md' -File
    Get-QuietReadmeGuideFiles -RootPath $RootPath
) | Where-Object { $_.FullName -ne $creditsFullPath } | Sort-Object FullName -Unique

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$portableAgentDocs = @('agents/AGENTS.md', 'agents/SKILL.md') | ForEach-Object { [IO.Path]::GetFullPath(([IO.Path]::Combine($DocsPath,$_))) }
$report = foreach ($file in $files) {
    $relativeDir = [System.IO.Path]::GetRelativePath($file.DirectoryName, (Split-Path -Parent $creditsFullPath)) -replace '\\', '/'
    $creditsRelative = if ($relativeDir -eq '.') { $creditsName } else { $relativeDir.TrimEnd('/') + '/' + $creditsName }
    $creditsTarget = if ($file.FullName -in $portableAgentDocs) {
        'https://github.com/FrenchExDev2/QuietCli.PoSh/blob/HEAD/CREDITS.md'
    } else { $creditsRelative }
    $content = [IO.File]::ReadAllTextAsync($file.FullName, $utf8NoBom).GetAwaiter().GetResult()
    $lineEnding = [regex]::Match($content, '\r?\n').Value
    if (!$lineEnding) { $lineEnding = "`n" }
    $expectedBlock = (Format-QuietDocsCreditsBlock -Link $creditsTarget).Replace("`n", $lineEnding)
    $blocks = @(Get-QuietDocsCreditsBlocks -Content $content)
    $state = if ($blocks.Count -eq 0) { 'Missing' }
             elseif ($blocks.Count -ne 1 -or $content.Substring($blocks[0].Index).TrimEnd() -cne $expectedBlock) { 'Stale' }
             else { 'UpToDate' }

    if ($state -ne 'UpToDate' -and $Apply -and $PSCmdlet.ShouldProcess($file.FullName, "Write credits block ($state)")) {
        foreach ($block in ($blocks | Sort-Object Index -Descending)) {
            $content = $content.Remove($block.Index, $block.Length)
        }
        $body = $content.TrimEnd("`r", "`n")
        if ($body.Length) { $body += $lineEnding + $lineEnding }
        $newContent = $body + $expectedBlock + $lineEnding
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

}

function Get-QuietDocsCreditsBlocks {
    <#
    .SYNOPSIS
    Finds complete top-level credits blocks and their trailing separator.
    .PARAMETER Content
    Markdown source. Literal markers in code examples and inline text are ignored.
    #>
    param([string]$Content)

    $start = $null
    $separatorPattern = [regex]::new('\G(?:\r?\n){0,2}')
    $document = [Markdig.Markdown]::Parse($Content)
    foreach ($node in [Linq.Enumerable]::OfType[Markdig.Syntax.HtmlBlock]($document)) {
        $marker = $Content.Substring($node.Span.Start, $node.Span.Length).TrimEnd()
        if ($marker -ceq '<!-- credits:begin -->') {
            $start = $node.Span.Start
        } elseif ($marker -ceq '<!-- credits:end -->' -and $null -ne $start) {
            $separator = $separatorPattern.Match($Content, $node.Span.End + 1)
            [pscustomobject]@{ Index = $start; Length = $separator.Index + $separator.Length - $start }
            $start = $null
        }
    }
}

function Format-QuietDocsCreditsBlock {
    <#
    .SYNOPSIS
    Formats the repository's standard Markdown credits block with LF line endings.
    .PARAMETER Link
    Markdown link destination for CREDITS.md, relative to the document or absolute.
    #>
    param([Parameter(Mandatory)][string]$Link)

    @(
        '<!-- credits:begin -->',
        '## Credits',
        '',
        "This document is covered by the mandatory [CREDITS.md]($Link), which records the licenses of all softwares which have QuietCli companions",
        '<!-- credits:end -->'
    ) -join "`n"
}

function Get-QuietReadmeGuideFiles {
    <#
    .SYNOPSIS
    Finds the README guides directly under the workspace readmes directory.
    .PARAMETER RootPath
    Workspace containing the optional readmes directory.
    #>
    param([string]$RootPath)
    $readmesPath = [IO.Path]::Combine($RootPath, 'readmes')
    if (Test-Path -LiteralPath $readmesPath -PathType Container) {
        Get-ChildItem -LiteralPath $readmesPath -Filter 'README-*.md' -File
    }
}

Export-ModuleMember -Function 'Invoke-QuietScriptSyncDocsCredits','Format-QuietDocsCreditsBlock'
