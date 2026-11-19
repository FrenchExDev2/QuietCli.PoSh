#requires -Version 7.6
<#
.SYNOPSIS
Writes the local working-tree CI plan outputs to a file.
.PARAMETER Base
Full SHA of the comparison base. Defaults to git merge-base origin/develop HEAD in this checkout.
.PARAMETER OutputPath
Destination file. Relative paths are resolved from the current location. Defaults to a new temporary file.
.PARAMETER GetContent
Returns the UTF-8 lines of the generated file.
.PARAMETER Open
Opens the generated file in VS Code Insiders, falling back to VS Code.
.EXAMPLE
./scripts/New-CiImpactPlanFile.ps1 -OutputPath ./artifacts/ci-plan/outputs.txt -GetContent
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Base,
    [Parameter(Position = 1)][Alias('Output')][ValidateNotNullOrWhiteSpace()][string]$OutputPath,
    [switch]$GetContent,
    [switch]$Open
)
$ErrorActionPreference = 'Stop'
$destination = if ($OutputPath) { [IO.Path]::GetFullPath($OutputPath, $PWD.ProviderPath) }
$target = if ($destination) { $destination } else { 'a new temporary file' }
if (!$PSCmdlet.ShouldProcess($target, 'Generate the local CI impact plan file')) { return }

if (!$Base) {
    Import-Module ([IO.Path]::Combine($PSScriptRoot, 'lib/Ci.Process.psm1')) -DisableNameChecking -ErrorAction Stop
    $baseState = @{ Lines = [Collections.Generic.List[string]]::new() }
    $baseResult = Invoke-CiProcess -FilePath git -ArgumentList @('merge-base', 'origin/develop', 'HEAD') -WorkingDirectory (Split-Path $PSScriptRoot -Parent) -State $baseState -OnOutput {
        param($record, $state)
        if ($record.Stream -ceq 'stdout' -and $state.Lines.Count -lt 2) { $state.Lines.Add($record.Text) }
    }
    if ($baseResult.Outcome -cne 'Success' -or $baseState.Lines.Count -ne 1 -or $baseState.Lines[0] -cnotmatch '\A[a-f0-9]{40}\z') {
        throw 'CiImpactPlanDefaultBaseUnavailable: supply -Base or update the local origin/develop ref.'
    }
    $Base = $baseState.Lines[0]
}

$scratch = [IO.Path]::GetTempFileName()
$staged = $null
$keepScratch = $false
try {
    $planner = [IO.Path]::Combine($PSScriptRoot, 'New-CiImpactPlan.ps1')
    $null = & $planner -Base $Base -WorkingTree -OutputPath $scratch -Confirm:$false
    if ($destination) {
        $parent = [IO.Path]::GetDirectoryName($destination)
        [void][IO.Directory]::CreateDirectory($parent)
        $staged = [IO.Path]::Combine($parent, '.ci-plan-' + [guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::Copy($scratch, $staged)
        [IO.File]::Move($staged, $destination, $true)
    } else {
        $destination = $scratch
        $keepScratch = $true
    }
} finally {
    if (!$keepScratch) { [IO.File]::Delete($scratch) }
    if ($staged) { [IO.File]::Delete($staged) }
}

if ($Open) {
    Import-Module ([IO.Path]::Combine($PSScriptRoot, 'lib/EditorExtensions.psm1')) -DisableNameChecking -ErrorAction Stop
    $editorFailures = foreach ($insiders in $true, $false) {
        try {
            $editor = Resolve-DevelopmentEditorCli -Insiders:$insiders
            $start = [Diagnostics.ProcessStartInfo]::new($editor.FilePath)
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            [void]$start.Environment.Remove('ELECTRON_RUN_AS_NODE')
            $start.ArgumentList.Add($destination)
            $process = [Diagnostics.Process]::Start($start)
            $process.Dispose()
            break
        } catch {
            $_.Exception.Message
        }
    }
    if ($editorFailures.Count -eq 2) {
        throw "CiImpactPlanEditorUnavailable: $destination ($($editorFailures -join ' | '))"
    }
}

if ($GetContent) {
    Get-Content -LiteralPath $destination -Encoding utf8
} else {
    Get-Item -LiteralPath $destination
}
