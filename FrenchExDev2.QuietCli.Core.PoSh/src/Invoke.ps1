function Invoke-QuietCli {
    <#
.SYNOPSIS
Executes a streaming command or registered handler; options precede the binary.
    .DESCRIPTION
    quiet [-C context] [-AsObject|-AsJson|-AsYaml] [-Output {param($event,$runtime)}]
    [-Complete {param($runtime)}] executable arguments. AsObject never serializes Data.
    Nested calls default to AsObject and inherit their parent's context.
    Native arguments follow the executable verbatim; put QuietCli options first.
    -Script path.ps1 writes a reusable definition without executing the command.
    -DataFactory and -StateFactory initialize fresh business values once per real call.
    .EXAMPLE
    $result = quiet -AsObject -Data @{Bytes=0L} -Output {param($e,$r) $r.Data.Bytes+=$e.ByteCount} pwsh -Command '"hello"'
    #>
    $request = Read-QuietArguments $args
    if ($request.ContainsKey('Script')) { return Export-QuietCallScript $request }
    if($request.ContainsKey('RecallId')){return Invoke-QuietSavedRecallRequest $request}
    Invoke-QuietCall $request
}
function Invoke-QuietCall {
    <#
.SYNOPSIS
Owns one caller-local lifecycle and preserves assigned child failures.
    .PARAMETER Request
    Validated facade options.
    #>
    param([hashtable]$Request)
    if ($script:QuietRecallDepth -gt 0) { throw 'NativeExecutionUnavailableDuringRecall' }
    $Request = Initialize-QuietCallFactories $Request
    Import-QuietManagedEngine
    $allocation = [FrenchExDev2.QuietCli.AllocationMeter]::new()
    # A new root request may establish a fresh engine; no outstanding invocation is retried.
    if ($script:QuietStack.Count -eq 0 -and [FrenchExDev2.QuietCli.QuietSession]::Engine -and [FrenchExDev2.QuietCli.QuietSession]::Engine.Broken) { Stop-QuietEngine }
    $runtime = New-QuietRuntime -Request $Request -Parent $(if ($script:QuietStack.Count) { $script:QuietStack.Peek() }) -SessionId $script:QuietSession
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $outcome = 'Success'
    $result = $null
    $script:QuietStack.Push($runtime)
    try {
        try {
            $application = Get-Command $Request.FilePath -CommandType Application -ErrorAction Stop | Select-Object -First 1
            $Request.FilePath = $application.Source
            $runtime.Transition('Running')
            if ($Request.ContainsKey('Output') -or $Request.ContainsKey('Complete')) { Invoke-QuietNative $runtime }
            else {
                $handler = Resolve-QuietHandler $runtime
                if (!$handler -and $Request.ContainsKey('SaveRecall') -and $Request.SaveRecall) { Invoke-QuietNative $runtime }
                elseif (!$handler) {
                    $outcome = 'Unsupported'
                    $runtime.Errors.Add(@{Code = 'HandlerNotFound'; Phase = 'Resolve'; Message = 'No compatible handler is registered. Supply -Output/-Complete for direct execution.' })
                }
                else {
                    $runtime.Handler = $handler
                    $value = Invoke-QuietCallbackValue $handler.Execute @($runtime)
                    if ($value.HasValue) { $runtime.Data = $value.Value }
                }
            }
        }
        catch {
            $outcome = 'Failed'
            $runtime.AnalysisComplete = $false
            $runtime.Errors.Add(@{Code = 'InvocationFailed'; Phase = $runtime.Lifecycle; Message = $_.Exception.Message })
            if (!$runtime.NativeStarted -and $runtime.StartState -eq 'StartRequested') {
                $effect = if ($_.Exception.Data.Contains('QuietCliRequestRejected')) { 'NotStarted' }else { 'Unknown' }
                $runtime.Execution = [pscustomobject]@{Outcome ='Failed'
                    ExitCode                                   =$null
                    SourceComplete                             =$false
                    EffectStatus                               =$effect
                    State                                      ='Finalized'
                    Error                                      ='NativeStartUnconfirmed'
                }
                try {
                    $null = Send-QuietRequest @{Action ='cancel'
                        InvocationId                   =$runtime.InvocationId
                    }
                }
                catch {}
            }
            if ($runtime.NativeStarted -and !$runtime.Completed) {
                try {
                    $null = Send-QuietRequest @{Action ='cancel'
                        InvocationId                   =$runtime.InvocationId
                    }
                    while (!$runtime.Completed) { $null = $runtime.ReadEvent() }
                }
                catch {
                    $runtime.Execution = [pscustomobject]@{Outcome ='Failed'
                        ExitCode                                   =$null
                        SourceComplete                             =$false
                        EffectStatus                               ='Unknown'
                    }
                }
            }
        }
        if ($runtime.Execution -and $runtime.Execution.Outcome -ne 'Success') { $outcome = $runtime.Execution.Outcome }
        $diskRecall=$null
        if($runtime.RecallWriter){
            try{
                $status=if($runtime.Execution){[FrenchExDev2.QuietCli.RecallSourceStatus]::new([string]$runtime.Execution.Outcome,$runtime.Execution.ExitCode,[string]$runtime.Execution.EffectStatus)}else{$null}
                $diskRecall=$runtime.RecallWriter.CompleteAsync([bool]($runtime.Execution -and $runtime.Execution.SourceComplete),$status).GetAwaiter().GetResult()
                if($Request.ContainsKey('Zip') -and $Request.Zip){
                    $level=if($Request.ContainsKey('Compress')){$Request.Compress}else{6}
                    $null=[FrenchExDev2.QuietCli.RecallArchive]::ExportAsync($diskRecall,($diskRecall.StoragePath+'.zip'),$true,$level).GetAwaiter().GetResult()
                }
            }catch{$runtime.RecallSaveFailed=$true;if(!$diskRecall){$diskRecall=$runtime.RecallWriter.FailedSnapshot()};$runtime.Errors.Add(@{Code='RecallSaveFailed';Phase='SaveRecall';Message=$_.Exception.Message})}
        }
        if($runtime.RecallSaveFailed -and $outcome -eq 'Success'){$outcome='Failed'}
        if (!$runtime.AnalysisComplete -and $outcome -eq 'Success') { $outcome = 'Failed' }
        $issues = @($runtime.Children | Where-Object Outcome -NE Success)
        if ($issues.Count -and $outcome -eq 'Success') { $outcome = $issues[0].Outcome }
        foreach ($child in $runtime.Children) { foreach ($key in $child.Internal.Sources.Keys) { $runtime.Sources[$key] = $child.Internal.Sources[$key] } }
        $sourceComplete = ($runtime.Execution -eq $null -or $runtime.Execution.SourceComplete) -and @($runtime.Children | Where-Object { !$_.Completeness.Source }).Count -eq 0
        $analysisComplete = $runtime.AnalysisComplete -and @($runtime.Children | Where-Object { !$_.Completeness.Analysis }).Count -eq 0
        if ($runtime.Lifecycle -eq 'Running') { $runtime.Transition('Draining') }
        if ($runtime.Lifecycle -eq 'Draining') { $runtime.Transition('Completing') }
        $runtime.Transition('Finalized')
        $effect = if ($runtime.Execution -and $runtime.Execution.PSObject.Properties['EffectStatus']) { $runtime.Execution.EffectStatus }elseif (@($runtime.Children | Where-Object { $_.Execution.EffectStatus -eq 'Unknown' }).Count) { 'Unknown' }else { 'Observed' }
        $execution = ConvertTo-QuietSnapshot @{State ='Finalized'
            Native                                   =$runtime.Execution
            ElapsedMs                                =$watch.Elapsed.TotalMilliseconds
            CallbackMs                               =$runtime.CallbackMs
            Children                                 =$runtime.Children.Count
            EffectStatus                             =$effect
            Issues                                   =@($issues | ForEach-Object { @{InvocationId = $_.InvocationId; Outcome = $_.Outcome; EffectStatus = $_.Execution.EffectStatus; Error = $_.Error } })
        }
        $result = [pscustomobject][ordered]@{
            SchemaVersion =1
            Summary       =$(if ($runtime.Handler) { $runtime.Handler.Summary }else { 'Native command processed.' })
            Outcome       =$outcome
            Data          =$runtime.Data
            InvocationId  =$runtime.InvocationId
            ParentId      =$runtime.ParentId
            RootId        =$runtime.RootId
            SessionId     =$runtime.SessionId
            Context       =$runtime.Context
            Execution     =$execution
            Error         =$runtime.Errors.ToArray()
            Completeness  =(ConvertTo-QuietSnapshot @{Source = [bool]$sourceComplete; Analysis = [bool]$analysisComplete })
            Truncation    =[pscustomobject]@{Applied =$false
                Reasons                              =@()
            }
            Measurement   =[pscustomobject]@{Status ='CountersOnly'
                OutputBytes                      =$null
                OutputTokens                     =$null
                NativeTokens                     =$null
                ReductionBytes                   =$null
                StorageError                     =$null
                Allocation                       =$null
                CompleteAllocation               =$runtime.CompleteAllocation
            }
            Deliveries    =[Collections.Generic.List[object]]::new()
            Internal      =@{Sources =$runtime.Sources
                Request              =$Request
                Handler              =$runtime.Handler
                Administrative       =$false
            }
        }
        $result.PSObject.TypeNames.Insert(0, 'QuietCli2.Result')
        if ($diskRecall) {
            if($runtime.RecallCollector){$diskRecall.AttachMemorySnapshot($runtime.RecallCollector.Snapshot([bool]($runtime.Execution -and $runtime.Execution.SourceComplete),(Get-QuietRecallSettings $Request),$diskRecall.SourceStatus))}
            Set-QuietFinalProperty $result Recall $diskRecall
        }
        elseif ($runtime.RecallCollector) {
            $settings = Get-QuietRecallSettings $Request
            $status = if ($runtime.Execution) { [FrenchExDev2.QuietCli.RecallSourceStatus]::new([string]$runtime.Execution.Outcome,$runtime.Execution.ExitCode,[string]$runtime.Execution.EffectStatus) } else { $null }
            Set-QuietFinalProperty $result Recall ($runtime.RecallCollector.Snapshot([bool]($runtime.Execution -and $runtime.Execution.SourceComplete), $settings, $status))
        }
        Set-QuietFinalProperty $result Execution $execution
        Set-QuietFinalProperty $result Completeness $result.Completeness
        $result.Measurement.Allocation = $allocation.Stop()
        Save-QuietResultMetadata $result
    }
    finally {
        if($runtime.RecallWriter){$runtime.RecallWriter.DisposeAsync().GetAwaiter().GetResult()|Out-Null}
        [void]$script:QuietStack.Pop()
        if ($runtime.StartState -ne 'NotStarted') {
            try {
                $null = Send-QuietRequest @{Action ='release'
                    InvocationId                   =$runtime.InvocationId
                }
            }
            catch {}
        }
    }
    if ($script:QuietStack.Count) { $script:QuietStack.Peek().Children.Add($result) }
    $asObject = $Request.ContainsKey('AsObject') -and $Request.AsObject
    if (!$Request.ContainsKey('AsJson') -and !$Request.ContainsKey('AsYaml') -and $script:QuietStack.Count) { $asObject = $true }
    if ($asObject) { return $result }
    Out-QuietResult -InputObject $result -AsYaml:($Request.ContainsKey('AsYaml') -and $Request.AsYaml) -MaxItems $Request.MaxItems -MaxOutputBytes $Request.MaxOutputBytes -Tokenizer $Request.Tokenizer
}
