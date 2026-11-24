#requires -Version 7.6

function Invoke-QuietScriptEnableWindowsLongPaths {
    <#
    .SYNOPSIS
    Writes the machine-wide LongPathsEnabled DWORD and reads it back.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    $name = 'LongPathsEnabled'
    if (!$PSCmdlet.ShouldProcess("$path\$name", 'Set DWORD to 1')) { return }

    New-ItemProperty -LiteralPath $path -Name $name -Value 1 -PropertyType DWord -Force -Confirm:$false -ErrorAction Stop
    Get-ItemPropertyValue -LiteralPath $path -Name $name -ErrorAction Stop
}

Export-ModuleMember -Function 'Invoke-QuietScriptEnableWindowsLongPaths'
