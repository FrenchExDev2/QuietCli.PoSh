function Read-QuietArguments {
    <#
.SYNOPSIS
Separates exact facade options from the uninterpreted native argument vector.
    .PARAMETER Arguments
    Original arguments received by Invoke-QuietCli.
    #>
    param([object[]]$Arguments)
    $switches = @('AsObject', 'AsJson', 'AsYaml')
    $values = @('Output', 'Complete', 'Context', 'Data', 'State', 'WorkingDirectory', 'TimeoutSeconds', 'DrainTimeoutSeconds', 'Environment', 'Transport', 'StdoutMode', 'StderrMode', 'InputText', 'InputBytes', 'InputPath', 'Interaction', 'RecordDelimiter', 'MaxRecordBytes', 'MaxOutputBytes', 'MaxItems', 'Role', 'HandlerId', 'CancellationFile', 'CancellationToken', 'Projection', 'Tokenizer', 'FilePath', 'ArgumentList', 'TerminalSize', 'SuccessExitCodes', 'ReadBlockBytes')
    $aliases = @{C = 'Context' }
    $request = @{}
    $index = 0
    while ($index -lt $Arguments.Count) {
        $argument = $Arguments[$index]
        if ($argument -isnot [string] -or !$argument.StartsWith('-') -or $argument -eq '--') { break }
        $name = $argument.TrimStart('-')
        $switchValue = $true
        if ($name -match '^([^:]+):(.*)$') {
            $name = $Matches[1]
            $suffix = $Matches[2]
            if ($suffix) { $switchValue = [bool]::Parse($suffix) }elseif ($index + 1 -lt $Arguments.Count) {
                $index++
                $switchValue = [bool]$Arguments[$index]
            }
        }
        if ($aliases.ContainsKey($name)) { $name = $aliases[$name] }
        if ($name -in $switches) {
            $request[$name] = $switchValue
            $index++
            continue
        }
        if ($name -notin $values) { throw "UnknownQuietOption: $argument" }
        $index++
        if ($index -ge $Arguments.Count) { throw "MissingQuietOptionValue: $name" }
        $request[$name] = $Arguments[$index]
        $index++
    }
    if ($index -lt $Arguments.Count -and $Arguments[$index] -eq '--') { $index++ }
    if (!$request.ContainsKey('FilePath')) {
        if ($index -ge $Arguments.Count) { throw 'MissingExecutable' }
        $request.FilePath = [string]$Arguments[$index]
        $index++
    }
    if (!$request.ContainsKey('ArgumentList')) {
        $native = [Collections.Generic.List[string]]::new()
        while ($index -lt $Arguments.Count) {
            $argument = $Arguments[$index]
            $index++
            if ($argument -is [scriptblock] -or $argument -is [Collections.IDictionary]) { throw 'QuietOptionsMustPrecedeExecutable' }
            if ($argument -is [string] -and $argument.EndsWith(':') -and $argument.PSObject.Properties['<CommandParameterName>'] -and $index -lt $Arguments.Count) {
                $native.Add($argument + [string]$Arguments[$index])
                $index++
                continue
            }
            foreach ($value in @($argument)) { if ($null -ne $value) { $native.Add([string]$value) } }
        }
        $request.ArgumentList = $native.ToArray()
    }
    elseif ($index -ne $Arguments.Count) { throw 'UnexpectedArgumentsAfterArgumentList' }
    $defaults = @{WorkingDirectory =(Get-Location).Path
        TimeoutSeconds             =600
        DrainTimeoutSeconds        =30
        Environment                =@{}
        Transport                  ='Pipe'
        StdoutMode                 ='Text'
        StderrMode                 ='Text'
        MaxRecordBytes             =1048576
        MaxOutputBytes             =4096
        MaxItems                   =20
        Role                       ='Business'
        Tokenizer                  ='off'
        TerminalSize               =@(120, 40)
        SuccessExitCodes           =@(0)
        ReadBlockBytes             =16384
    }
    foreach ($name in $defaults.Keys) { if (!$request.ContainsKey($name)) { $request[$name] = $defaults[$name] } }
    if (@($switches | Where-Object { $request.ContainsKey($_) -and $request[$_] }).Count -gt 1) { throw 'OutputFormatsAreExclusive' }
    if (@('InputText', 'InputBytes', 'InputPath', 'Interaction' | Where-Object { $request.ContainsKey($_) }).Count -gt 1) { throw 'InputOptionsAreExclusive' }
    if ($request.Transport -notin @('Pipe', 'Pty') -or $request.StdoutMode -notin @('Text', 'Bytes') -or $request.StderrMode -notin @('Text', 'Bytes')) { throw 'InvalidTransportOrStreamMode' }
    if ($request.Role -notin @('Business', 'Probe', 'Observation', 'Infrastructure')) { throw 'InvalidSourceRole' }
    if ($request.TimeoutSeconds -le 0 -or $request.MaxRecordBytes -lt 1 -or $request.MaxOutputBytes -lt 256 -or $request.MaxItems -lt 0) { throw 'InvalidLimits' }
    if (![double]::IsFinite([double]$request.TimeoutSeconds) -or $request.TimeoutSeconds -gt ([uint32]::MaxValue - 1L) / 1000.0) { throw 'InvalidTimeout' }
    if (![double]::IsFinite([double]$request.DrainTimeoutSeconds) -or $request.DrainTimeoutSeconds -lt 0.05 -or $request.DrainTimeoutSeconds -gt 300) { throw 'InvalidDrainTimeout' }
    $request.WorkingDirectory = [IO.Path]::GetFullPath($request.WorkingDirectory, (Get-Location).Path)
    if ($request.ReadBlockBytes -lt 1024 -or $request.ReadBlockBytes -gt 16384) { throw 'InvalidReadBlockBytes' }
    if (@($request.TerminalSize).Count -ne 2 -or $request.TerminalSize[0] -lt 1 -or $request.TerminalSize[0] -gt 1000 -or $request.TerminalSize[1] -lt 1 -or $request.TerminalSize[1] -gt 1000) { throw 'InvalidTerminalSize' }
    if ($request.ContainsKey('Context') -and [string]::IsNullOrWhiteSpace($request.Context)) { throw 'EmptyExplicitContext' }
    if ($request.ContainsKey('RecordDelimiter') -and !([string]$request.RecordDelimiter).Length) { throw 'EmptyRecordDelimiter' }
    return $request
}
function Invoke-QuietCli {
    <#
.SYNOPSIS
Executes a streaming command or registered handler; options precede the binary.
    .DESCRIPTION
    quiet [-C context] [-AsObject|-AsJson|-AsYaml] [-Output {param($event,$runtime)}]
    [-Complete {param($runtime)}] executable arguments. AsObject never serializes Data.
    Nested calls default to AsObject and inherit their parent's context.
    Native arguments follow the executable verbatim; put QuietCli options first.
    .EXAMPLE
    $result = quiet -AsObject -Data @{Bytes=0L} -Output {param($e,$r) $r.Data.Bytes+=$e.ByteCount} pwsh -Command '"hello"'
    #>
    $request = Read-QuietArguments $args
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
    Import-QuietManagedEngine
    $allocation = [FrenchExDev2.QuietCli.AllocationMeter]::new()
    # A new root request may establish a fresh engine; no outstanding invocation is retried.
    if ($script:QuietStack.Count -eq 0 -and $script:QuietEngine -and $script:QuietEngine.Broken) { Stop-QuietEngine }
    $runtime = New-QuietRuntime $Request
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $outcome = 'Success'
    $result = $null
    $script:QuietStack.Push($runtime)
    try {
        try {
            $application = Get-Command $Request.FilePath -CommandType Application -ErrorAction Stop | Select-Object -First 1
            $Request.FilePath = $application.Source
            Set-QuietLifecycle $runtime Running
            if ($Request.ContainsKey('Output') -or $Request.ContainsKey('Complete')) { Invoke-QuietNative $runtime }
            else {
                $handler = Resolve-QuietHandler $runtime
                if (!$handler) {
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
                    while (!$runtime.Completed) { $null = Read-QuietEvent $runtime }
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
        if (!$runtime.AnalysisComplete -and $outcome -eq 'Success') { $outcome = 'Failed' }
        $issues = @($runtime.Children | Where-Object Outcome -NE Success)
        if ($issues.Count -and $outcome -eq 'Success') { $outcome = $issues[0].Outcome }
        foreach ($child in $runtime.Children) { foreach ($key in $child.Internal.Sources.Keys) { $runtime.Sources[$key] = $child.Internal.Sources[$key] } }
        $sourceComplete = ($runtime.Execution -eq $null -or $runtime.Execution.SourceComplete) -and @($runtime.Children | Where-Object { !$_.Completeness.Source }).Count -eq 0
        $analysisComplete = $runtime.AnalysisComplete -and @($runtime.Children | Where-Object { !$_.Completeness.Analysis }).Count -eq 0
        if ($runtime.Lifecycle -eq 'Running') { Set-QuietLifecycle $runtime Draining }
        if ($runtime.Lifecycle -eq 'Draining') { Set-QuietLifecycle $runtime Completing }
        Set-QuietLifecycle $runtime Finalized
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
        Set-QuietFinalProperty $result Execution $execution
        Set-QuietFinalProperty $result Completeness $result.Completeness
        $result.Measurement.Allocation = $allocation.Stop()
        Save-QuietResultMetadata $result
    }
    finally {
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
function Invoke-QuietNative {
    <#
.SYNOPSIS
Drives the separate native process without retaining its streams.
    .PARAMETER Runtime
    Caller-local state and callbacks.
    #>
    param($Runtime)
    $request = $Runtime.Request
    $start = @{Action    ='start'
        InvocationId     =$Runtime.InvocationId
        FilePath         =$request.FilePath
        ArgumentList     =[string[]]$request.ArgumentList
        WorkingDirectory =[IO.Path]::GetFullPath($request.WorkingDirectory)
        Environment      =$request.Environment
        Transport        =$request.Transport
        Columns          =[int]$request.TerminalSize[0]
        Rows             =[int]$request.TerminalSize[1]
        TimeoutSeconds   =[double]$request.TimeoutSeconds
        SuccessExitCodes =@($request.SuccessExitCodes)
        KeepInputOpen    =($request.ContainsKey('InputBytes') -or $request.ContainsKey('InputText') -or $request.ContainsKey('Interaction'))
    }
    if ($request.ContainsKey('InputPath')) { $start.InputPath = [IO.Path]::GetFullPath($request.InputPath, $start.WorkingDirectory) }
    $start.ReadBlockBytes = [int]$request.ReadBlockBytes
    $start.DrainTimeoutSeconds = [double]$request.DrainTimeoutSeconds
    $Runtime.StartState = 'StartRequested'
    $null = Send-QuietRequest $start
    $Runtime.NativeStarted = $true
    $Runtime.StartState = 'StartAcknowledged'
    if ($request.ContainsKey('InputBytes')) {
        Write-QuietInput $Runtime $request.InputBytes
        $Runtime.CompleteInput()
    }
    elseif ($request.ContainsKey('InputText')) {
        Write-QuietInput $Runtime $script:QuietUtf8.GetBytes($request.InputText)
        $Runtime.CompleteInput()
    }
    elseif ($request.ContainsKey('Interaction')) {
        try {
            $values = @(& $request.Interaction $Runtime)
            if ($values.Count) { throw 'InteractionUnexpectedOutput' }
        }
        catch {
            $Runtime.AnalysisComplete = $false
            $Runtime.Errors.Add(@{Code = 'InteractionFailed'; Phase = 'Interaction'; Message = $_.Exception.Message })
            $Runtime.Cancel()
        }
    }
    while (!$Runtime.Completed) {
        if (($request.ContainsKey('CancellationFile') -and (Test-Path -LiteralPath $request.CancellationFile)) -or ($request.ContainsKey('CancellationToken') -and $request.CancellationToken.IsCancellationRequested)) { $Runtime.Cancel() }
        $null = Read-QuietEvent $Runtime
    }
    foreach ($stream in @('stdout', 'stderr', 'terminal')) {
        if (!$Runtime.AnalysisComplete) { break }
        if (!$Runtime.TextStreams.ContainsKey($stream)) { continue }
        try {
            $tail = $Runtime.TextStreams[$stream].Finish()
            if ($tail.Length) { Invoke-QuietOutputCallback $Runtime ([pscustomobject]@{Stream = $stream; Kind = 'Text'; Text = $tail; Bytes = $null; ByteCount = $null }) }
        }
        catch {
            $Runtime.AnalysisComplete = $false
            $Runtime.Errors.Add(@{Code = 'DecodeIncomplete'; Phase = 'Drain'; Message = $_.Exception.Message })
        }
    }
    foreach ($processor in $Runtime.TextStreams.Values) { $processor.Dispose() }
    $Runtime.Sources[$Runtime.InvocationId] = [ordered]@{InvocationId =$Runtime.InvocationId
        Role                                                          =$request.Role
        StdoutBytesRead                                               =$Runtime.Execution.StdoutBytesRead
        StderrBytesRead                                               =$Runtime.Execution.StderrBytesRead
        TerminalBytesRead                                             =$Runtime.Execution.TerminalBytesRead
        StdinBytesWritten                                             =$Runtime.Execution.StdinBytesWritten
        Complete                                                      =$Runtime.Execution.SourceComplete
    }
    Set-QuietLifecycle $Runtime Completing
    if ($request.ContainsKey('Complete')) {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $allocation = [FrenchExDev2.QuietCli.AllocationMeter]::new()
        try {
            if ($Runtime.CompleteInvoked) { throw 'CompleteAlreadyInvoked' }
            $Runtime.CompleteInvoked = $true
            $value = Invoke-QuietCallbackValue $request.Complete @($Runtime)
            if ($value.HasValue) { $Runtime.Data = $value.Value }
        }
        catch {
            $Runtime.AnalysisComplete = $false
            $Runtime.Errors.Add(@{Code = 'CompleteCallbackFailed'; Phase = 'Complete'; Message = $_.Exception.Message })
        }
        finally {
            $Runtime.CompleteAllocation = $allocation.Stop()
            $Runtime.CallbackMs += $watch.Elapsed.TotalMilliseconds
        }
    }
}
