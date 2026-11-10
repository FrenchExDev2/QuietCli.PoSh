#requires -Version 7.6
function New-QuietReportStream {
    <#
    .SYNOPSIS
    Creates caller-owned incremental UTF-8 tail state.
    .PARAMETER Path
    Explicit run-owned diagnostic file to observe.
    #>
    param([string]$Path)
    return @{Path=$Path;Position=0L;Decoder=[Text.UTF8Encoding]::new($false,$true).GetDecoder();Pending='';Lines=[Collections.Generic.Queue[string]]::new();TotalLines=0L;TotalBytes=0L}
}
function Read-QuietReportStream {
    <#
    .SYNOPSIS
    Reads newly appended bytes once, preserving incomplete UTF-8 and keeping only a bounded tail.
    .PARAMETER State
    State returned by New-QuietReportStream.
    .PARAMETER MaxLines
    Maximum retained/newly delivered tail lines.
    #>
    param([hashtable]$State,[ValidateRange(1,100)][int]$MaxLines=8)
    $new=[Collections.Generic.Queue[string]]::new()
    if(!(Test-Path -LiteralPath $State.Path -PathType Leaf)){return ,@()}
    $stream=[IO.FileStream]::new($State.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{
        if($stream.Length -lt $State.Position){$State.Position=0L;$State.Decoder.Reset();$State.Pending=''}
        $stream.Position=$State.Position
        $bytes=[byte[]]::new(65536);$chars=[char[]]::new(65540)
        $count=$stream.ReadAsync($bytes,0,$bytes.Length).GetAwaiter().GetResult()
        if($count){
            $State.Position=$stream.Position;$State.TotalBytes+=$count
            $length=$State.Decoder.GetChars($bytes,0,$count,$chars,0,$false)
            $text=$State.Pending+[string]::new($chars,0,$length)
            $parts=$text.Split("`n")
            for($index=0;$index -lt $parts.Length-1;$index++){
                $line=$parts[$index].TrimEnd("`r")
                if($line.Length -gt 2048){$line=$line.Substring(0,2048)+'…'}
                $State.TotalLines++
                while($State.Lines.Count -ge $MaxLines){$null=$State.Lines.Dequeue()}
                while($new.Count -ge $MaxLines){$null=$new.Dequeue()}
                $State.Lines.Enqueue($line);$new.Enqueue($line)
            }
            $State.Pending=$parts[-1]
            if($State.Pending.Length -gt 2048){$State.Pending=$State.Pending.Substring($State.Pending.Length-2048)}
        }
    }finally{$stream.Dispose()}
    return ,@($new)
}
