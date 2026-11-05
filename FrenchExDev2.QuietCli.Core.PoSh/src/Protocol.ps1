function Start-QuietEngine {
    <#
.SYNOPSIS
Starts the private engine lazily, without transferring business objects. #>
    if($script:QuietEngine -and !$script:QuietEngine.Process.HasExited){return}
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
    $script:QuietEngine=@{Process=$process;Input=$process.StandardInput.BaseStream;Output=$process.StandardOutput.BaseStream;Database=$database;Requests=0L;InputBytes=0L;OutputBytes=0L;Info=$null;Broken=$false;DiagnosticDrain=$process.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)}
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
    $encoded=$script:QuietUtf8.GetBytes((ConvertTo-Json -InputObject $Header -Depth 32 -Compress))
    if($encoded.Length -gt $script:QuietProtocol.HeaderLimit){throw 'ControlFrameTooLarge'}
    $lengths=[byte[]]::new(8)
    [BitConverter]::GetBytes([int]$encoded.Length).CopyTo($lengths,0)
    [BitConverter]::GetBytes([int]$Payload.Length).CopyTo($lengths,4)
    $seconds=30.0
    if($env:QUIETCLI2_IPC_TIMEOUT_SECONDS){$seconds=[double]::Parse($env:QUIETCLI2_IPC_TIMEOUT_SECONDS,[Globalization.CultureInfo]::InvariantCulture)}
    if(![double]::IsFinite($seconds) -or $seconds -lt 0.05 -or $seconds -gt 300){throw 'InvalidIpcTimeout'}
    $deadline=[Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($seconds))
    try{
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
        if($response.Version -ne $script:QuietProtocol.Version -or $response.RequestId -ne $Header.RequestId){throw 'ProtocolMismatch'}
        $script:QuietEngine.Requests++;$script:QuietEngine.InputBytes+=8+$encoded.Length+$Payload.Length;$script:QuietEngine.OutputBytes+=8+$headerSize+$payloadSize
    }catch{
        $script:QuietEngine.Broken=$true
        try{if(!$script:QuietEngine.Process.HasExited){$script:QuietEngine.Process.Kill($true)}}catch{}
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
    try{if(!$script:QuietEngine.Process.HasExited -and !$script:QuietEngine.Broken){$null=Send-QuietRequest @{Action='shutdown'};$script:QuietEngine.Input.Close();[void]$script:QuietEngine.Process.WaitForExitAsync().WaitAsync([TimeSpan]::FromSeconds(5)).GetAwaiter().GetResult()}}
    finally{if(!$script:QuietEngine.Process.HasExited){try{$script:QuietEngine.Process.Kill($true)}catch{}};$script:QuietEngine.Process.Dispose();$script:QuietEngine=$null}
}
function Get-QuietEngine {
    <#
.SYNOPSIS
Returns engine identity and protocol counters, without native output. #>
    [CmdletBinding()]param()
    Start-QuietEngine
    [pscustomobject]@{SessionId=$script:QuietSession;Engine=$script:QuietEngine.Info;Requests=$script:QuietEngine.Requests;ProtocolInputBytes=$script:QuietEngine.InputBytes;ProtocolOutputBytes=$script:QuietEngine.OutputBytes;Database=$script:QuietEngine.Database}
}
