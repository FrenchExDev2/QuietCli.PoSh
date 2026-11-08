#requires -Version 7.6
<#
.SYNOPSIS
Order statistics and a paired bootstrap used to separate a real difference from measurement noise.
#>

function Get-SortedQuantile {
    <#
    .SYNOPSIS
    Linearly interpolated quantile of an already sorted sample.
    .PARAMETER Sorted
    Ascending, non-empty sample.
    .PARAMETER Probability
    Quantile in the closed range 0..1.
    #>
    param([double[]]$Sorted, [double]$Probability)
    $position = ($Sorted.Length - 1) * $Probability
    $low = [int][Math]::Floor($position)
    $high = [int][Math]::Ceiling($position)
    return $Sorted[$low] + ($Sorted[$high] - $Sorted[$low]) * ($position - $low)
}

function Get-RunQuantile {
    <#
    .SYNOPSIS
    Returns a linearly interpolated quantile of an unsorted sample.
    .PARAMETER Values
    Non-empty sample.
    .PARAMETER Probability
    Quantile in the closed range 0..1.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][double[]]$Values, [Parameter(Mandatory)][ValidateRange(0, 1)][double]$Probability)
    if ($Values.Length -eq 0) { throw 'RunStatisticsEmptySample' }
    $sorted = [double[]]$Values.Clone()
    [Array]::Sort($sorted)
    return Get-SortedQuantile $sorted $Probability
}

function Get-RunSummary {
    <#
    .SYNOPSIS
    Summarizes a sample as count, minimum, quartiles, median and maximum.
    .PARAMETER Values
    Non-empty sample.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][double[]]$Values)
    if ($Values.Length -eq 0) { throw 'RunStatisticsEmptySample' }
    $sorted = [double[]]$Values.Clone()
    [Array]::Sort($sorted)
    return [pscustomobject]@{
        N      = $sorted.Length
        Min    = $sorted[0]
        Q1     = Get-SortedQuantile $sorted 0.25
        Median = Get-SortedQuantile $sorted 0.5
        Q3     = Get-SortedQuantile $sorted 0.75
        Max    = $sorted[-1]
    }
}

function Get-PairedBootstrapInterval {
    <#
    .SYNOPSIS
    Percentile bootstrap confidence interval of the median of paired differences.
    .DESCRIPTION
    Resamples the pairs with replacement, so drift shared by both members of a pair cancels out. The seed makes the
    interval reproducible.
    .PARAMETER Differences
    Candidate minus baseline, one value per pair.
    .PARAMETER Resamples
    Number of bootstrap resamples.
    .PARAMETER Seed
    Seed of the resampling generator.
    .PARAMETER Confidence
    Two-sided confidence level, strictly between 0 and 1.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][double[]]$Differences,
        [ValidateRange(100, 1000000)][int]$Resamples = 2000,
        [int]$Seed = 1,
        [ValidateRange(0.01, 0.9999)][double]$Confidence = 0.95
    )
    $n = $Differences.Length
    if ($n -eq 0) { throw 'RunStatisticsEmptySample' }
    $random = [Random]::new($Seed)
    $buffer = [double[]]::new($n)
    $medians = [double[]]::new($Resamples)
    $middle = $n -shr 1
    for ($r = 0; $r -lt $Resamples; $r++) {
        for ($i = 0; $i -lt $n; $i++) { $buffer[$i] = $Differences[$random.Next($n)] }
        [Array]::Sort($buffer)
        $medians[$r] = if ($n % 2 -eq 1) { $buffer[$middle] } else { ($buffer[$middle - 1] + $buffer[$middle]) / 2 }
    }
    [Array]::Sort($medians)
    $alpha = (1 - $Confidence) / 2
    return [pscustomobject]@{
        Pairs      = $n
        Median     = (Get-RunQuantile $Differences 0.5)
        Low        = Get-SortedQuantile $medians $alpha
        High       = Get-SortedQuantile $medians (1 - $alpha)
        Confidence = $Confidence
        Resamples  = $Resamples
    }
}

function Get-RunVerdict {
    <#
    .SYNOPSIS
    Classifies a confidence interval of candidate-minus-baseline differences.
    .PARAMETER Interval
    Object with Pairs, Low and High.
    .PARAMETER MinPairs
    Below this many pairs the bootstrap interval is unreliable and no direction is claimed.
    #>
    param([Parameter(Mandatory)]$Interval, [int]$MinPairs = 20)
    if ($Interval.Pairs -lt $MinPairs) { return 'too-few-pairs' }
    if ($Interval.Low -gt 0) { return 'slower' }
    if ($Interval.High -lt 0) { return 'faster' }
    return 'inconclusive'
}

Export-ModuleMember -Function Get-RunQuantile, Get-RunSummary, Get-PairedBootstrapInterval, Get-RunVerdict
