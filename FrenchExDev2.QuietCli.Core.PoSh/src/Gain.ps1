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
function ConvertTo-QuietGainYamlGraph {
    <#
    .SYNOPSIS
    Normalizes the closed telemetry report for the YAML renderer without truncating groups.
    .PARAMETER Value
    Report property, group, array or scalar received from the metadata engine.
    #>
    param([AllowNull()]$Value)
    if($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]){return $Value}
    if($Value -is [array]){return ,@($Value | ForEach-Object {ConvertTo-QuietGainYamlGraph $_})}
    $map=[ordered]@{}
    foreach($property in $Value.PSObject.Properties){$map[$property.Name]=ConvertTo-QuietGainYamlGraph $property.Value}
    return $map
}
function Get-QuietCliGain {
    <#
.SYNOPSIS
Reports measured counters across all contexts by default, without creating a missing database.
    .DESCRIPTION
    Returns a PSCustomObject by default. Formatting the report never records delivery telemetry.
    .PARAMETER Context
    Optional named context, alias C.
    .PARAMETER Generic
    Selects only invocations without a context; exclusive with Context.
    .PARAMETER SessionId
    Optional caller session identity.
    .PARAMETER ModuleId
    Optional registered business module identity.
    .PARAMETER Days
    Optional trailing window ending at To or now. Ignored when From is supplied.
    .PARAMETER From
    Optional inclusive lower time boundary; overrides Days. Null means no lower boundary.
    .PARAMETER To
    Optional exclusive upper time boundary. Null means no upper boundary.
    .PARAMETER GroupBy
    Context, Command, Session, Module, Role or Outcome.
    .PARAMETER AsObject
    Explicitly selects the default object output; retained for compatibility.
    .PARAMETER AsYaml
    Serializes the report directly as YAML without recording a delivery.
    .PARAMETER AsJson
    Serializes the report as indented JSON without recording a delivery.
    .PARAMETER Compress
    Removes JSON formatting whitespace; requires AsJson.
    .PARAMETER MaxEvents
    Maximum telemetry events scanned by this report; a limit is explicitly marked incomplete.
    #>
    [CmdletBinding()]param([Alias('C')][string]$Context,[switch]$Generic,[string]$SessionId,[string]$ModuleId,[ValidateRange(1,3650000)][int]$Days,[Nullable[DateTimeOffset]]$From,[Nullable[DateTimeOffset]]$To,[ValidateSet('Context','Command','Session','Module','Role','Outcome')][string]$GroupBy='Context',[switch]$AsObject,[switch]$AsYaml,[switch]$AsJson,[switch]$Compress,[ValidateRange(1,1000000)][int]$MaxEvents=10000)
    if(([int][bool]$AsObject+[int][bool]$AsYaml+[int][bool]$AsJson) -gt 1){throw 'OutputFormatsAreExclusive'}
    if($PSBoundParameters.ContainsKey('Compress') -and !$AsJson){throw 'CompressRequiresAsJson'}
    if($Generic -and $PSBoundParameters.ContainsKey('Context')){throw 'ContextAndGenericAreExclusive'}
    if($null -eq $From -and $PSBoundParameters.ContainsKey('Days')){
        if($null -eq $To){$To=[DateTimeOffset]::UtcNow}
        $From=$To.AddDays(-$Days)
    }
    if($null -ne $From -and $null -ne $To -and $From -ge $To){throw 'InvalidTimeRange'}
    $lower=if($null -eq $From){[DateTimeOffset]::MinValue.ToUnixTimeMilliseconds()}else{$From.ToUnixTimeMilliseconds()}
    $upper=if($null -eq $To){[DateTimeOffset]::MaxValue.ToUnixTimeMilliseconds()}else{$To.ToUnixTimeMilliseconds()}
    $query=@{Action='gain';From=$lower;To=$upper;Generic=[bool]$Generic;GroupBy=$GroupBy;MaxEvents=$MaxEvents}
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
    # Integrated hosting returns a CLR DTO; expose the same PowerShell type in both hosts.
    $properties=[ordered]@{}
    foreach($property in $report.PSObject.Properties){$properties[$property.Name]=$property.Value}
    $report=[pscustomobject]$properties
    $report|Add-Member -NotePropertyName From -NotePropertyValue $From
    $report|Add-Member -NotePropertyName To -NotePropertyValue $To
    $report|Add-Member -NotePropertyName Groups -NotePropertyValue $groups.ToArray()
    # Report formatting is independent of measured business-result deliveries.
    if($AsYaml){return ConvertTo-QuietYamlValue (ConvertTo-QuietGainYamlGraph $report)}
    if($AsJson){return ConvertTo-Json -InputObject $report -Depth 20 -Compress:$Compress}
    return $report
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
