function Test-QuietSqlitePreparation {
    <#
    .SYNOPSIS
    Verifies telemetry preparation while a native child is waiting for input, in both engine hosts.
    .PARAMETER WorkspaceRoot
    Built monorepo and fixture root.
    .PARAMETER RunDirectory
    Owned report directory containing isolated databases.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $fixture=[IO.Path]::Combine($WorkspaceRoot,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture/QuietCli.Fixture.dll')
    $dotnet=(Get-Command dotnet -CommandType Application|Select-Object -First 1).Source
    $values=(Get-QuietTestConfiguration).Values
    $previous=@{Mode=$values['engine.hosting'];Enabled=$values['telemetry.enabled'];Database=$values['telemetry.database']}
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    try{
        foreach($mode in @('InProcess','Process')){
            Stop-QuietEngine
            $database=[IO.Path]::Combine($RunDirectory,($mode+'.sqlite'))
            $values['engine.hosting']=$mode;$values['telemetry.database']=$database;$values['telemetry.enabled']=$false
            $null=Get-QuietEngine
            if([IO.File]::Exists($database)){throw 'EngineInspectionCreatedDatabase'}
            $disabled=quiet -AsObject -Complete {param($runtime) 'disabled'} $dotnet $fixture emit 1
            Assert-QuietEqual $disabled.Outcome Success
            if([IO.File]::Exists($database)){throw 'DisabledTelemetryPreparedDatabase'}
            $values['telemetry.enabled']=$true
            $prepared=quiet -AsObject -State @{Database=$database} -Data @{ObservedReady=$false} -Output {param($event,$runtime)} -Interaction {
                param($runtime)
                try{
                    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(10)
                    while(![IO.File]::Exists($runtime.State.Database)){
                        if([DateTimeOffset]::UtcNow -gt $deadline){throw 'PreparationDidNotOverlapNativeExecution'}
                        [Threading.Tasks.Task]::Delay(20).GetAwaiter().GetResult()
                    }
                    $runtime.Data.ObservedReady=$runtime.NativeStarted -and !$runtime.Completed
                }finally{$runtime.CompleteInput()}
            } $dotnet $fixture copy
            Assert-QuietEqual $prepared.Outcome Success
            Assert-QuietEqual $prepared.Data.ObservedReady $true
            Assert-QuietEqual $prepared.Measurement.StorageError $null
            if((Get-QuietCliGain).Invocations -lt 1){throw 'PreparationLostImmediateMeasurementVisibility'}
            Stop-QuietEngine
            $parent=[IO.Path]::Combine($RunDirectory,($mode+'-blocked'))
            [IO.File]::WriteAllText($parent,'fixture',[Text.UTF8Encoding]::new($false))
            $values['telemetry.database']=[IO.Path]::Combine($parent,'cannot-create.sqlite')
            $failedStorage=quiet -AsObject -Complete {param($runtime) 'business-completed'} $dotnet $fixture emit 1
            Assert-QuietEqual $failedStorage.Outcome Success
            Assert-QuietEqual $failedStorage.Data 'business-completed'
            Assert-QuietEqual $failedStorage.Measurement.Status StorageUnavailable
            if(!$failedStorage.Measurement.StorageError){throw 'PreparationFailureWasNotReported'}
        }
    }finally{
        Stop-QuietEngine
        $values['engine.hosting']=$previous.Mode;$values['telemetry.enabled']=$previous.Enabled;$values['telemetry.database']=$previous.Database
    }
}

function Test-QuietAllocationTelemetry {
    <#
    .SYNOPSIS
    Checks allocation intervals, custom Complete objects, persistence and mixed delivery scopes in both hosts.
    .PARAMETER WorkspaceRoot
    Workspace whose existing companion launcher owns the visible monitor and private SQLite database.
    #>
    param([string]$WorkspaceRoot)
    $fixture=Join-Path $PSScriptRoot 'lib/fixture/QuietCli.Fixture.dll'
    $dotnet=(Get-Command dotnet -CommandType Application|Select-Object -First 1).Source
    $previousMode=(Get-QuietTestConfiguration).Values['engine.hosting']
    try{
        foreach($mode in @('InProcess','Process')){
            Stop-QuietEngine;(Get-QuietTestConfiguration).Values['engine.hosting']=$mode
            $context='allocations-'+[guid]::NewGuid().ToString('N')
            $allocated=0L;$completeAllocated=0L
            foreach($length in @(65536,262144,1048576)){
                $r=quiet -AsObject -C $context -State @{Length=$length} -Complete {
                    param($runtime)
                    $business=[pscustomobject]@{Buffer=[byte[]]::new($runtime.State.Length);Marker='created-in-complete'}
                    $business|Add-Member ScriptProperty Forbidden {throw 'Allocation measurement inspected Data'}
                    return $business
                } $dotnet $fixture emit 32768
                Assert-QuietEqual $r.Outcome Success
                Assert-QuietEqual $r.Data.Marker 'created-in-complete'
                Assert-QuietEqual $r.Data.Buffer.Length $length
                Assert-QuietEqual $r.Measurement.Allocation.Status Measured
                Assert-QuietEqual $r.Measurement.CompleteAllocation.Status Measured
                if($r.Measurement.CompleteAllocation.AllocatedBytes -lt $length -or $r.Measurement.Allocation.AllocatedBytes -lt $r.Measurement.CompleteAllocation.AllocatedBytes){throw 'CompleteAllocationIntervalLostPayload'}
                Assert-QuietEqual $r.Deliveries.Count 0
                Assert-QuietEqual $r.Measurement.OutputBytes $null
                Assert-QuietEqual $r.Measurement.ReductionBytes $null
                Assert-QuietEqual $r.Measurement.StorageError $null
                $allocated+=$r.Measurement.Allocation.AllocatedBytes
                $completeAllocated+=$r.Measurement.CompleteAllocation.AllocatedBytes
            }
            $report=Get-QuietCliGain -C $context -AsObject
            Assert-QuietEqual $report.RootInvocationAllocatedBytes $allocated
            Assert-QuietEqual $report.RootCompleteAllocatedBytes $completeAllocated
            Assert-QuietEqual $report.ReductionBytes $null
            Assert-QuietEqual $report.UnserializedRoots 3
            $plain=quiet -AsObject -C $context -Data @{Kept=$true} -Output {param($e,$r)} $dotnet $fixture emit 8192
            Assert-QuietEqual $plain.Measurement.CompleteAllocation $null
            Assert-QuietEqual $plain.Measurement.Allocation.Status Measured
            $text=Out-QuietResult $plain
            Assert-QuietEqual $plain.Measurement.ReductionBytes (8192-[Text.Encoding]::UTF8.GetByteCount($text))
            $report=Get-QuietCliGain -C $context -AsObject
            Assert-QuietEqual $report.SerializedBusinessBytesObserved 8192
            Assert-QuietEqual $report.ReductionBytes (8192-[Text.Encoding]::UTF8.GetByteCount($text))
            Assert-QuietEqual $report.UnserializedRoots 3
            $text2=Out-QuietResult $plain -AsYaml
            $report=Get-QuietCliGain -C $context -AsObject
            Assert-QuietEqual $report.RootDeliveries 2
            Assert-QuietEqual $report.ReductionBytes (8192-[Text.Encoding]::UTF8.GetByteCount($text)-[Text.Encoding]::UTF8.GetByteCount($text2))
            $failed=quiet -AsObject -Complete {param($runtime)$buffer=[byte[]]::new(131072);throw 'ExpectedCompleteFailure'} $dotnet $fixture emit 1
            Assert-QuietEqual $failed.Outcome Failed
            if($failed.Measurement.CompleteAllocation.AllocatedBytes -lt 131072){throw 'FailedCompleteAllocationMissing'}
            $rows=& (Get-Module FrenchExDev2.QuietCli.Core.PoSh) {
                param($selected)
                (Send-QuietRequest @{Action='query';From=0L;To=[DateTimeOffset]::UtcNow.AddMinutes(1).ToUnixTimeMilliseconds();Context=$selected}).Header.Data.Rows
            } $context
            if(@($rows|Where-Object {$_.Allocation.AllocatedBytes -gt 0}).Count -ne 6){throw 'AllocationMetadataNotPersisted'}
            if(@($rows|Where-Object {$_.PSObject.Properties['Data']}).Count){throw 'BusinessDataEnteredAllocationTelemetry'}
        }
    }finally{Stop-QuietEngine;(Get-QuietTestConfiguration).Values['engine.hosting']=$previousMode}
}
function Measure-QuietProcessAllocations {
    <#
    .SYNOPSIS
    Measures explicit process-wide allocation deltas over controlled warm workloads in both hosts.
    .PARAMETER WorkspaceRoot
    Built workspace whose companion launcher owns the visible monitor and report files.
    #>
    param([string]$WorkspaceRoot)
    $fixture=Join-Path $PSScriptRoot 'lib/fixture/QuietCli.Fixture.dll'
    $dotnet=(Get-Command dotnet -CommandType Application|Select-Object -First 1).Source
    $previousMode=(Get-QuietTestConfiguration).Values['engine.hosting']
    try{
        foreach($mode in @('InProcess','Process')){
            Stop-QuietEngine;(Get-QuietTestConfiguration).Values['engine.hosting']=$mode
            $warmup=quiet -AsObject -StdoutMode Bytes -Output {param($event,$runtime)} $dotnet $fixture emit 1
            if($warmup.Outcome -ne 'Success'){throw 'AllocationBenchmarkWarmupFailed'}
            foreach($iteration in 1..3){
                $before=(Get-QuietEngine -IncludeAllocations -Precise).Allocations
                $watch=[Diagnostics.Stopwatch]::StartNew()
                $r=quiet -AsObject -StdoutMode Bytes -Output {param($event,$runtime)} -Complete {
                    param($runtime)
                    [pscustomobject]@{Marker='benchmark';Buffer=[byte[]]::new(65536)}
                } $dotnet $fixture emit 4194304
                $watch.Stop()
                $after=(Get-QuietEngine -IncludeAllocations -Precise).Allocations
                if($r.Outcome -ne 'Success' -or $r.Data.Buffer.Length -ne 65536 -or $before.Caller.ProcessId -ne $after.Caller.ProcessId -or $before.Engine.ProcessId -ne $after.Engine.ProcessId){throw 'AllocationBenchmarkIdentityChanged'}
                $caller=$after.Caller.AllocatedBytes-$before.Caller.AllocatedBytes
                $engine=$after.Engine.AllocatedBytes-$before.Engine.AllocatedBytes
                if($before.SharedProcess -ne ($mode -eq 'InProcess') -or $caller -lt 65536 -or $engine -lt 0){throw 'AllocationBenchmarkScopeMismatch'}
                [pscustomobject]@{Kind='ProcessAllocationBenchmark';Mode=$mode;Iteration=$iteration;CallerProcessId=$after.Caller.ProcessId;EngineProcessId=$after.Engine.ProcessId;SharedProcess=$after.SharedProcess;Precise=$true;CallerAllocatedBytes=$caller;EngineAllocatedBytes=$engine;UniqueProcessAllocatedBytes=$(if($after.SharedProcess){$caller}else{$caller+$engine});InvocationAllocatedBytes=$r.Measurement.Allocation.AllocatedBytes;CompleteAllocatedBytes=$r.Measurement.CompleteAllocation.AllocatedBytes;NativeBytes=4194304;ElapsedMs=$watch.Elapsed.TotalMilliseconds;Scope='Process-wide managed allocation deltas, including concurrent work and sampling/control overhead; native allocations excluded. Shared caller/engine counters describe one process.'}
            }
        }
    }finally{Stop-QuietEngine;(Get-QuietTestConfiguration).Values['engine.hosting']=$previousMode}
}
