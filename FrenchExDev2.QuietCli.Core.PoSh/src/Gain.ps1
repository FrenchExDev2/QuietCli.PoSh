function Get-QuietMetadata {
    <#
.SYNOPSIS
Projects execution counters only; never touches the business Data property.
    .PARAMETER Result
    Local result whose public business data must not be inspected.
    #>
    param($Result)
    $execution=@{State=$Result.Execution.State;ElapsedMs=$Result.Execution.ElapsedMs;CallbackMs=$Result.Execution.CallbackMs;Children=$Result.Execution.Children;EffectStatus=$Result.Execution.EffectStatus;Native=$null;Issues=@()}
    if($Result.Execution.Native){
        $native=@{}
        foreach($field in @('ProcessId','Transport','ReadBlockBytes','ExitCode','Outcome','StdinBytesWritten','StdoutBytesRead','StderrBytesRead','TerminalBytesRead','ElapsedMs','SourceComplete','Error','State','EffectStatus')){
            if($Result.Execution.Native.ContainsKey($field)){$native[$field]=$Result.Execution.Native[$field]}
        }
        $execution.Native=$native
    }
    $execution.Issues=@(foreach($issue in $Result.Execution.Issues){@{InvocationId=$issue.InvocationId;Outcome=$issue.Outcome;EffectStatus=$issue.EffectStatus;Error=(ConvertTo-QuietErrorCodes $issue.Error)}})
    $metadata=@{InvocationId=$Result.InvocationId;ParentId=$Result.ParentId;RootId=$Result.RootId;SessionId=$Result.SessionId;Context=$Result.Context;Command=[IO.Path]::GetFileName($Result.Internal.Request.FilePath);Role=$Result.Internal.Request.Role;Outcome=$Result.Outcome;Completeness=$Result.Completeness;Sources=@($Result.Internal.Sources.Values);Execution=$execution;Error=(ConvertTo-QuietErrorCodes $Result.Error);CallbackMs=$Result.Execution.CallbackMs}
    if($Result.Internal.Handler){$metadata.HandlerId=$Result.Internal.Handler.Id;$metadata.ModuleVersion=$Result.Internal.Handler.ModuleVersion}
    return $metadata
}
function Save-QuietResultMetadata {
    <#
.SYNOPSIS
Saves counters without serializing or enumerating Result.Data.
    .PARAMETER Result
    Completed caller-local result.
    #>
    param($Result)
    if($env:QUIETCLI2_TRACKING -eq '0'){return}
    try{$null=Send-QuietRequest @{Action='save';Kind='invocation';Metadata=(Get-QuietMetadata $Result)}}
    catch{$Result.Measurement.StorageError=$_.Exception.Message;$Result.Measurement.Status='StorageUnavailable'}
}
function Get-QuietCliGain {
    <#
.SYNOPSIS
Reports measured counters across all contexts by default, without creating a missing database.
    .PARAMETER Context
    Optional named context, alias C.
    .PARAMETER Generic
    Selects only invocations without a context; exclusive with Context.
    .PARAMETER SessionId
    Optional caller session identity.
    .PARAMETER ModuleId
    Optional registered business module identity.
    .PARAMETER Days
    Number of past days, default seven.
    .PARAMETER From
    Inclusive lower time boundary; overrides Days.
    .PARAMETER To
    Exclusive upper time boundary.
    .PARAMETER GroupBy
    Context, Command, Session, Module, Role or Outcome.
    .PARAMETER AsObject
    Returns the report directly; does not serialize it.
    .PARAMETER MaxEvents
    Maximum telemetry events retained by this report; a limit is explicitly marked incomplete.
    #>
    [CmdletBinding()]param([Alias('C')][string]$Context,[switch]$Generic,[string]$SessionId,[string]$ModuleId,[int]$Days=7,[DateTimeOffset]$From,[DateTimeOffset]$To=[DateTimeOffset]::UtcNow,[ValidateSet('Context','Command','Session','Module','Role','Outcome')][string]$GroupBy='Context',[switch]$AsObject,[ValidateRange(1,1000000)][int]$MaxEvents=10000)
    if($Generic -and $PSBoundParameters.ContainsKey('Context')){throw 'ContextAndGenericAreExclusive'}
    if(!$PSBoundParameters.ContainsKey('From')){$From=$To.AddDays(-$Days)}
    if($From -ge $To){throw 'InvalidTimeRange'}
    $query=@{Action='query';From=$From.ToUnixTimeMilliseconds();To=$To.ToUnixTimeMilliseconds();Generic=[bool]$Generic}
    if($PSBoundParameters.ContainsKey('Context')){$query.Context=$Context}
    if($SessionId){$query.SessionId=$SessionId}
    if($ModuleId){$query.ModuleId=$ModuleId}
    $rows=[Collections.Generic.List[object]]::new()
    $limited=$false
    do{
        $response=(Send-QuietRequest $query).Header.Data
        foreach($row in $response.Rows){if($rows.Count -ge $MaxEvents){$limited=$true;break};$rows.Add($row)}
        if($response.Complete -or $rows.Count -ge $MaxEvents){break}
        if(!$response.After){throw 'MeasurementPaginationMissingCursor'}
        $query.After=$response.After
    }while($true)
    $complete=[bool]$response.Complete -and !$limited
    $calls=@($rows|Where-Object{!$_.PSObject.Properties['DeliveryId'] -or $null -eq $_.DeliveryId})
    $deliveries=@($rows|Where-Object{$_.PSObject.Properties['DeliveryId'] -and $null -ne $_.DeliveryId})
    $sourceMap=@{}
    foreach($call in $calls){foreach($source in $call.Sources){$sourceMap[$source.InvocationId]=$source}}
    $business=0L;$auxiliary=0L;$stdin=0L;$unknown=0
    foreach($source in $sourceMap.Values){$size=if($null -ne $source.TerminalBytesRead){$source.TerminalBytesRead}else{[long]$source.StdoutBytesRead+[long]$source.StderrBytesRead};$stdin+=$source.StdinBytesWritten;if($source.Role -eq 'Business'){$business+=$size}else{$auxiliary+=$size};if(!$source.Complete){$unknown++}}
    $rootDeliveries=@($deliveries|Where-Object{!$_.ParentId})
    $delivered=if($rootDeliveries.Count){[long](($rootDeliveries|Measure-Object OutputBytes -Sum).Sum)}else{$null}
    $groups=@($calls|Group-Object -CaseSensitive -Property {$row=$_;switch($GroupBy){Context {if($null -eq $row.Context){'(generic)'}else{$row.Context}} Session {$row.SessionId} Module {if($row.PSObject.Properties['HandlerId'] -and $row.HandlerId){$row.HandlerId}else{'(direct)'}} default {$row.$GroupBy}}}|ForEach-Object{@{Key=$_.Name;Invocations=$_.Count;Roots=@($_.Group|Where-Object{!$_.ParentId}).Count;Failures=@($_.Group|Where-Object Outcome -NE Success).Count}})
    $report=[pscustomobject]@{From=$From;To=$To;Complete=$complete;Invocations=$calls.Count;Roots=@($calls|Where-Object{!$_.ParentId}).Count;UniqueNativeSources=$sourceMap.Count;StdinBytesWritten=$stdin;BusinessBytesObserved=$business;AuxiliaryBytesObserved=$auxiliary;IncompleteSources=$unknown;RootDeliveryBytes=$delivered;ReductionBytes=$null;NativeTokens=$null;Groups=$groups;Comparability='Observed effective native business output; source and delivered object may be projected. Context subtotals are not additive.'}
    # A total reduction requires exactly one accounted delivery for every selected root.
    $roots=@($calls|Where-Object{!$_.ParentId})
    if($unknown -eq 0 -and $complete -and $roots.Count -gt 0 -and $rootDeliveries.Count -eq $roots.Count -and @($rootDeliveries.InvocationId|Select-Object -Unique).Count -eq $roots.Count -and @($roots|Where-Object{!$_.Completeness -or !$_.Completeness.Analysis}).Count -eq 0){$report.ReductionBytes=$business-$delivered}
    if($AsObject){return $report}
    ConvertTo-Json -InputObject $report -Depth 20 -Compress
}
function Repair-QuietCliMeasurementPrivacy {
    <#
    .SYNOPSIS
    Explicitly expunges legacy persisted diagnostic text; normal reads only project safe fields.
    .DESCRIPTION
    Irreversible for the selected engine database. Does not erase external backups or filesystem snapshots.
    .EXAMPLE
    Repair-QuietCliMeasurementPrivacy -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]param()
    $identity=Get-QuietEngine
    if($PSCmdlet.ShouldProcess($identity.Database,'Expurger définitivement les diagnostics historiques non conformes')){
        (Send-QuietRequest @{Action='scrub';Confirmed=$true}).Header.Data
    }
}
