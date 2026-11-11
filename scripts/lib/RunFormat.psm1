#Objective: Presentation helpers shared by the run-profile tooling: compact durations, Unicode tables, counter tables and PowerShell literals.
#requires -Version 7.6
<#
.SYNOPSIS
Presentation helpers shared by the run-profile tooling: compact durations, Unicode tables, counter tables and PowerShell literals.
#>

function Format-RunDuration {
    <#
    .SYNOPSIS
    Formats milliseconds with compact units: 12ms, 1s, 1m30s, 2h5m. Unknown values render as a dash.
    .PARAMETER Milliseconds
    Duration in milliseconds; negative values keep their sign.
    #>
    param($Milliseconds)
    if ($null -eq $Milliseconds -or [double]::IsNaN([double]$Milliseconds)) { return '-' }
    $value = [double]$Milliseconds
    $sign = if ($value -lt 0) { '-' } else { '' }
    $magnitude = [Math]::Abs($value)
    if ($magnitude -lt 999.5) { return "$sign$([long][Math]::Round($magnitude))ms" }
    $seconds = [long][Math]::Round($magnitude / 1000)
    $hours = [Math]::Floor($seconds / 3600)
    $minutes = [Math]::Floor(($seconds % 3600) / 60)
    $rest = $seconds % 60
    $text = if ($hours -gt 0) { "${hours}h" + $(if ($minutes -gt 0) { "${minutes}m" } else { '' }) }
    elseif ($minutes -gt 0) { "${minutes}m" + $(if ($rest -gt 0) { "${rest}s" } else { '' }) }
    else { "${rest}s" }
    return $sign + $text
}

function Format-RunDataSize {
    <#
    .SYNOPSIS
    Formats a byte count as a compact MiB figure (2 decimals). Unknown values render as a dash.
    .PARAMETER Bytes
    Size in bytes; negative values keep their sign.
    .PARAMETER Signed
    Also prefixes a non-negative value with '+', for a candidate-minus-baseline difference.
    #>
    param($Bytes, [switch]$Signed)
    if ($null -eq $Bytes -or [double]::IsNaN([double]$Bytes)) { return '-' }
    $mib = [double]$Bytes / 1MB
    $sign = if ($Signed -and $mib -ge 0) { '+' } else { '' }
    return "$sign$($mib.ToString('F2', [Globalization.CultureInfo]::InvariantCulture)) MiB"
}

function Format-RunCell {
    <#
    .SYNOPSIS
    Pads or truncates (with an ellipsis) one table cell to an exact width.
    .PARAMETER Text
    Cell text.
    .PARAMETER Width
    Target width in characters.
    .PARAMETER Right
    Right-aligns the text.
    #>
    param([string]$Text, [int]$Width, [switch]$Right)
    if ($Text.Length -gt $Width) { $Text = $Text.Substring(0, [Math]::Max(0, $Width - 1)) + '…' }
    if ($Right) { return $Text.PadLeft($Width) }
    return $Text.PadRight($Width)
}

function Format-RunTable {
    <#
    .SYNOPSIS
    Renders a Unicode box-drawing table whose lines all have the same width, shrinking the widest columns when needed.
    .PARAMETER Headers
    Column titles.
    .PARAMETER Rows
    Rows, each an array of cell values.
    .PARAMETER RightAligned
    Zero-based indexes of right-aligned columns.
    .PARAMETER Width
    Maximum table width; zero means the console width, or 110 when output is redirected.
    #>
    [OutputType([string[]])]
    param([string[]]$Headers, [object[]]$Rows = @(), [int[]]$RightAligned = @(), [int]$Width = 0)
    if ($Width -le 0) {
        $Width = 110
        try {
            if (-not [Console]::IsOutputRedirected -and -not [Console]::IsErrorRedirected -and [Console]::WindowWidth -gt 0) { $Width = [Console]::WindowWidth }
        } catch { $Width = 110 }
    }
    $count = $Headers.Count
    $widths = [int[]]::new($count)
    for ($c = 0; $c -lt $count; $c++) {
        $widths[$c] = $Headers[$c].Length
        foreach ($row in $Rows) { $widths[$c] = [Math]::Max($widths[$c], ([string]$row[$c]).Length) }
    }
    $overflow = ($widths | Measure-Object -Sum).Sum + 3 * $count + 1 - $Width
    while ($overflow -gt 0) {
        $widest = 0
        for ($c = 1; $c -lt $count; $c++) { if ($widths[$c] -gt $widths[$widest]) { $widest = $c } }
        if ($widths[$widest] -le 4) { break }
        $widths[$widest]--; $overflow--
    }
    $rule = { param($left, $middle, $right) $left + (($widths | ForEach-Object { '─' * ($_ + 2) }) -join $middle) + $right }
    $line = { param($cells) '│' + ((0..($count - 1) | ForEach-Object { ' ' + (Format-RunCell -Text ([string]$cells[$_]) -Width $widths[$_] -Right:($_ -in $RightAligned)) + ' ' }) -join '│') + '│' }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add((& $rule '┌' '┬' '┐')); $lines.Add((& $line $Headers)); $lines.Add((& $rule '├' '┼' '┤'))
    foreach ($row in $Rows) { $lines.Add((& $line $row)) }
    $lines.Add((& $rule '└' '┴' '┘'))
    return $lines.ToArray()
}

function Format-RunCounters {
    <#
    .SYNOPSIS
    Renders a counter dictionary as a table; keys ending in .ms are shown as compact durations.
    .PARAMETER Counters
    Counter dictionary (name to number).
    .PARAMETER Width
    Maximum table width; zero means automatic.
    #>
    [OutputType([string[]])]
    param([Collections.IDictionary]$Counters, [int]$Width = 0)
    $rows = [Collections.Generic.List[object]]::new()
    foreach ($key in ($Counters.Keys | Sort-Object -CaseSensitive)) {
        $rows.Add(@($key, $(if ($key.EndsWith('.ms', [StringComparison]::Ordinal)) { Format-RunDuration $Counters[$key] } else { [string]$Counters[$key] })))
    }
    return Format-RunTable -Headers @('Counter', 'Value') -Rows $rows -RightAligned @(1) -Width $Width
}

function ConvertTo-RunSingleQuoted {
    <#
    .SYNOPSIS
    Produces a single-quoted PowerShell string literal, doubling every character PowerShell treats as a single quote.
    .PARAMETER Value
    Text to quote; control characters are rejected so that files stay line-oriented.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    if ($Value -match '[\u0000-\u001F\u007F]') { throw 'RunLiteralControlCharacter' }
    return "'" + [regex]::Replace($Value, "['‘’‚‛]", '$0$0') + "'"
}

Export-ModuleMember -Function Format-RunDuration, Format-RunDataSize, Format-RunTable, Format-RunCounters, ConvertTo-RunSingleQuoted
