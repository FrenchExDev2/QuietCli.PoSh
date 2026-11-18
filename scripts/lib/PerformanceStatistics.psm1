#requires -Version 7.6
Set-StrictMode -Version Latest

function Get-QuietPerformanceRank {
    <#
    .SYNOPSIS
    Returns the 1-based nearest-rank position of a quantile in a sorted sample of the given size.
    .PARAMETER Count
    Sample size, at least 1.
    .PARAMETER Quantile
    Quantile strictly above 0 and at most 1.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)][ValidateRange(1,[int]::MaxValue)][int]$Count,[Parameter(Mandatory)][double]$Quantile)
    if(!($Quantile -gt 0 -and $Quantile -le 1)){throw 'PerformanceQuantileInvalid'}
    [int][Math]::Max(1,[Math]::Ceiling($Quantile*$Count))
}

function Get-QuietPerformanceStatistics {
    <#
    .SYNOPSIS
    Describes a sample by count, nearest-rank quartiles and p95, extremes and interquartile range.
    .DESCRIPTION
    Returns nothing for an empty sample (null when assigned, no pipeline item), so callers render
    "unavailable" rather than zero. Rejects non-finite values. P95IsMax is true when the nearest-rank p95 is the largest observation, which
    holds for every sample of fewer than 20 values: such a p95 describes the worst observed run, not
    a stable tail.
    .PARAMETER Values
    Finite observations in one unit.
    #>
    [CmdletBinding()]
    param([AllowEmptyCollection()][double[]]$Values)
    if($null -eq $Values -or !$Values.Count){return}
    foreach($value in $Values){if(![double]::IsFinite($value)){throw 'PerformanceStatisticsNonFinite'}}
    $sorted=[double[]]$Values.Clone();[Array]::Sort($sorted)
    $count=$sorted.Length
    $at={param([double]$Quantile)$sorted[(Get-QuietPerformanceRank -Count $count -Quantile $Quantile)-1]}
    $median=if($count%2){$sorted[($count-1)/2]}else{($sorted[$count/2-1]+$sorted[$count/2])/2}
    $q1=& $at 0.25;$q3=& $at 0.75
    $p95Rank=Get-QuietPerformanceRank -Count $count -Quantile 0.95
    [pscustomobject]@{
        Count=$count;Min=$sorted[0];Q1=$q1;Median=$median;Q3=$q3;Max=$sorted[$count-1]
        Iqr=$q3-$q1;P95=$sorted[$p95Rank-1];P95Rank=$p95Rank;P95IsMax=($p95Rank -eq $count)
    }
}

Export-ModuleMember -Function 'Get-QuietPerformanceRank','Get-QuietPerformanceStatistics'
