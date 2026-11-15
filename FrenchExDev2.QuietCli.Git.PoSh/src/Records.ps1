function New-QuietGitRecordState {
    <#
.SYNOPSIS
Creates a bounded unfinished-record buffer owned by one business parser.
    .PARAMETER Data
    Parsed business state.
    .PARAMETER Delimiter
    Native record delimiter byte.
    .PARAMETER Parser
    Callback receiving exact record bytes and business Data.
    .PARAMETER Finalize
    Optional callback after the final record.
    #>
    param($Data,[byte]$Delimiter,[scriptblock]$Parser,[scriptblock]$Finalize)
    return @{Data=$Data;Delimiter=$Delimiter;Parser=$Parser;Finalize=$Finalize;Pending=(New-QuietByteRecordFramer -Delimiter $Delimiter);MaxRecordBytes=1048576;Records=0L}
}
function Receive-QuietGitRecord {
    <#
.SYNOPSIS
Parses complete byte records and releases each block without storing a native document.
    .PARAMETER Event
    Transient stdout byte event.
    .PARAMETER Runtime
    Child runtime containing explicit parser state in Data.
    #>
    param($Event,$Runtime)
    $state=$Runtime.Data
    if($Event.Stream -eq 'stderr'){if($state.Diagnostics){Add-QuietGitDiagnosticBytes $state.Diagnostics $Event.Bytes};return}
    if($Event.Stream -ne 'stdout'){return}
    foreach($record in $state.Pending.Push($Event.Bytes)){Invoke-QuietGitRecordParser $state $record}
}
function Complete-QuietGitRecord {
    <#
.SYNOPSIS
Finalizes a parser, preserving unterminated last lines without a raw capture.
    .PARAMETER Runtime
    Child runtime whose native streams have been drained.
    #>
    param($Runtime)
    $state=$Runtime.Data
    try{
        $last=$state.Pending.Finish()
        if($null -ne $last){Invoke-QuietGitRecordParser $state $last}
        if($state.Finalize){$values=@(& $state.Finalize $state.Data);if($values.Count -gt 1){throw 'GitFinalizerMustReturnOneValue'};if($values.Count){return $values[0]}}
        return $state.Data
    }finally{$state.Pending.Dispose()}
}
function Invoke-QuietGitRecordParser {
    <#
    .SYNOPSIS
    Applies the same zero-emission contract to terminated and unterminated records.
    .PARAMETER State
    Current bounded record parser.
    .PARAMETER Record
    Exact bytes excluding the delimiter.
    #>
    param($State,[byte[]]$Record)
    $values=@(& $State.Parser $Record $State.Data)
    if($values.Count){throw 'GitRecordParserUnexpectedOutput'}
    $State.Records++
}
function Invoke-QuietGitFieldRecords {
    <#
    .SYNOPSIS
    Groups NUL fields for history, refs, branches and stash using one validated parser.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Arguments
    Exact machine-format Git arguments.
    .PARAMETER Data
    Business result being populated.
    .PARAMETER FieldCount
    Fixed number of fields per business record.
    .PARAMETER Commit
    Zero-emission callback receiving one complete field group and the business object.
    .PARAMETER Role
    Business or observation role.
    #>
    param($Runtime,[string[]]$Arguments,$Data,[ValidateRange(1,64)][int]$FieldCount,[scriptblock]$Commit,[string]$Role='Business')
    $state=@{Business=$Data;Fields=[Collections.Generic.List[object]]::new();FieldCount=$FieldCount;Commit=$Commit}
    Import-QuietGitParser
    $decode=Get-Command ConvertFrom-QuietGitBytes
    $parser={
        param($record,$state)
        if([FrenchExDev2.QuietCli.Git.GitRecords]::Field($record,$state)){
            $values=@(& $state.Commit $state.Fields $state.Business)
            if($values.Count){throw 'GitFieldMapperUnexpectedOutput'}
            $state.Fields.Clear()
        }
    }.GetNewClosure()
    Invoke-QuietGitRecords $Runtime $Arguments $state -Role $Role -Delimiter 0 -Parser $parser -Finalize {
        param($state)
        if($state.Fields.Count){throw 'IncompleteGitFieldGroup'}
        return $state.Business
    }
}
function Invoke-QuietGitRecords {
    <#
.SYNOPSIS
Invokes a Git command with an explicit streaming business record parser.
    .PARAMETER Runtime
    Parent runtime.
    .PARAMETER Arguments
    Effective native argument vector.
    .PARAMETER Data
    Explicit parsed business object.
    .PARAMETER Parser
    Exact-record business parser.
    .PARAMETER Finalize
    Optional business finalizer.
    .PARAMETER Delimiter
    Byte delimiter, LF by default.
    .PARAMETER Role
    Business or auxiliary source role.
    .PARAMETER Codes
    Documented successful exit conditions.
    .PARAMETER Diagnostics
    Optional caller-owned collector from New-QuietGitDiagnosticCollector; receives bounded stderr bytes.
    #>
    param($Runtime,[string[]]$Arguments,$Data,[scriptblock]$Parser,[scriptblock]$Finalize,[byte]$Delimiter=10,[string]$Role='Business',[int[]]$Codes=@(0),[hashtable]$Diagnostics)
    if($Runtime.Request.Transport -ne 'Pipe' -and $Role -eq 'Business'){throw 'ByteRecordBusinessProtocolRequiresPipe: use explicit -Output for terminal control.'}
    $state=New-QuietGitRecordState $Data $Delimiter $Parser $Finalize
    $state.Diagnostics=$Diagnostics
    $receive=Get-Command Receive-QuietGitRecord;$complete=Get-Command Complete-QuietGitRecord
    try{$r=Invoke-QuietGitNative $Runtime $Arguments -Role $Role -Data $state -StdoutMode Bytes -StderrMode Bytes -SuccessExitCodes $Codes -Output {param($e,$r)& $receive $e $r}.GetNewClosure() -Complete {param($r)& $complete $r}.GetNewClosure()}
    finally{$state.Pending.Dispose()}
    if([object]::ReferenceEquals($r.Data,$state)){$r.Data=$state.Data}
    return $r
}
function Invoke-QuietGitRequestedFormat {
    <#
.SYNOPSIS
Preserves explicitly requested formatting as lossless business records, without an alternative hidden execution.
    .PARAMETER Runtime
    Parent runtime.
    .PARAMETER Arguments
    Native vector, preserving the requested format.
    .PARAMETER Name
    Command name.
    .PARAMETER Codes
    Documented exit conditions.
    .PARAMETER Delimiter
    Native delimiter, LF by default.
    #>
    param($Runtime,[string[]]$Arguments,[string]$Name,[int[]]$Codes=@(0),[byte]$Delimiter=10)
    $data=@{Command=$Name;GitVersion=$Runtime.State.DetectedVersion;OutputMode='RequestedFormat';Records=[Collections.Generic.List[object]]::new();Delimiter=$Delimiter;Scope='Exact requested native records; UTF-8 text or an explicit byte representation.'}
    Import-QuietGitParser
    $decode=Get-Command ConvertFrom-QuietGitBytes
    $r=Invoke-QuietGitRecords $Runtime $Arguments $data -Codes $Codes -Delimiter $Delimiter -Parser {param($record,$data)$data.Records.Add((& $decode $record))}.GetNewClosure()
    return $r.Data
}
function New-QuietGitDiagnosticCollector {
    <#
    .SYNOPSIS
    Creates a bounded stderr collector; it keeps native diagnostics for classification, never business output.
    .PARAMETER Limit
    Maximum retained bytes; later bytes are counted and marked as truncated.
    #>
    param([ValidateRange(1,1048576)][int]$Limit=8192)
    return @{Stream=[IO.MemoryStream]::new();Limit=$Limit;Truncated=$false;Bytes=0L}
}
function Add-QuietGitDiagnosticBytes {
    <#
    .SYNOPSIS
    Appends stderr bytes to a collector up to its limit.
    .PARAMETER Collector
    Collector from New-QuietGitDiagnosticCollector.
    .PARAMETER Bytes
    Transient stderr block.
    #>
    param([hashtable]$Collector,[byte[]]$Bytes)
    if($null -eq $Bytes -or !$Bytes.Length){return}
    $Collector.Bytes+=$Bytes.Length
    $room=$Collector.Limit-[int]$Collector.Stream.Length
    if($room -le 0){$Collector.Truncated=$true;return}
    $count=[Math]::Min($room,$Bytes.Length);$Collector.Stream.Write($Bytes,0,$count)
    if($count -lt $Bytes.Length){$Collector.Truncated=$true}
}
function Read-QuietGitDiagnosticText {
    <#
    .SYNOPSIS
    Decodes the retained stderr bytes of a collector (invalid UTF-8 is replaced, not rejected).
    .PARAMETER Collector
    Collector from New-QuietGitDiagnosticCollector.
    #>
    param([hashtable]$Collector)
    if(!$Collector){return ''}
    return [Text.Encoding]::UTF8.GetString($Collector.Stream.ToArray())
}
