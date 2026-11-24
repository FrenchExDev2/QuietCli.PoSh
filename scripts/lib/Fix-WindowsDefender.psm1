#requires -Version 7.6

function Invoke-QuietScriptFixWindowsDefender {
    <#
    .SYNOPSIS
    Adds the development path, process and extension exclusions and returns the active lists.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (!$PSCmdlet.ShouldProcess('Microsoft Defender Antivirus', 'Add development path, process and VHDX exclusions')) { return }

    $paths = @(
        'C:\code'
        if ($env:USERPROFILE) {
            [IO.Path]::Combine($env:USERPROFILE, 'source', 'repos')
            [IO.Path]::Combine($env:USERPROFILE, '.nuget', 'packages')
            [IO.Path]::Combine($env:USERPROFILE, '.vscode-insiders')
        }
        if ($env:LOCALAPPDATA) {
            [IO.Path]::Combine($env:LOCALAPPDATA, 'npm-cache')
            [IO.Path]::Combine($env:LOCALAPPDATA, 'Programs', 'Microsoft VS Code Insiders')
        }
        if ($env:APPDATA) {
            [IO.Path]::Combine($env:APPDATA, 'Code - Insiders')
        }
        'C:\Program Files\dotnet'
    )
    $existingPaths = @(foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path -ErrorAction Stop) { $path }
    })

    $exclusions = @{
        ExclusionProcess = @('dotnet.exe', 'MSBuild.exe', 'VBCSCompiler.exe', 'node.exe', 'code.exe', 'Code - Insiders.exe', 'git.exe', 'codex.exe', 'claude.exe')
        ExclusionExtension = 'vhdx'
    }
    if ($existingPaths.Count -gt 0) { $exclusions.ExclusionPath = $existingPaths }

    Add-MpPreference @exclusions -ErrorAction Stop
    Get-MpPreference -ErrorAction Stop | Select-Object ExclusionPath, ExclusionProcess, ExclusionExtension
}

Export-ModuleMember -Function 'Invoke-QuietScriptFixWindowsDefender'
