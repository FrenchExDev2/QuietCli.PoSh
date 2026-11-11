#Objective: Single text-encoding policy of the run-profile tooling.
#requires -Version 7.6
<#
.SYNOPSIS
Single text-encoding policy of the run-profile tooling.

.DESCRIPTION
Two different contracts live here, and only one of them is configurable:
- Files are always UTF-8 without BOM with LF line endings, as the repository rules require and as the byte-identical
  profile rendering depends on. Reading is strict: malformed bytes are an error, never replacement characters.
- The console boundary (what a process prints and what its consumer decodes) is a parameter, utf-8 by default,
  because the consumer (`quiet`) decodes strictly and a mismatch must be chosen deliberately, not hard-coded.
#>

$script:Utf8Strict = [Text.UTF8Encoding]::new($false, $true)
$script:Utf8Writer = [Text.UTF8Encoding]::new($false, $true)

function Read-RunTextFile {
    <#
    .SYNOPSIS
    Reads a UTF-8 text file; malformed bytes throw instead of being replaced.
    .PARAMETER Path
    File to read.
    #>
    param([Parameter(Mandatory)][string]$Path)
    return [IO.File]::ReadAllTextAsync($Path, $script:Utf8Strict).GetAwaiter().GetResult()
}

function ConvertTo-RunLf {
    <#
    .SYNOPSIS
    Normalizes CRLF and lone CR line endings to LF.
    .PARAMETER Text
    Text to normalize.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Write-RunTextFile {
    <#
    .SYNOPSIS
    Writes a text file as UTF-8 without BOM with LF line endings, replacing any existing file.
    .PARAMETER Path
    Destination file; its directory must exist.
    .PARAMETER Text
    Content; line endings are normalized to LF.
    #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    [void][IO.File]::WriteAllTextAsync($Path, (ConvertTo-RunLf $Text), $script:Utf8Writer).GetAwaiter().GetResult()
}

function Add-RunTextLine {
    <#
    .SYNOPSIS
    Appends one line, terminated by LF, to a UTF-8 file without BOM.
    .PARAMETER Path
    Destination file; its directory must exist.
    .PARAMETER Line
    Line without a terminator; embedded line breaks are normalized to LF.
    #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Line)
    [void][IO.File]::AppendAllTextAsync($Path, ((ConvertTo-RunLf $Line) + "`n"), $script:Utf8Writer).GetAwaiter().GetResult()
}

function Resolve-RunConsoleEncoding {
    <#
    .SYNOPSIS
    Maps a console encoding name to an Encoding without BOM: utf-8, or oem (the active OEM code page).
    .PARAMETER Name
    Encoding name; case-insensitive.
    #>
    [OutputType([Text.Encoding])]
    param([Parameter(Mandatory)][string]$Name)
    switch ($Name.ToLowerInvariant()) {
        'utf-8' { return [Text.UTF8Encoding]::new($false) }
        'oem' { return [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) }
        default { throw "RunConsoleEncodingUnknown: '$Name' (expected utf-8 or oem)" }
    }
}

function Set-RunConsoleEncoding {
    <#
    .SYNOPSIS
    Applies a console encoding to the console output and to the pipe encoding of native commands, and returns it.
    .PARAMETER Name
    Encoding name accepted by Resolve-RunConsoleEncoding.
    #>
    [OutputType([Text.Encoding])]
    param([Parameter(Mandatory)][string]$Name)
    $encoding = Resolve-RunConsoleEncoding -Name $Name
    [Console]::OutputEncoding = $encoding
    $global:OutputEncoding = $encoding
    return $encoding
}

Export-ModuleMember -Function Read-RunTextFile, Write-RunTextFile, Add-RunTextLine, ConvertTo-RunLf, Resolve-RunConsoleEncoding, Set-RunConsoleEncoding
