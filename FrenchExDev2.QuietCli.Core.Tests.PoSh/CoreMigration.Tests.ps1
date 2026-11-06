function Measure-QuietCoreMigration {
    <#
    .SYNOPSIS
    Checks detached PowerShell metadata, then compares snapshots, YAML emission and local metadata dispatch.
    .PARAMETER Dotnet
    Existing executable identity used only for the synthetic registry cache test.
    #>
    param([string]$Dotnet)
    & (Get-Module FrenchExDev2.QuietCli.Core.PoSh) {
        param($baseline,$dotnet)
        . $baseline
        $metadata=[ordered]@{State='Finalized';Native=[pscustomobject]@{Outcome='Success';StdoutBytesRead=123L};Issues=@(foreach($index in 1..16){@{InvocationId="child-$index";Error=@(@{Code='Known';Phase='Output'})}})}
        $copy=ConvertTo-QuietSnapshot $metadata
        $metadata.Native.StdoutBytesRead=456L;$metadata.Issues[0].Error[0].Code='Changed'
        if($copy.Native.StdoutBytesRead -ne 123 -or $copy.Issues[0].Error[0].Code -cne 'Known'){throw 'CallerMetadataNotDetached'}
        $graph=[ordered]@{items=@(foreach($index in 1..24){[ordered]@{name="é漢🙂-$index";literal='true';enabled=$true;count=$index}});empty=@();none=$null}
        foreach($kind in @('Snapshot','Yaml')){
            foreach($iteration in 1..3){
                foreach($implementation in $(if($iteration%2){@('PowerShell','CSharp')}else{@('CSharp','PowerShell')})){
                    $watch=[Diagnostics.Stopwatch]::StartNew()
                    foreach($call in 1..20){
                        if($kind -eq 'Snapshot'){
                            $value=if($implementation -eq 'PowerShell'){ConvertTo-QuietSnapshotBaseline $metadata}else{ConvertTo-QuietSnapshot $metadata}
                            if($value.Issues.Count -ne 16 -or $value.Native.StdoutBytesRead -ne 456){throw 'SnapshotBenchmarkChangedMetadata'}
                        }else{
                            $value=if($implementation -eq 'PowerShell'){ConvertTo-QuietYamlValueBaseline $graph}else{ConvertTo-QuietYamlValue $graph}
                            # Unicode escape spelling is serializer-owned; the independent C# parser case verifies decoded identity.
                            if(!$value.Contains('-24') -or !$value.Contains('true')){throw 'YamlBenchmarkLostContent'}
                        }
                    }
                    $watch.Stop()
                    @{Kind='CoreLocalHelper';Operation=$kind;Implementation=$implementation;Iteration=$iteration;Calls=20;ElapsedMs=$watch.Elapsed.TotalMilliseconds;Scope='Identical synthetic metadata or normalized delivery graph; excludes native execution, callbacks and IPC. YAML text styles may differ.'}
                }
            }
        }
        $previousMode=(Get-QuietTestConfiguration).Values['engine.hosting']
        try{
            Stop-QuietEngine;(Get-QuietTestConfiguration).Values['engine.hosting']='InProcess';$null=Get-QuietEngine;$hostEngine=[FrenchExDev2.QuietCli.QuietSession]::Engine.Host
            foreach($iteration in 1..3){
                foreach($implementation in $(if($iteration%2){@('Json','Typed')}else{@('Typed','Json')})){
                    $jsonBytes=0L;$watch=[Diagnostics.Stopwatch]::StartNew()
                    foreach($call in 1..128){
                        $header=@{Version=1;RequestId="metadata-$iteration-$call";Action='hello'}
                        if($implementation -eq 'Json'){
                            $encoded=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $header -Compress))
                            $reply=$hostEngine.RequestAsync($encoded,[byte[]]@()).GetAwaiter().GetResult()
                            $jsonBytes+=$encoded.Length+[Text.Encoding]::UTF8.GetByteCount($reply.HeaderJson)
                            $response=ConvertFrom-Json -InputObject $reply.HeaderJson
                        }else{
                            $reply=$hostEngine.MetadataAsync($header,$script:QuietMetadataAdapter).GetAwaiter().GetResult()
                            if($null -eq $reply.Header -or $null -ne $reply.HeaderJson){throw 'TypedMetadataStillSerialized'}
                            $response=$reply.Header
                        }
                        if(!$response.Ok -or $response.RequestId -cne $header.RequestId -or $response.Data.ProcessId -ne $PID){throw 'MetadataBenchmarkIdentityChanged'}
                    }
                    $watch.Stop()
                    @{Kind='EngineMetadata';Implementation=$implementation;Iteration=$iteration;Calls=128;ElapsedMs=$watch.Elapsed.TotalMilliseconds;ControlJsonBytes=$jsonBytes;ProtocolBytes=0L;Scope='Local hello dispatch with identical engine identity; excludes session startup, native processes, persistence and IPC.'}
                }
            }
        }finally{Stop-QuietEngine;(Get-QuietTestConfiguration).Values['engine.hosting']=$previousMode}
        $id='registry-measure-'+[guid]::NewGuid().ToString('N');$probe=@{Calls=0}
        $binary=[IO.Path]::GetFileNameWithoutExtension($dotnet)
        Register-QuietHandler -Id $id -Definition @{Binary=$binary;VersionRange='synthetic';Execute={};TestVersion={param($version)$version -ceq 'synthetic-1'};Probe={$probe.Calls++;'synthetic-1'}.GetNewClosure()}
        try{
            $runtime=[pscustomobject]@{Request=@{FilePath=$dotnet;Environment=@{};HandlerId=$id};State=@{}}
            $existingKeys=@($script:QuietProbeCache.Keys)
            foreach($iteration in 1..3){
                foreach($implementation in $(if($iteration%2){@('PowerShell','CompiledIdentity')}else{@('CompiledIdentity','PowerShell')})){
                    foreach($key in @($script:QuietProbeCache.Keys)){if($key -cnotin $existingKeys){$script:QuietProbeCache.Remove($key)}}
                    $beforeProbes=$probe.Calls;$watch=[Diagnostics.Stopwatch]::StartNew()
                    foreach($call in 1..200){
                        $handler=if($implementation -eq 'PowerShell'){Resolve-QuietHandlerBaseline $runtime}else{Resolve-QuietHandler $runtime}
                        if($null -eq $handler -or $handler.Id -cne $id){throw 'RegistrySelectionChanged'}
                    }
                    $watch.Stop()
                    if($probe.Calls-$beforeProbes -ne 1){throw 'RegistryRepeatedVersionProbe'}
                    @{Kind='RegistryResolution';Implementation=$implementation;Iteration=$iteration;Calls=200;ProbeCalls=($probe.Calls-$beforeProbes);ElapsedMs=$watch.Elapsed.TotalMilliseconds;Scope='One synthetic candidate, one cached version probe, real executable stat and child environment cache key; no native execution.'}
                }
            }
        }finally{Unregister-QuietHandler $id;foreach($key in @($script:QuietProbeCache.Keys)){if($key -cnotin $existingKeys){$script:QuietProbeCache.Remove($key)}}}
    } (Join-Path $PSScriptRoot 'CoreMigration.Baseline.ps1') $Dotnet
}
