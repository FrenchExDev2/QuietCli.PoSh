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
        $root=Resolve-QuietRecallRoot $RecallRoot
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
    $runtime=New-QuietRuntime -Request $request -Parent $(if($script:QuietStack.Count){$script:QuietStack.Peek()}) -SessionId $script:QuietSession
    $runtime.IsRecall=$true
    $runtime.Recall=$capture
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
            $null=$runtime.StreamBlock($event.Stream,$event.Bytes)
            $cursor=$event.ObservedOffset+$event.ByteCount;$consumed+=$event.ByteCount;$count++
        }
        $runtime.CurrentRecallEvent=$null
        if($cursor -eq $capture.ReceivedBytes){$runtime.CompleteStreams()}else{foreach($processor in $runtime.TextStreams.Values){$processor.Dispose()};$runtime.TextStreams.Clear()}
        $runtime.CompleteAnalysis()
    }catch{
        $readComplete=$false;$runtime.AnalysisComplete=$false
        $runtime.Errors.Add(@{Code='RecallReadFailed';Phase='Recall';Message=$_.Exception.Message})
        if(!$runtime.CompleteInvoked){$runtime.CompleteAnalysis()}
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

function Resolve-QuietRecall {
    <#
    .SYNOPSIS
    Accepts an immutable capture or a result containing one.
    .PARAMETER InputObject
    Capture or native result.
    #>
    param($InputObject)
    [FrenchExDev2.QuietCli.Cmdlets.RecallCommandSupport]::ResolveCapture($InputObject)
}
function Resolve-QuietRecallRoot {
    <#
    .SYNOPSIS
    Resolves an explicit Recall store or the configured/default durable location.
    .PARAMETER Path
    Optional explicit store root.
    #>
    param([string]$Path)
    [FrenchExDev2.QuietCli.Cmdlets.RecallCommandSupport]::ResolveRoot($Path,$PWD.Path)
}
