#requires -Version 7.6
<#
.SYNOPSIS
Generates or checks the Markdown reference for the registered Git command forms.
.PARAMETER OutputPath
Markdown destination. Defaults to the tracked documentation under docs/.
.PARAMETER Check
Require the destination to match the generated UTF-8/LF content without writing.
.EXAMPLE
./src/Git/scripts/Export-GitCommandReference.ps1
.EXAMPLE
./src/Git/scripts/Export-GitCommandReference.ps1 -Check
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateNotNullOrEmpty()][string]$OutputPath = [IO.Path]::GetFullPath('../../../docs/README-git-command-reference.md', $PSScriptRoot),
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if ([IO.Path]::GetExtension($target) -ine '.md') { throw 'GitReferenceOutputMustBeMarkdown' }
Import-Module ([IO.Path]::Combine($PSScriptRoot, 'lib/GitCommandReference.psm1')) -DisableNameChecking -ErrorAction Stop
$moduleDirectory = [IO.Path]::GetFullPath('../src/FrenchExDev2.QuietCli.Git.PoSh', $PSScriptRoot)
$guidance = [IO.Path]::Combine($PSScriptRoot, 'GitCommandReference.json')
$markdown = Get-QuietGitCommandReference -ModuleDirectory $moduleDirectory -GuidancePath $guidance
$utf8 = [Text.UTF8Encoding]::new($false, $true)

if ([IO.File]::Exists($target) -and $markdown.Equals($utf8.GetString([IO.File]::ReadAllBytes($target)), [StringComparison]::Ordinal)) {
    return
}
if ($Check) { throw ('GitCommandReferenceStale: ' + $target) }
if (!$PSCmdlet.ShouldProcess($target, 'Write the Git command reference')) { return }

$directory = [IO.Path]::GetDirectoryName($target)
$temporary = [IO.Path]::Combine($directory, '.git-command-reference-' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
    [IO.File]::WriteAllText($temporary, $markdown, $utf8)
    [IO.File]::Move($temporary, $target, $true)
} finally {
    [IO.File]::Delete($temporary)
}
