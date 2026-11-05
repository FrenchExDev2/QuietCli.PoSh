function Resolve-QuietManagedTarget {
    <#
    .SYNOPSIS
    Selects a compatible build from the actual host CLR, independent of the PowerShell release channel.
    .PARAMETER RuntimeMajor
    Actual CLR major version; explicit values allow independent compatibility assertions.
    #>
    param([int]$RuntimeMajor=[Environment]::Version.Major)
    if($RuntimeMajor -ge 11){return @{Framework='net11.0';Directory='lib/engine'}}
    if($RuntimeMajor -eq 10){return @{Framework='net10.0';Directory='lib/inprocess'}}
    throw 'ManagedEngineRequiresNet10OrLater'
}
function Import-QuietManagedEngine {
    <#
    .SYNOPSIS
    Loads the verified build compatible with the actual CLR, including PowerShell preview hosts.
    #>
    if($script:QuietManagedAssembly){return}
    $target=Resolve-QuietManagedTarget
    Assert-QuietResources
    $directory=Join-Path $script:QuietRoot $target.Directory
    $build=Get-Content (Join-Path $directory 'build-manifest.json') -Raw -Encoding utf8|ConvertFrom-Json
    if(@($build.Binaries|Where-Object Path -CEQ 'QuietCli.Engine.dll').Count -ne 1){throw 'EngineBuildIdentityInvalid'}
    foreach($file in $build.Binaries){
        if([IO.Path]::GetFileName($file.Path) -cne $file.Path){throw 'EngineBuildIdentityUnsafePath'}
        if((Get-FileHash (Join-Path $directory $file.Path) -Algorithm SHA256).Hash -cne $file.SHA256){throw 'EngineBinaryIntegrityFailed'}
    }
    $configuration=Get-Content (Join-Path $directory 'QuietCli.Engine.runtimeconfig.json') -Raw -Encoding utf8|ConvertFrom-Json
    if($configuration.runtimeOptions.tfm -cne $target.Framework){throw 'ManagedEngineTargetMismatch'}
    $assembly=Join-Path $directory 'QuietCli.Engine.dll'
    $hash=(Get-FileHash $assembly -Algorithm SHA256).Hash
    $loaded=[AppDomain]::CurrentDomain.GetData('QuietCli2.ManagedEngineIdentity')
    if($loaded -and $loaded -cne $hash){throw 'ManagedEngineAlreadyLoaded: restart PowerShell after rebuilding.'}
    $script:QuietManagedAssembly=[Reflection.Assembly]::LoadFrom($assembly)
    [AppDomain]::CurrentDomain.SetData('QuietCli2.ManagedEngineIdentity',$hash)
}
function New-QuietByteRecordFramer {
    <#
    .SYNOPSIS
    Creates a compiled local framer without IPC or per-byte PowerShell dispatch.
    .PARAMETER Delimiter
    Exact record delimiter byte.
    .PARAMETER MaxRecordBytes
    Maximum retained unfinished record size.
    #>
    [CmdletBinding()]param([byte]$Delimiter=10,[ValidateRange(1,2147483647)][int]$MaxRecordBytes=1048576)
    Import-QuietManagedEngine
    return [FrenchExDev2.QuietCli.ByteRecordFramer]::new($Delimiter,$MaxRecordBytes)
}
function Start-QuietEngine {
    <#
.SYNOPSIS
Starts the private engine lazily, without transferring business objects. #>
    if($script:QuietEngine -and ($script:QuietEngine.Mode -eq 'InProcess' -or !$script:QuietEngine.Process.HasExited)){return}
    $mode=if($env:QUIETCLI2_ENGINE_MODE){$env:QUIETCLI2_ENGINE_MODE}else{'Auto'}
    if($mode -notin @('Auto','Process','InProcess')){throw 'InvalidEngineMode'}
    if($mode -eq 'Auto'){$mode=if([Environment]::Version.Major -ge 10){'InProcess'}else{'Process'}}
    if($mode -eq 'InProcess'){
        Import-QuietManagedEngine
        $database=if($env:QUIETCLI2_DATABASE){$env:QUIETCLI2_DATABASE}else{Join-Path ([Environment]::GetFolderPath('UserProfile')) '.quietcli2/gains.sqlite'}
        $hostEngine=[FrenchExDev2.QuietCli.InProcessEngine]::CreateAsync([IO.Path]::GetFullPath($database),$script:QuietRoot).GetAwaiter().GetResult()
        $script:QuietEngine=@{Mode='InProcess';Host=$hostEngine;Database=$database;Requests=0L;DirectRequests=0L;MetadataJsonRequests=0L;InputBytes=0L;OutputBytes=0L;Info=$null;Broken=$false}
        $script:QuietEngine.Info=(Send-QuietRequest @{Action='hello'}).Header.Data
        return
    }
    $rid=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier
    $engineDirectory=Join-Path $script:QuietRoot 'lib/engine'
    $targets=Get-Content (Join-Path $script:QuietRoot 'runtime-targets.json') -Encoding utf8 -Raw|ConvertFrom-Json
    if($rid -cnotin $targets.Targets.Rid){throw ('RuntimeNotDistributed: '+$rid)}
    $engineDirectory=Join-Path $engineDirectory $rid
    $assembly=Join-Path $engineDirectory 'QuietCli.Engine.dll'
    if(!(Test-Path -LiteralPath $assembly)){throw 'EngineNotBuilt: run scripts/Build-Workspace.ps1.'}
    Assert-QuietResources
    $buildPath=Join-Path $engineDirectory 'build-manifest.json'
    if(!(Test-Path -LiteralPath $buildPath)){throw 'EngineBuildIdentityMissing'}
    $build=Get-Content -LiteralPath $buildPath -Encoding utf8 -Raw|ConvertFrom-Json
    if($build.RuntimeIdentifier -cne $rid){throw 'EngineBuildRuntimeMismatch'}
    if(@($build.Binaries|Where-Object Path -CEQ 'QuietCli.Engine.dll').Count -ne 1){throw 'EngineBuildIdentityInvalid'}
    if($IsWindows -and @($build.Binaries|Where-Object Path -CEQ 'QuietCli.Engine.exe').Count -ne 1){throw 'EngineApphostIdentityInvalid'}
    foreach($file in $build.Binaries){
        if([IO.Path]::GetFileName($file.Path) -cne $file.Path){throw 'EngineBuildIdentityUnsafePath'}
        $binary=Join-Path $engineDirectory $file.Path
        if(!(Test-Path -LiteralPath $binary) -or (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash -cne $file.SHA256){throw 'EngineBinaryIntegrityFailed'}
    }
    $database=if($env:QUIETCLI2_DATABASE){$env:QUIETCLI2_DATABASE}else{Join-Path ([Environment]::GetFolderPath('UserProfile')) '.quietcli2/gains.sqlite'}
    $executable=if($IsWindows){Join-Path $engineDirectory 'QuietCli.Engine.exe'}else{(Get-Command dotnet -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source}
    $start=[Diagnostics.ProcessStartInfo]::new($executable)
    if($IsWindows){
        $dotnetDirectory=Split-Path (Get-Command dotnet -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source -Parent
        $architecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToUpperInvariant()
        $start.Environment['DOTNET_ROOT_'+$architecture]=$dotnetDirectory
    }
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    if(!$IsWindows){$start.ArgumentList.Add($assembly)}
    $start.ArgumentList.Add('--database');$start.ArgumentList.Add([IO.Path]::GetFullPath($database));$start.ArgumentList.Add('--module-root');$start.ArgumentList.Add($script:QuietRoot)
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start
    if(!$process.Start()){throw 'EngineStartFailed'}
    # Discard diagnostics through a bounded async copy, keeping this pipe separate from native output.
    $script:QuietEngine=@{Mode='Process';Process=$process;Input=$process.StandardInput.BaseStream;Output=$process.StandardOutput.BaseStream;Database=$database;Requests=0L;DirectRequests=0L;MetadataJsonRequests=0L;InputBytes=0L;OutputBytes=0L;Info=$null;Broken=$false;DiagnosticDrain=$process.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)}
    $script:QuietEngine.Info=(Send-QuietRequest @{Action='hello'}).Header.Data
}
function Send-QuietRequest {
    <#
.SYNOPSIS
Exchanges one bounded metadata frame and an optional transient byte block.
    .PARAMETER Header
    Control metadata, never a business object.
    .PARAMETER Payload
    Native input bytes, at most 16384 bytes.
    #>
    param([hashtable]$Header,[byte[]]$Payload=@())
    if(!$script:QuietEngine){Start-QuietEngine}
    if($script:QuietEngine.Broken){throw 'EngineDisconnected'}
    if($Payload.Length -gt $script:QuietProtocol.BlockSize){throw 'InputBlockTooLarge'}
    $Header.Version=$script:QuietProtocol.Version;$Header.RequestId=[guid]::NewGuid().ToString('N')
    $directRead=$script:QuietEngine.Mode -eq 'InProcess' -and $Header.Action -eq 'next'
    $directControl=$script:QuietEngine.Mode -eq 'InProcess' -and $Header.Action -in @('input','eof','cancel','resize','release')
    $directMetadata=$script:QuietEngine.Mode -eq 'InProcess' -and $Header.Action -in @('hello','start','save','gain','gain-poll','gain-next','gain-release','scrub','shutdown')
    if(!$directRead -and !$directControl -and !$directMetadata){
    $encoded=$script:QuietUtf8.GetBytes((ConvertTo-Json -InputObject $Header -Depth 32 -Compress))
    if($encoded.Length -gt $script:QuietProtocol.HeaderLimit){throw 'ControlFrameTooLarge'}
    $lengths=[byte[]]::new(8)
    [BitConverter]::GetBytes([int]$encoded.Length).CopyTo($lengths,0)
    [BitConverter]::GetBytes([int]$Payload.Length).CopyTo($lengths,4)
    }
    $seconds=30.0
    if($env:QUIETCLI2_IPC_TIMEOUT_SECONDS){$seconds=[double]::Parse($env:QUIETCLI2_IPC_TIMEOUT_SECONDS,[Globalization.CultureInfo]::InvariantCulture)}
    if(![double]::IsFinite($seconds) -or $seconds -lt 0.05 -or $seconds -gt 300){throw 'InvalidIpcTimeout'}
    $deadline=[Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($seconds))
    try{
        if($script:QuietEngine.Mode -eq 'InProcess'){
            if($directRead){$reply=$script:QuietEngine.Host.ReadAsync([string]$Header.InvocationId,[string]$Header.RequestId).WaitAsync($deadline.Token).GetAwaiter().GetResult()}
            elseif($directControl){$reply=$script:QuietEngine.Host.ControlAsync([FrenchExDev2.QuietCli.LocalControl]$Header.Action,[string]$Header.InvocationId,[string]$Header.RequestId,$Payload,[int]$Header['Columns'],[int]$Header['Rows']).WaitAsync($deadline.Token).GetAwaiter().GetResult()}
            elseif($directMetadata){$reply=$script:QuietEngine.Host.MetadataAsync($Header,$script:QuietMetadataAdapter).WaitAsync($deadline.Token).GetAwaiter().GetResult()}
            else{$reply=$script:QuietEngine.Host.RequestAsync($encoded,$Payload).WaitAsync($deadline.Token).GetAwaiter().GetResult()}
            $response=if($reply.Header){$reply.Header}else{ConvertFrom-Json -InputObject $reply.HeaderJson -Depth 48}
            $payloadBytes=$reply.Payload
        }else{
        foreach($bytes in @($lengths,$encoded,$Payload)){
            if($bytes.Length){[void]$script:QuietEngine.Input.WriteAsync($bytes,0,$bytes.Length,$deadline.Token).WaitAsync($deadline.Token).GetAwaiter().GetResult()}
        }
        [void]$script:QuietEngine.Input.FlushAsync($deadline.Token).WaitAsync($deadline.Token).GetAwaiter().GetResult()
        [void]$script:QuietEngine.Output.ReadExactlyAsync([Memory[byte]]::new($lengths),$deadline.Token).AsTask().WaitAsync($deadline.Token).GetAwaiter().GetResult()
        $headerSize=[BitConverter]::ToInt32($lengths,0);$payloadSize=[BitConverter]::ToInt32($lengths,4)
        if($headerSize -lt 2 -or $headerSize -gt $script:QuietProtocol.HeaderLimit -or $payloadSize -lt 0 -or $payloadSize -gt $script:QuietProtocol.BlockSize){throw 'InvalidFrameLength'}
        $headerBytes=[byte[]]::new($headerSize);$payloadBytes=[byte[]]::new($payloadSize)
        [void]$script:QuietEngine.Output.ReadExactlyAsync([Memory[byte]]::new($headerBytes),$deadline.Token).AsTask().WaitAsync($deadline.Token).GetAwaiter().GetResult()
        [void]$script:QuietEngine.Output.ReadExactlyAsync([Memory[byte]]::new($payloadBytes),$deadline.Token).AsTask().WaitAsync($deadline.Token).GetAwaiter().GetResult()
        $response=ConvertFrom-Json -InputObject $script:QuietUtf8.GetString($headerBytes) -Depth 48
        }
        if($response.Version -ne $script:QuietProtocol.Version -or $response.RequestId -ne $Header.RequestId){throw 'ProtocolMismatch'}
        $script:QuietEngine.Requests++
        if($directRead -or $directControl -or $directMetadata){$script:QuietEngine.DirectRequests++}else{$script:QuietEngine.MetadataJsonRequests++}
        if($script:QuietEngine.Mode -eq 'Process'){$script:QuietEngine.InputBytes+=8+$encoded.Length+$Payload.Length;$script:QuietEngine.OutputBytes+=8+$headerSize+$payloadSize}
    }catch{
        $script:QuietEngine.Broken=$true
        try{if($script:QuietEngine.Mode -eq 'InProcess'){$null=$script:QuietEngine.Host.DisposeAsync().AsTask()}elseif(!$script:QuietEngine.Process.HasExited){$script:QuietEngine.Process.Kill($true)}}catch{}
        throw [IO.IOException]::new('EngineCommunicationFailed: '+$_.Exception.GetType().Name,$_.Exception)
    }finally{$deadline.Dispose()}
    if(!$response.Ok){
        $error=[InvalidOperationException]::new('EngineRequestRejected: '+$response.Error.Message)
        $error.Data['QuietCliRequestRejected']=$true;$error.Data['Code']=$response.Error.Code
        throw $error
    }
    return [pscustomobject]@{Header=$response;Payload=$payloadBytes}
}
function Stop-QuietEngine {
    <#
.SYNOPSIS
Closes the owned engine normally and flushes accepted measurement writes. #>
    [CmdletBinding()]param()
    if(!$script:QuietEngine){return}
    if($script:QuietEngine.Mode -eq 'InProcess'){
        try{[void]$script:QuietEngine.Host.DisposeAsync().AsTask().WaitAsync([TimeSpan]::FromSeconds(5)).GetAwaiter().GetResult()}
        finally{$script:QuietEngine=$null}
        return
    }
    try{if(!$script:QuietEngine.Process.HasExited -and !$script:QuietEngine.Broken){$null=Send-QuietRequest @{Action='shutdown'};$script:QuietEngine.Input.Close();[void]$script:QuietEngine.Process.WaitForExitAsync().WaitAsync([TimeSpan]::FromSeconds(5)).GetAwaiter().GetResult()}}
    finally{if(!$script:QuietEngine.Process.HasExited){try{$script:QuietEngine.Process.Kill($true)}catch{}};$script:QuietEngine.Process.Dispose();$script:QuietEngine=$null}
}
function Get-QuietEngine {
    <#
.SYNOPSIS
Returns engine identity and protocol counters, without native output. #>
    [CmdletBinding()]param()
    Start-QuietEngine
    [pscustomobject]@{SessionId=$script:QuietSession;Mode=$script:QuietEngine.Mode;Engine=$script:QuietEngine.Info;Requests=$script:QuietEngine.Requests;DirectRequests=$script:QuietEngine.DirectRequests;MetadataJsonRequests=$script:QuietEngine.MetadataJsonRequests;ProtocolInputBytes=$script:QuietEngine.InputBytes;ProtocolOutputBytes=$script:QuietEngine.OutputBytes;Database=$script:QuietEngine.Database}
}
