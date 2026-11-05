# Objectif : Calculer les durées du moniteur indépendamment de la culture du terminal.
function ConvertTo-QuietMonitorTimestamp {
    <#
    .SYNOPSIS
    Preserves typed timestamps and parses persisted ISO timestamps using invariant culture.
    .PARAMETER Value
    DateTimeOffset, DateTime or an ISO timestamp from a run report.
    #>
    param([Parameter(Mandatory)]$Value)
    if($Value -is [DateTimeOffset]){return $Value}
    if($Value -is [DateTime]){return [DateTimeOffset]::new($Value)}
    return [DateTimeOffset]::Parse([string]$Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
}
function Get-QuietMonitorDuration {
    <#
    .SYNOPSIS
    Formats elapsed time, stopping the clock at the saved terminal timestamp.
    .PARAMETER StartedUtc
    Start timestamp as stored in the run status.
    .PARAMETER FinishedUtc
    Optional terminal timestamp; active runs use Now.
    .PARAMETER Now
    Current time, injectable for independent assertions.
    #>
    param([Parameter(Mandatory)]$StartedUtc,$FinishedUtc,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    $start=ConvertTo-QuietMonitorTimestamp $StartedUtc
    $end=if($null -ne $FinishedUtc -and ![string]::IsNullOrEmpty([string]$FinishedUtc)){ConvertTo-QuietMonitorTimestamp $FinishedUtc}else{$Now}
    $seconds=[long][Math]::Max(0,[Math]::Floor(($end-$start).TotalSeconds))
    if($seconds -ge 3600){return '{0}h{1}m' -f [Math]::Floor($seconds/3600),[Math]::Floor(($seconds%3600)/60)}
    if($seconds -ge 60){return '{0}m{1}s' -f [Math]::Floor($seconds/60),($seconds%60)}
    return "${seconds}s"
}
