# Objective: Verify actual ELF hardening rather than relying on compiler flags alone.
function Assert-PtyHardening {
    <#
    .SYNOPSIS
    Checks static PIE, RELRO, immediate binding and a non-executable stack in each shipped bridge.
    .PARAMETER WorkspaceRoot
    QuietCli2 monorepo root containing the four published Linux bridges.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    foreach($rid in @('linux-x64','linux-musl-x64','linux-arm64','linux-musl-arm64')){
        $path=Join-Path $WorkspaceRoot "FrenchExDev2.QuietCli.Core.PoSh/resources/transport/$rid/quietcli-pty"
        $bytes=[IO.File]::ReadAllBytes($path)
        if($bytes.Length -lt 64 -or [BitConverter]::ToUInt32($bytes,0) -ne 0x464c457f -or $bytes[4] -ne 2 -or $bytes[5] -ne 1){throw "Expected little-endian ELF64: $rid"}
        $relro=$false;$stack=$false;$now=$false;$interpreter=$false
        $offset=[BitConverter]::ToInt64($bytes,32)
        $size=[BitConverter]::ToUInt16($bytes,54)
        $count=[BitConverter]::ToUInt16($bytes,56)
        if($size -ne 56 -or $offset -lt 64 -or $offset+$size*$count -gt $bytes.Length){throw "Invalid ELF program headers: $rid"}
        for($i=0;$i -lt $count;$i++){
            $header=[int]($offset+$i*$size)
            $type=[BitConverter]::ToUInt32($bytes,$header)
            if($type -eq 0x6474e552){$relro=$true}
            if($type -eq 0x6474e551){$stack=([BitConverter]::ToUInt32($bytes,$header+4) -band 1) -eq 0}
            if($type -eq 3){$interpreter=$true}
            if($type -eq 2){
                $start=[BitConverter]::ToUInt64($bytes,$header+8)
                $length=[BitConverter]::ToUInt64($bytes,$header+32)
                if($start -gt $bytes.Length -or $length -gt $bytes.Length-$start -or $length%16){throw "Invalid ELF dynamic segment: $rid"}
                for($j=$start;$j -lt $start+$length;$j+=16){
                    $tag=[BitConverter]::ToUInt64($bytes,[int]$j)
                    $value=[BitConverter]::ToUInt64($bytes,[int]$j+8)
                    if($tag -eq 0){break}
                    if($tag -eq 24 -or ($tag -eq 30 -and ($value -band 8)) -or ($tag -eq 0x6ffffffb -and ($value -band 1))){$now=$true}
                }
            }
        }
        $pie=[BitConverter]::ToUInt16($bytes,16) -eq 3
        if(!$pie -or !$relro -or !$stack -or !$now -or $interpreter){throw "ELF hardening missing: $rid"}
        [pscustomobject]@{Runtime=$rid;PIE=$pie;RELRO=$relro;NonExecutableStack=$stack;BindNow=$now;Static=(!$interpreter)}
    }
}
