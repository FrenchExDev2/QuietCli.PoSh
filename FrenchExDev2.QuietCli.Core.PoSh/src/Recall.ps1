function Get-QuietRecallSettings {
    <#
    .SYNOPSIS
    Projects only inert analysis settings, without native arguments or callbacks.
    .PARAMETER Request
    Original request.
    #>
    param([hashtable]$Request)
    $delimiter=if($Request.ContainsKey('RecordDelimiter')){[string]$Request.RecordDelimiter}else{[NullString]::Value}
    $stdout=if($Request.StdoutMode -eq 'Bytes'){'Bytes'}else{'Text'}
    $stderr=if($Request.StderrMode -eq 'Bytes'){'Bytes'}else{'Text'}
    return [FrenchExDev2.QuietCli.RecallAnalysisSettings]::new($stdout,$stderr,$delimiter,$Request.MaxRecordBytes)
}
function Resolve-QuietRecall {
    <#
    .SYNOPSIS
    Accepts an immutable capture or a result containing one.
    .PARAMETER InputObject
    Capture or native result.
    #>
    param($InputObject)
    Import-QuietManagedEngine
    if($InputObject -is [FrenchExDev2.QuietCli.RecallCapture]){return $InputObject}
    if($InputObject.PSObject.Properties['Recall'] -and $InputObject.Recall -is [FrenchExDev2.QuietCli.RecallCapture]){return $InputObject.Recall}
    throw 'RecallCaptureRequired'
}
function Get-QuietRecall {
    <#
    .SYNOPSIS
    Reads bounded native evidence with explicit event and byte budgets.
    .PARAMETER InputObject
    Native result or capture.
    .PARAMETER Sequence
    First original block sequence.
    .PARAMETER Stream
    Optional native stream filter.
    .PARAMETER Offset
    First stream byte offset.
    .PARAMETER ByteCount
    Selected stream byte range.
    .PARAMETER Context
    Neighbor events on each side.
    .PARAMETER MaxItems
    Delivered event budget.
    .PARAMETER MaxOutputBytes
    Delivered native byte budget; object metadata is additional.
    .PARAMETER Reference
    Optional validated evidence reference to resolve against this capture.
    .EXAMPLE
    Get-QuietRecall -InputObject $result -Stream stderr -MaxOutputBytes 4096
    #>
    [CmdletBinding()]param([Parameter(Mandatory)]$InputObject,[long]$Sequence=1,[ValidateSet('stdout','stderr','terminal')][string]$Stream,[long]$Offset=0,[long]$ByteCount=[long]::MaxValue,[int]$Context=0,[int]$MaxItems=20,[long]$MaxOutputBytes=4096,$Reference)
    $capture=Resolve-QuietRecall $InputObject
    if($Reference){
        if($Reference.CaptureId -cne $capture.CaptureId){throw 'RecallReferenceCaptureMismatch'}
        $Stream=$Reference.Stream;$Offset=$Reference.Offset;$ByteCount=$Reference.ByteCount
        $null=[FrenchExDev2.QuietCli.RecallReader]::Reference($capture,$Stream,$Offset,$ByteCount)
    }
    $selectedStream=if($Stream){$Stream}else{[NullString]::Value}
    return ,([FrenchExDev2.QuietCli.RecallReader]::Read($capture,$Sequence,$selectedStream,$Offset,$ByteCount,$Context,$MaxItems,$MaxOutputBytes))
}
function New-QuietRecallReference {
    <#
    .SYNOPSIS
    Creates a content-free reference only for a completely retained byte range.
    .PARAMETER InputObject
    Native result or capture.
    .PARAMETER Stream
    Native stream.
    .PARAMETER Offset
    First evidence byte offset.
    .PARAMETER ByteCount
    Positive evidence byte length.
    .EXAMPLE
    New-QuietRecallReference -InputObject $result -Stream stderr -Offset 0 -ByteCount 12
    #>
    [CmdletBinding()]param([Parameter(Mandatory)]$InputObject,[Parameter(Mandatory)][ValidateSet('stdout','stderr','terminal')][string]$Stream,[Parameter(Mandatory)][long]$Offset,[Parameter(Mandatory)][long]$ByteCount)
    return [FrenchExDev2.QuietCli.RecallReader]::Reference((Resolve-QuietRecall $InputObject),$Stream,$Offset,$ByteCount)
}
function Invoke-QuietRecall {
    <#
    .SYNOPSIS
    Reanalyzes retained bytes locally without native execution or telemetry writes.
    .PARAMETER InputObject
    Native result or capture.
    .PARAMETER Output
    Streaming callback receiving event and fresh runtime.
    .PARAMETER Complete
    Optional completion callback.
    .PARAMETER Data
    Caller-owned fresh business state.
    .PARAMETER State
    Caller-owned fresh auxiliary state.
    .PARAMETER StdoutMode
    Optional Text or Bytes override.
    .PARAMETER StderrMode
    Optional Text or Bytes override.
    .PARAMETER RecordDelimiter
    Optional record delimiter override.
    .PARAMETER MaxRecordBytes
    Optional positive framing budget override.
    .PARAMETER AllowPartial
    Explicitly accepts missing intervals; resets framing at each gap.
    .PARAMETER RecallId
    Opens a durable identity instead of an in-memory object.
    .PARAMETER RecallRoot
    Explicit durable store root.
    .PARAMETER Projection
    Caller-local delivery projection; never persisted or executed during loading.
    .EXAMPLE
    Invoke-QuietRecall -InputObject $result -Data @{Count=0L} -Output {param($e,$r) $r.Data.Count += $e.ByteCount}
    #>
    [CmdletBinding(DefaultParameterSetName='Input')]param([Parameter(Mandatory,Position=0,ParameterSetName='Input')]$InputObject,[Parameter(Mandatory,ParameterSetName='Id')][string]$RecallId,[Parameter(ParameterSetName='Id')][string]$RecallRoot,[scriptblock]$Output,[scriptblock]$Complete,$Data,[hashtable]$State=@{},[ValidateSet('Text','Bytes')][string]$StdoutMode,[ValidateSet('Text','Bytes')][string]$StderrMode,[AllowNull()][string]$RecordDelimiter,[ValidateRange(1,2147483647)][int]$MaxRecordBytes,[switch]$AllowPartial,[scriptblock]$Projection)
    Import-QuietManagedEngine
    $capture=if($PSCmdlet.ParameterSetName -eq 'Id'){
        $root=if($RecallRoot){$RecallRoot}else{[NullString]::Value}
        [FrenchExDev2.QuietCli.RecallStore]::OpenAsync($root,$RecallId).GetAwaiter().GetResult()
    }else{Resolve-QuietRecall $InputObject}
    if(!$capture.CaptureComplete -and !$AllowPartial){throw 'PartialRecallRequiresAllowPartial'}
    if(!$Output -and !$Complete){throw 'RecallAnalysisCallbackRequired'}
    $request=@{AsObject=$true;Data=$Data;State=$State;StdoutMode=$capture.Settings.StdoutMode;StderrMode=$capture.Settings.StderrMode;MaxRecordBytes=$capture.Settings.MaxRecordBytes;MaxItems=20;MaxOutputBytes=4096}
    if($null -ne $capture.Settings.RecordDelimiter){$request.RecordDelimiter=$capture.Settings.RecordDelimiter}
    foreach($name in @('StdoutMode','StderrMode','MaxRecordBytes')){if($PSBoundParameters.ContainsKey($name)){$request[$name]=$PSBoundParameters[$name]}}
    if($PSBoundParameters.ContainsKey('RecordDelimiter')){if([string]::IsNullOrEmpty($RecordDelimiter)){$request.Remove('RecordDelimiter')}else{$request.RecordDelimiter=$RecordDelimiter}}
    if($Output){$request.Output=$Output};if($Complete){$request.Complete=$Complete}
    if($Projection){$request.Projection=$Projection}
    $runtime=New-QuietRuntime $request
    $runtime.IsRecall=$true
    $runtime|Add-Member NoteProperty CurrentRecallEvent $null
    $runtime|Add-Member NoteProperty CurrentRecallGap $null
    $runtime|Add-Member NoteProperty Recall $capture
    $runtime|Add-Member NoteProperty IgnoredSequences ([Collections.Generic.HashSet[long]]::new())
    $runtime|Add-Member ScriptMethod MarkIgnored {if(!$this.CurrentRecallEvent){throw 'RecallCursorUnavailable'};[void]$this.IgnoredSequences.Add($this.CurrentRecallEvent.Sequence)}
    $watch=[Diagnostics.Stopwatch]::StartNew();$allocation=[FrenchExDev2.QuietCli.AllocationMeter]::new()
    $cursor=0L;$consumed=0L;$count=0L;$readComplete=$true
    $script:QuietRecallDepth++
    try{
        foreach($event in $capture.Events){
            $runtime.CurrentRecallGap=$null
            if($event.ObservedOffset -ne $cursor){
                $runtime.CurrentRecallGap=[FrenchExDev2.QuietCli.RecallGap]::new($cursor,($event.ObservedOffset-$cursor))
                foreach($processor in $runtime.TextStreams.Values){$processor.Dispose()};$runtime.TextStreams.Clear()
            }
            $runtime.CurrentRecallEvent=$event
            $null=Invoke-QuietStreamBlock $runtime $event.Stream $event.Bytes
            $cursor=$event.ObservedOffset+$event.ByteCount;$consumed+=$event.ByteCount;$count++
        }
        $runtime.CurrentRecallEvent=$null
        if($cursor -eq $capture.ReceivedBytes){Complete-QuietStreams $runtime}else{foreach($processor in $runtime.TextStreams.Values){$processor.Dispose()};$runtime.TextStreams.Clear()}
        Complete-QuietAnalysis $runtime
    }catch{
        $readComplete=$false;$runtime.AnalysisComplete=$false
        $runtime.Errors.Add(@{Code='RecallReadFailed';Phase='Recall';Message=$_.Exception.Message})
        if(!$runtime.CompleteInvoked){Complete-QuietAnalysis $runtime}
    }finally{
        foreach($processor in $runtime.TextStreams.Values){$processor.Dispose()}
        $script:QuietRecallDepth--
    }
    $analysisComplete=$runtime.AnalysisComplete -and $capture.CaptureComplete -and $capture.SourceComplete -and $readComplete
    $native=if($null -ne $InputObject -and $InputObject.PSObject.Properties['Execution']){$InputObject.Execution}else{$capture.SourceStatus}
    $result=[pscustomobject]@{
        SchemaVersion=1;Summary='Retained native output reanalyzed locally.';Outcome=$(if($runtime.AnalysisComplete){'Success'}else{'Failed'});Data=$runtime.Data
        InvocationId=$runtime.InvocationId;Context=$runtime.Context;Execution=(ConvertTo-QuietSnapshot @{State='Finalized';Kind='Recall';ElapsedMs=$watch.Elapsed.TotalMilliseconds;Native=$null;Original=$native})
        Error=$runtime.Errors.ToArray();Completeness=(ConvertTo-QuietSnapshot @{Source=($capture.SourceComplete -and $capture.CaptureComplete -and $readComplete);Analysis=$analysisComplete})
        Truncation=[pscustomobject]@{Applied=(!$capture.CaptureComplete);Reasons=$(if($capture.CaptureComplete){@()}else{@('RecallRangesOmitted')})}
        Recall=$capture;Cursor=[pscustomobject]@{Events=$count;Bytes=$consumed;DeclaredIgnoredSequences=@($runtime.IgnoredSequences|Sort-Object)}
        Measurement=[pscustomobject]@{Status='LocalAnalysis';OutputBytes=$null;OutputTokens=$null;ReductionBytes=$null;StorageError=$null;Allocation=$allocation.Stop()}
        Deliveries=[Collections.Generic.List[object]]::new();Internal=@{Sources=[ordered]@{};Request=$request;Administrative=$true;Offline=$true}
    }
    $result.PSObject.TypeNames.Insert(0,'QuietCli2.Result')
    return $result
}
function Export-QuietRecall {
    <#
    .SYNOPSIS
    Explicitly exports inert capture bytes and a versioned integrity manifest.
    .PARAMETER InputObject
    Native result or immutable capture.
    .PARAMETER Path
    New directory or explicit ZIP path; existing files are never overwritten.
    .PARAMETER Zip
    Writes a ZIP64 transport instead of a working directory.
    .PARAMETER Compress
    Exact zlib level from zero to nine; requires Zip.
    .PARAMETER PassThru
    Returns measured transport bytes and actual compression ratio.
    .EXAMPLE
    Export-QuietRecall -InputObject $result -Path ./failure.qrecall
    #>
    [CmdletBinding()]param([Parameter(Mandatory)]$InputObject,[Parameter(Mandatory)][string]$Path,[switch]$Zip,[ValidateRange(0,9)][int]$Compress=6,[switch]$PassThru)
    if($PSBoundParameters.ContainsKey('Compress') -and !$Zip){throw 'CompressRequiresZip'}
    $transport=[FrenchExDev2.QuietCli.RecallArchive]::ExportAsync((Resolve-QuietRecall $InputObject),$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path),[bool]$Zip,$Compress).GetAwaiter().GetResult()
    if($PassThru){return $transport}
}
function Import-QuietRecall {
    <#
    .SYNOPSIS
    Imports verified inert capture data within an explicit retained-byte budget.
    .PARAMETER Path
    Archive path.
    .PARAMETER MaxBytes
    Optional native-byte ceiling; All uses bounded-memory disk streaming.
    .PARAMETER RecallRoot
    Destination store for a ZIP import; a directory is opened in place.
    .EXAMPLE
    Import-QuietRecall -Path ./failure.qrecall -MaxBytes 64MiB
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$Path,$MaxBytes='All',[string]$RecallRoot)
    Import-QuietManagedEngine
    $budget=[FrenchExDev2.QuietCli.RecallOptions]::ParseSize([string]$MaxBytes)
    $root=if($RecallRoot){$RecallRoot}else{[NullString]::Value}
    return [FrenchExDev2.QuietCli.RecallArchive]::ImportAsync($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path),$budget,$root).GetAwaiter().GetResult()
}
function Invoke-QuietSavedRecallRequest {
    <#
    .SYNOPSIS
    Routes quiet -RecallId before native resolution, probing or lifecycle orchestration.
    .PARAMETER Request
    Validated replay-only facade options.
    #>
    param([hashtable]$Request)
    $options=$Request.ReplayOptions
    $root=if($Request.ContainsKey('RecallRoot')){[string]$Request.RecallRoot}else{''}
    $result=Invoke-QuietRecall -RecallId $Request.RecallId -RecallRoot $root @options
    if($Request.ContainsKey('AsObject') -and $Request.AsObject){return $result}
    Out-QuietResult $result -AsYaml:($Request.ContainsKey('AsYaml') -and $Request.AsYaml) -MaxItems $Request.MaxItems -MaxOutputBytes $Request.MaxOutputBytes -Tokenizer $Request.Tokenizer
}
function Save-QuietRecall {
    <#
    .SYNOPSIS
    Explicitly saves existing evidence into the durable catalog, optionally producing ZIP transport.
    .PARAMETER InputObject
    Local result or capture; only retained bytes can be saved after execution.
    .PARAMETER RecallName
    Optional nonunique display name.
    .PARAMETER RecallRoot
    Explicit store root; defaults to durable user data.
    .PARAMETER Zip
    Also produces an adjacent ZIP64 transport.
    .PARAMETER Compress
    Exact zlib level zero through nine; requires Zip.
    #>
    [CmdletBinding()]param([Parameter(Mandatory,Position=0)]$InputObject,[string]$RecallName,[string]$RecallRoot,[switch]$Zip,[ValidateRange(0,9)][int]$Compress=6)
    if($PSBoundParameters.ContainsKey('Compress') -and !$Zip){throw 'CompressRequiresZip'}
    $capture=Resolve-QuietRecall $InputObject
    $root=if($RecallRoot){[IO.Path]::GetFullPath($RecallRoot,$PWD.Path)}else{[FrenchExDev2.QuietCli.RecallStore]::DefaultRoot}
    $name=if($PSBoundParameters.ContainsKey('RecallName')){$RecallName}elseif($null -ne $capture.RecallName){$capture.RecallName}else{[NullString]::Value}
    $saved=[FrenchExDev2.QuietCli.RecallStore]::SaveDirectoryAsync($capture,(Join-Path $root $capture.RecallId),$name).GetAwaiter().GetResult()
    if($Zip){$null=[FrenchExDev2.QuietCli.RecallArchive]::ExportAsync($saved,($saved.StoragePath+'.zip'),$true,$Compress).GetAwaiter().GetResult()}
    return $saved
}
function Get-QuietSavedRecall {
    <#
    .SYNOPSIS
    Finds durable recalls using metadata only, without reading native content.
    .PARAMETER RecallId
    Optional exact identity.
    .PARAMETER RecallName
    Optional wildcard display-name filter.
    .PARAMETER RecallRoot
    Explicit store root.
    .PARAMETER MaxItems
    Maximum returned metadata rows.
    #>
    [CmdletBinding()]param([string]$RecallId,[string]$RecallName,[string]$RecallRoot,[ValidateRange(1,10000)][int]$MaxItems=20)
    Import-QuietManagedEngine
    $root=if($RecallRoot){$RecallRoot}else{[NullString]::Value}
    $id=if($RecallId){[FrenchExDev2.QuietCli.RecallStore]::NormalizeId($RecallId)}else{$null}
    [FrenchExDev2.QuietCli.RecallStore]::ListAsync($root).GetAwaiter().GetResult()|Where-Object {(!$id -or $_.RecallId -eq $id) -and (!$RecallName -or $_.RecallName -like $RecallName)}|Select-Object -First $MaxItems
}
