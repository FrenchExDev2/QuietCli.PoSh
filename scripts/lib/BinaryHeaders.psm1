#requires -Version 7.6
function Get-QuietPeMachine {
    <#
    .SYNOPSIS
    Reads the actual PE machine field without loading or executing a managed assembly or native apphost.
    .PARAMETER Path
    Compiled Windows executable or assembly.
    #>
    param([string]$Path)
    $stream=[IO.File]::OpenRead($Path);$reader=[IO.BinaryReader]::new($stream)
    try{
        if($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5a4d){throw 'InvalidPeHeader'}
        $stream.Position=0x3c;$offset=$reader.ReadUInt32()
        if($offset -gt $stream.Length-6){throw 'InvalidPeOffset'}
        $stream.Position=$offset
        if($reader.ReadUInt32() -ne 0x4550){throw 'InvalidPeSignature'}
        return $reader.ReadUInt16()
    }finally{$reader.Dispose();$stream.Dispose()}
}
Export-ModuleMember -Function 'Get-QuietPeMachine'
