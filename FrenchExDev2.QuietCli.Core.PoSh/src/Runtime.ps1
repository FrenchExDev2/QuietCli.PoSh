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
        AnalysisComplete=$true;Errors=[Collections.Generic.List[object]]::new();CallbackMs=0.0;NativeStarted=$false;StartState='NotStarted';CompleteInvoked=$false;InputClosed=$false;Completed=$false;Handler=$null
        Decoders=@{stdout=[Text.UTF8Encoding]::new($false,$true).GetDecoder();stderr=[Text.UTF8Encoding]::new($false,$true).GetDecoder();terminal=[Text.UTF8Encoding]::new($false,$true).GetDecoder()}
        Pending=@{stdout='';stderr='';terminal=''}
    }
    if($Request.ContainsKey('Data')){$runtime.Data=$Request.Data}
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
    if($Runtime.Completed){return $null}
    $packet=Send-QuietRequest @{Action='next';InvocationId=$Runtime.InvocationId}
    $data=$packet.Header.Data;$Runtime.Execution=$data.Execution
    if($data.Completed){$Runtime.Completed=$true;Set-QuietLifecycle $Runtime Draining;return $null}
    if(!$packet.Payload.Length){return $null}
    $stream=$data.Stream
    $mode=if($stream -eq 'stderr'){$Runtime.Request.StderrMode}else{$Runtime.Request.StdoutMode}
    $event=[pscustomobject]@{Stream=$stream;Kind=$mode;Bytes=$packet.Payload;ByteCount=$packet.Payload.Length;Text=$null}
    if($mode -eq 'Text' -and $Runtime.AnalysisComplete){
        try{
            $characters=[char[]]::new($packet.Payload.Length*2+2)
            $count=$Runtime.Decoders[$stream].GetChars($packet.Payload,0,$packet.Payload.Length,$characters,0,$false)
            $event.Text=[string]::new($characters,0,$count)
            if($Runtime.Request.ContainsKey('RecordDelimiter')){
                $pending=$Runtime.Pending[$stream]+$event.Text;$delimiter=[string]$Runtime.Request.RecordDelimiter
                while(($position=$pending.IndexOf($delimiter,[StringComparison]::Ordinal)) -ge 0){
                    if([Text.Encoding]::UTF8.GetByteCount($pending.Substring(0,$position)) -gt $Runtime.Request.MaxRecordBytes){throw 'RecordTooLarge'}
                    $record=[pscustomobject]@{Stream=$stream;Kind='Text';Text=$pending.Substring(0,$position);Bytes=$null;ByteCount=$null}
                    Invoke-QuietOutputCallback $Runtime $record
                    $pending=$pending.Substring($position+$delimiter.Length)
                }
                if([Text.Encoding]::UTF8.GetByteCount($pending) -gt $Runtime.Request.MaxRecordBytes){throw 'RecordTooLarge'}
                $Runtime.Pending[$stream]=$pending
                return $event
            }
        }catch{$Runtime.AnalysisComplete=$false;$Runtime.Errors.Add(@{Code='DecodeOrFramingFailed';Phase='Output';Message=$_.Exception.Message});return $null}
    }
    Invoke-QuietOutputCallback $Runtime $event
    return $event
}
