function Get-QuietMetadata {
    <#
.SYNOPSIS
Projects execution counters only; never touches the business Data property.
    .PARAMETER Result
    Local result whose public business data must not be inspected.
    #>
    param($Result)
    Import-QuietManagedEngine
    $metadata=@{InvocationId=$Result.InvocationId;ParentId=$Result.ParentId;RootId=$Result.RootId;SessionId=$Result.SessionId;Context=$Result.Context;Command=[IO.Path]::GetFileName($Result.Internal.Request.FilePath);Role=$Result.Internal.Request.Role;Outcome=$Result.Outcome;Completeness=$Result.Completeness;Sources=$Result.Internal.Sources.Values;Execution=$Result.Execution;Error=$Result.Error;Allocation=$Result.Measurement.Allocation;CompleteAllocation=$Result.Measurement.CompleteAllocation}
    if($Result.Internal.Handler){$metadata.HandlerId=$Result.Internal.Handler.Id;$metadata.ModuleVersion=$Result.Internal.Handler.ModuleVersion}
    return [FrenchExDev2.QuietCli.MeasurementTelemetry]::Project($metadata,$script:QuietMetadataAdapter)
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
    Maximum telemetry events scanned by this report; a limit is explicitly marked incomplete.
    #>
    [CmdletBinding()]param([Alias('C')][string]$Context,[switch]$Generic,[string]$SessionId,[string]$ModuleId,[int]$Days=7,[DateTimeOffset]$From,[DateTimeOffset]$To=[DateTimeOffset]::UtcNow,[ValidateSet('Context','Command','Session','Module','Role','Outcome')][string]$GroupBy='Context',[switch]$AsObject,[ValidateRange(1,1000000)][int]$MaxEvents=10000)
    if($Generic -and $PSBoundParameters.ContainsKey('Context')){throw 'ContextAndGenericAreExclusive'}
    if(!$PSBoundParameters.ContainsKey('From')){$From=$To.AddDays(-$Days)}
    if($From -ge $To){throw 'InvalidTimeRange'}
    $query=@{Action='gain';From=$From.ToUnixTimeMilliseconds();To=$To.ToUnixTimeMilliseconds();Generic=[bool]$Generic;GroupBy=$GroupBy;MaxEvents=$MaxEvents}
    if($PSBoundParameters.ContainsKey('Context')){$query.Context=$Context}
    if($SessionId){$query.SessionId=$SessionId}
    if($ModuleId){$query.ModuleId=$ModuleId}
    $groups=[Collections.Generic.List[object]]::new();$reportId=$null;$report=$null
    try{
        do{
            $response=(Send-QuietRequest $query).Header.Data
            if($response.PSObject.Properties['Pending'] -and $response.Pending){
                if(!$response.ReportId){throw 'MeasurementPaginationMissingCursor'}
                $reportId=$response.ReportId;$query=@{Action='gain-poll';ReportId=$reportId}
                continue
            }
            if($null -eq $report){$report=$response.Report}
            foreach($group in $response.Groups){$groups.Add($group)}
            if($response.GroupsComplete){break}
            if(!$response.ReportId -or $null -eq $response.After){throw 'MeasurementPaginationMissingCursor'}
            $reportId=$response.ReportId
            $query=@{Action='gain-next';ReportId=$reportId;After=$response.After}
        }while($true)
    }finally{if($reportId){try{$null=Send-QuietRequest @{Action='gain-release';ReportId=$reportId}}catch{}}}
    $report|Add-Member -NotePropertyName From -NotePropertyValue $From
    $report|Add-Member -NotePropertyName To -NotePropertyValue $To
    $report|Add-Member -NotePropertyName Groups -NotePropertyValue $groups.ToArray()
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
