function New-QuietRuntime {
    <#
.SYNOPSIS
Creates one fresh caller-local runtime and attaches interactive adapters.
    .PARAMETER Request
    Explicit call options and native argument vector.
    #>
    param([hashtable]$Request)
    $parent=if($script:QuietStack.Count){$script:QuietStack.Peek()}else{$null}
    $context=if($Request.ContainsKey('Context')){$Request.Context}elseif($parent){$parent.Context}else{$null}
    $id=[guid]::NewGuid().ToString('N')
    $runtime=[pscustomobject]@{
        InvocationId=$id;ParentId=$(if($parent){$parent.InvocationId}else{$null});RootId=$(if($parent){$parent.RootId}else{$id});SessionId=$script:QuietSession;Context=$context
        Request=$Request;Data=$null;State=$(if($Request.ContainsKey('State')){$Request.State}else{@{}})
        Lifecycle='Created';Execution=$null;Children=[Collections.Generic.List[object]]::new();Sources=[ordered]@{}
        AnalysisComplete=$true;Errors=[Collections.Generic.List[object]]::new();CallbackMs=0.0;CompleteAllocation=$null;NativeStarted=$false;StartState='NotStarted';CompleteInvoked=$false;InputClosed=$false;Completed=$false;Handler=$null
        TextStreams=@{};RecallCollector=$null;RecallWriter=$null;RecallSaveFailed=$false;IsRecall=$false
    }
    if($Request.ContainsKey('Data')){$runtime.Data=$Request.Data}
    $name=if($Request.ContainsKey('RecallName')){[string]$Request.RecallName}else{[NullString]::Value}
    if($Request.ContainsKey('SaveRecall') -and $Request.SaveRecall){
        $root=Resolve-QuietRecallRoot $(if($Request.ContainsKey('RecallRoot')){[string]$Request.RecallRoot}else{''})
        $runtime.RecallWriter=[FrenchExDev2.QuietCli.RecallStore]::CreateAsync($root,$name,(Get-QuietRecallSettings $Request)).GetAwaiter().GetResult()
    }
    if($Request.ContainsKey('RecallOptions')){
        $id=if($runtime.RecallWriter){$runtime.RecallWriter.RecallId}else{[NullString]::Value}
        $runtime.RecallCollector=[FrenchExDev2.QuietCli.RecallCollector]::new($Request.RecallOptions,$id,$name)
    }
    $runtime.PSObject.TypeNames.Insert(0,'QuietCli2.Runtime')
    $control=Get-Command Invoke-QuietControl -CommandType Function
    $write=Get-Command Write-QuietInput -CommandType Function
    $read=Get-Command Read-QuietEvent -CommandType Function
    $runtime|Add-Member ScriptMethod WriteBytes {param([byte[]]$Bytes)& $write $this $Bytes}.GetNewClosure()
    $runtime|Add-Member ScriptMethod WriteText {param([string]$Text)& $write $this ([Text.Encoding]::UTF8.GetBytes($Text))}.GetNewClosure()
    $runtime|Add-Member ScriptMethod CompleteInput {& $control $this eof;$this.InputClosed=$true}.GetNewClosure()
    $runtime|Add-Member ScriptMethod Cancel {& $control $this cancel}.GetNewClosure()
    $runtime|Add-Member ScriptMethod Resize {param([int]$Columns,[int]$Rows)& $control $this resize @{Columns=$Columns;Rows=$Rows}}.GetNewClosure()
    $runtime|Add-Member ScriptMethod ReadEvent {& $read $this}.GetNewClosure()
    return $runtime
}
function Invoke-QuietControl {
    <#
.SYNOPSIS
Sends a lifecycle control for the runtime's owned native child.
    .PARAMETER Runtime
    Active invocation.
    .PARAMETER Action
    eof, cancel or resize.
    .PARAMETER Options
    Additional control fields.
    #>
    param($Runtime,[string]$Action,[hashtable]$Options=@{})
    if($Runtime.IsRecall){throw 'ProcessControlUnavailableDuringRecall'}
    if(!$Runtime.NativeStarted -or $Runtime.Completed){throw 'NativeSessionNotRunning'}
    $header=@{Action=$Action;InvocationId=$Runtime.InvocationId};foreach($key in $Options.Keys){$header[$key]=$Options[$key]}
    $null=Send-QuietRequest $header
}
function Write-QuietInput {
    <#
.SYNOPSIS
Writes input in bounded blocks while consuming output during back-pressure.
    .PARAMETER Runtime
    Active invocation.
    .PARAMETER Bytes
    Explicit input bytes; not retained by the engine after writing.
    #>
    param($Runtime,[byte[]]$Bytes)
    if($Runtime.IsRecall){throw 'ProcessInputUnavailableDuringRecall'}
    if($Runtime.InputClosed){throw 'InputAlreadyClosed'}
    for($offset=0;$offset -lt $Bytes.Length;$offset+=$count){
        $count=[Math]::Min($script:QuietProtocol.BlockSize,$Bytes.Length-$offset);$block=[byte[]]::new($count);[Array]::Copy($Bytes,$offset,$block,0,$count)
        while(!(Send-QuietRequest @{Action='input';InvocationId=$Runtime.InvocationId} $block).Header.Data.Accepted){
            $null=Read-QuietEvent $Runtime
            if($Runtime.Completed){throw 'InputProcessExited'}
        }
    }
}
function Invoke-QuietOutputCallback {
    <#
.SYNOPSIS
Dispatches a transient event without retaining it in the runtime.
    .PARAMETER Runtime
    Active invocation.
    .PARAMETER Event
    Current native event.
    #>
    param($Runtime,$Event)
    if(!$Runtime.AnalysisComplete -or !$Runtime.Request.ContainsKey('Output')){return}
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try{$null=Invoke-QuietCallbackValue $Runtime.Request.Output @($Event,$Runtime) -NoOutput}
    catch{$Runtime.AnalysisComplete=$false;$Runtime.Errors.Add(@{Code='OutputCallbackFailed';Phase='Output';Message=$_.Exception.Message})}
    finally{$Runtime.CallbackMs+=$watch.Elapsed.TotalMilliseconds}
}
function Read-QuietEvent {
    <#
.SYNOPSIS
Consumes one bounded native frame and optionally decodes or frames its text.
    .PARAMETER Runtime
    Active invocation; only unfinished delimiter fragments are retained.
    #>
    param($Runtime)
    if($Runtime.IsRecall){throw 'ProcessControlUnavailableDuringRecall'}
    if($Runtime.Completed){return $null}
    $packet=Send-QuietRequest @{Action='next';InvocationId=$Runtime.InvocationId}
    $data=$packet.Header.Data;$Runtime.Execution=$data.Execution
    if($data.Completed){$Runtime.Completed=$true;Set-QuietLifecycle $Runtime Draining;return $null}
    if(!$packet.Payload.Length){return $null}
    $stream=$data.Stream
    if($Runtime.RecallWriter -and !$Runtime.RecallSaveFailed){
        try{[void]$Runtime.RecallWriter.AppendAsync($stream,$packet.Payload).GetAwaiter().GetResult()}
        catch{$Runtime.RecallSaveFailed=$true;$Runtime.Errors.Add(@{Code='RecallWriteFailed';Phase='SaveRecall';Message=$_.Exception.Message})}
    }
    if($Runtime.RecallCollector){$Runtime.RecallCollector.Append($stream,$packet.Payload)}
    Invoke-QuietStreamBlock $Runtime $stream $packet.Payload
}
function Invoke-QuietStreamBlock {
    <#
    .SYNOPSIS
    Shares strict decoding, framing and callback dispatch between live and offline analysis.
    .PARAMETER Runtime
    Fresh analysis runtime.
    .PARAMETER Stream
    Native stream name.
    .PARAMETER Bytes
    One transient native block.
    #>
    param($Runtime,[string]$Stream,[byte[]]$Bytes)
    $mode=if($stream -eq 'stderr'){$Runtime.Request.StderrMode}else{$Runtime.Request.StdoutMode}
    $event=[pscustomobject]@{Stream=$stream;Kind=$mode;Bytes=$Bytes;ByteCount=$Bytes.Length;Text=$null}
    if($mode -eq 'Text' -and $Runtime.AnalysisComplete){
        try{
            if(!$Runtime.TextStreams.ContainsKey($stream)){
                Import-QuietManagedEngine
                $delimiter=if($Runtime.Request.ContainsKey('RecordDelimiter')){[string]$Runtime.Request.RecordDelimiter}else{[System.Management.Automation.Language.NullString]::Value}
                $Runtime.TextStreams[$stream]=[FrenchExDev2.QuietCli.TextStreamState]::new($delimiter,[int]$Runtime.Request.MaxRecordBytes)
            }
            $processor=$Runtime.TextStreams[$stream]
            $event.Text=$processor.Decode($Bytes)
            if($Runtime.Request.ContainsKey('RecordDelimiter')){
                foreach($text in $processor.Frame($event.Text)){
                    $record=[pscustomobject]@{Stream=$stream;Kind='Text';Text=$text;Bytes=$null;ByteCount=$null}
                    Invoke-QuietOutputCallback $Runtime $record
                }
                return $event
            }
        }catch{$Runtime.AnalysisComplete=$false;$Runtime.Errors.Add(@{Code='DecodeOrFramingFailed';Phase='Output';Message=$_.Exception.Message});return $null}
    }
    Invoke-QuietOutputCallback $Runtime $event
    return $event
}
