#requires -Version 7.6
function New-QuietPreviewTagName {
    <#
    .SYNOPSIS
    Creates a deterministic preview tag from a numeric module version and a UTC instant.
    .PARAMETER Version
    Three-component numeric version read from the Core manifest.
    .PARAMETER Timestamp
    Instant converted to UTC, retaining all seven fractional-second digits.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Version, [Parameter(Mandatory)][DateTimeOffset]$Timestamp)
    if ($Version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z') {
        throw 'PreviewTagInvalidVersion'
    }
    $stamp = $Timestamp.ToUniversalTime().ToString("yyyyMMdd'T'HHmmssfffffff'Z'", [Globalization.CultureInfo]::InvariantCulture)
    return "v$Version-preview$stamp"
}
Export-ModuleMember -Function New-QuietPreviewTagName
