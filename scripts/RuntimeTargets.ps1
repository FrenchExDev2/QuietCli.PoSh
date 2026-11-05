# Objectif : Centraliser les architectures livrées et vérifier leurs véritables en-têtes binaires.
function Get-QuietRuntimeTargets {
    <#
    .SYNOPSIS
    Reads the explicit release platform catalogue without running a binary.
    .PARAMETER WorkspaceRoot
    QuietCli2 workspace.
    #>
    param([string]$WorkspaceRoot)
    $catalogue=Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/runtime-targets.json') -Encoding utf8 -Raw|ConvertFrom-Json
    return $catalogue.Targets
}
function Get-QuietElfHeader {
    <#
    .SYNOPSIS
    Reads a bounded ELF64 little-endian header and determines whether it requests an interpreter.
    .PARAMETER Path
    Native Linux executable; never loaded into PowerShell.
    #>
    param([string]$Path)
    $stream=[IO.File]::OpenRead($Path);$reader=[IO.BinaryReader]::new($stream)
    try{
        $header=$reader.ReadBytes(64)
        if($header.Length -ne 64 -or $header[0] -ne 127 -or $header[1] -ne 69 -or $header[2] -ne 76 -or $header[3] -ne 70 -or $header[4] -ne 2 -or $header[5] -ne 1){throw 'InvalidElf64Header'}
        $offset=[BitConverter]::ToUInt64($header,32);$size=[BitConverter]::ToUInt16($header,54);$count=[BitConverter]::ToUInt16($header,56)
        if($size -lt 56 -or $count -gt 1024 -or $offset -gt $stream.Length -or $offset+[long]$count*$size -gt $stream.Length){throw 'InvalidElfProgramHeaders'}
        $interpreter=$false
        for($index=0;$index -lt $count;$index++){$stream.Position=$offset+[long]$index*$size;if($reader.ReadUInt32() -eq 3){$interpreter=$true}}
        return [pscustomobject]@{Machine=[BitConverter]::ToUInt16($header,18);HasInterpreter=$interpreter}
    }finally{$reader.Dispose();$stream.Dispose()}
}
function Assert-QuietRuntimePublication {
    <#
    .SYNOPSIS
    Checks both managed assembly and apphost architectures against the release catalogue.
    .PARAMETER Directory
    One RID publication directory.
    .PARAMETER Target
    Explicit catalogue entry.
    #>
    param([string]$Directory,$Target)
    if((Get-QuietPeMachine (Join-Path $Directory 'QuietCli.Engine.dll')) -ne $Target.ManagedMachine){throw ('ManagedArchitectureMismatch: '+$Target.Rid)}
    $apphost=Join-Path $Directory $Target.Apphost
    $machine=if($Target.NativeFormat -eq 'PE'){Get-QuietPeMachine $apphost}else{(Get-QuietElfHeader $apphost).Machine}
    if($machine -ne $Target.NativeMachine){throw ('ApphostArchitectureMismatch: '+$Target.Rid)}
}
function Assert-QuietPtyPublications {
    <#
    .SYNOPSIS
    Checks that each shipped Linux bridge is static, has the expected machine and matches its source receipt.
    .PARAMETER WorkspaceRoot
    QuietCli2 workspace.
    #>
    param([string]$WorkspaceRoot)
    $module=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh'
    $source=(Get-FileHash (Join-Path $module 'native/quietcli-pty.c') -Algorithm SHA256).Hash
    foreach($target in Get-QuietRuntimeTargets $WorkspaceRoot|Where-Object Pty){
        $directory=Join-Path $module ('resources/transport/'+$target.Rid);$path=Join-Path $directory quietcli-pty
        $header=Get-QuietElfHeader $path
        $receipt=Get-Content (Join-Path $directory build.json) -Encoding utf8 -Raw|ConvertFrom-Json
        if($header.Machine -ne $target.NativeMachine -or $header.HasInterpreter -or $receipt.SourceSHA256 -cne $source -or $receipt.ExecutableSHA256 -cne (Get-FileHash $path -Algorithm SHA256).Hash){throw ('PtyPublicationInvalid: '+$target.Rid)}
    }
}
