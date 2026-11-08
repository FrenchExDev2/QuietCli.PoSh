#requires -Version 7.6
function ConvertFrom-RunColdSample {
    <#
    .SYNOPSIS
    Validates the three invariant-culture, finite, nonnegative durations returned by a measurement child.
    .PARAMETER Fields
    Import, first-call and second-call milliseconds, without the RESULT marker.
    #>
    param([AllowNull()][AllowEmptyCollection()][object[]]$Fields)
    if ($null -eq $Fields -or $Fields.Count -ne 3) { throw 'ColdSampleInvalid' }
    $values = [double[]]::new(3)
    for ($index = 0; $index -lt 3; $index++) {
        $value = 0.0
        if (-not [double]::TryParse([string]$Fields[$index], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$value) -or -not [double]::IsFinite($value) -or $value -lt 0) { throw 'ColdSampleInvalid' }
        $values[$index] = $value
    }
    return [pscustomobject]@{ Import = $values[0]; First = $values[1]; Second = $values[2] }
}
Export-ModuleMember -Function ConvertFrom-RunColdSample
