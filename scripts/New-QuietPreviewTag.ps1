#requires -Version 7.6
<#
.SYNOPSIS
Creates a local annotated preview tag using the current Core manifest version and a UTC timestamp.
.DESCRIPTION
Tags the exact HEAD observed in a clean QuietCli2 repository. Never commits, pushes,
publishes, changes manifests or replaces a tag. WhatIf also permits a dirty checkout
to inspect the proposed name; creation requires committing changes first.
.PARAMETER WorkspaceRoot
QuietCli2 repository root; defaults to this script's checkout, independently of the current directory.
.PARAMETER Timestamp
Optional reproducible instant; defaults to the current UTC time at invocation.
.EXAMPLE
./scripts/New-QuietPreviewTag.ps1 -WhatIf
.EXAMPLE
$tag = ./scripts/New-QuietPreviewTag.ps1
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$WorkspaceRoot = (Split-Path $PSScriptRoot -Parent),
    [DateTimeOffset]$Timestamp = [DateTimeOffset]::UtcNow
)
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path $PSScriptRoot -Parent
foreach ($component in @('Core', 'Git')) {
    $name = "FrenchExDev2.QuietCli.$component.PoSh"
    $path = Join-Path $sourceRoot "$name/$name.psm1"
    $loaded = Get-Module -Name $name
    if ($loaded -and @($loaded | Where-Object { ![StringComparer]::OrdinalIgnoreCase.Equals($_.Path, $path) }).Count) {
        throw "PreviewTagUnexpectedModulePath: $name; start a fresh PowerShell session."
    }
    if (!$loaded) { Import-Module (Join-Path $sourceRoot "$name/$name.psd1") -ErrorAction Stop }
    if (![StringComparer]::OrdinalIgnoreCase.Equals((Get-Module -Name $name).Path, $path)) {
        throw "PreviewTagUnexpectedModulePath: $name"
    }
}
Import-Module (Join-Path $PSScriptRoot 'lib/PreviewTag.psm1') -Force
$WorkspaceRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($WorkspaceRoot, $PWD.Path))

function Invoke-QuietPreviewGit {
    <#
    .SYNOPSIS
    Runs one explicit Git operation, retaining only its first bounded value and output presence.
    .PARAMETER Arguments
    Exact native arguments; no shell expansion or implicit retries.
    #>
    param([string[]]$Arguments)
    $result = quiet -AsObject -C preview-tag -WorkingDirectory $WorkspaceRoot -RecordDelimiter "`n" `
        -Data @{ Value = ''; HasOutput = $false } -Output {
            param($event, $runtime)
            if ($event.Stream -ne 'stdout') { return }
            $line = $event.Text.TrimEnd([char[]]"`r`n")
            if (!$line.Length) { return }
            if (!$runtime.Data.HasOutput) {
                if ($line.Length -gt 4096) { throw 'PreviewTagValueTooLong' }
                $runtime.Data.Value = $line
            }
            $runtime.Data.HasOutput = $true
        } -Complete { param($runtime) $runtime.Data } -FilePath git -ArgumentList $Arguments
    if ($result.Outcome -ne 'Success' -or $result.Execution.Native.ExitCode -ne 0 -or
        !$result.Completeness.Source -or !$result.Completeness.Analysis -or @($result.Error).Count) {
        throw "PreviewTagGitFailed: $($Arguments[0]); $($result.Outcome). No retry was attempted."
    }
    return $result.Data
}

$repository = (Invoke-QuietPreviewGit @('rev-parse', '--show-toplevel')).Value
$comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
if (!$WorkspaceRoot.Equals([IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($repository)), $comparison)) {
    throw 'PreviewTagWorkspaceMustBeRepositoryRoot'
}
$manifestPath = Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1'
$version = [string](Import-PowerShellDataFile -LiteralPath $manifestPath).ModuleVersion
$tag = New-QuietPreviewTagName -Version $version -Timestamp $Timestamp
$revision = (Invoke-QuietPreviewGit @('rev-parse', '--verify', 'HEAD^{commit}')).Value
if ($revision -cnotmatch '^(?:[a-f0-9]{40}|[a-f0-9]{64})\z') { throw 'PreviewTagInvalidRevision' }
$clean = !(Invoke-QuietPreviewGit @('status', '--porcelain=v1', '--untracked-files=normal')).HasOutput
$existing = Invoke-QuietPreviewGit @('tag', '--list', $tag)
if ($existing.HasOutput) { throw "PreviewTagAlreadyExists: $tag" }
$created = $false
if ($PSCmdlet.ShouldProcess("$WorkspaceRoot @ $revision", "Create annotated tag $tag")) {
    if (!$clean) { throw 'PreviewTagDirtyCheckout: commit changes before tagging HEAD.' }
    $null = Invoke-QuietPreviewGit @('-c', 'tag.gpgSign=false', 'tag', '--annotate', '--message', "QuietCli $version preview ($($Timestamp.ToUniversalTime().ToString('o')))", '--', $tag, $revision)
    $created = $true
}
[pscustomobject]@{
    Tag = $tag
    Version = $version
    TimestampUtc = $Timestamp.ToUniversalTime()
    Revision = $revision
    WorkspaceRoot = $WorkspaceRoot
    ManifestPath = $manifestPath
    Clean = $clean
    Created = $created
}
