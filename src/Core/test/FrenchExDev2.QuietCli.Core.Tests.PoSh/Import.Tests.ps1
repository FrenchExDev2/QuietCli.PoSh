function Get-QuietImportStatistics {
    <#
    .SYNOPSIS
    Computes a median and nearest-rank p95 without clamping signed deltas.
    .PARAMETER Values
    Nonempty finite observations, in the caller's stated unit.
    #>
    param([AllowEmptyCollection()][double[]]$Values)
    if(!$Values.Count){throw 'ImportStatisticsEmpty'}
    foreach($value in $Values){if(![double]::IsFinite($value)){throw 'ImportStatisticsNonFinite'}}
    $sorted=@($Values|Sort-Object)
    $count=$sorted.Count
    $median=if($count%2){$sorted[[int][math]::Floor($count/2)]}else{($sorted[$count/2-1]+$sorted[$count/2])/2}
    [pscustomobject]@{Count=$count;Min=$sorted[0];Median=$median;P95=$sorted[[int][math]::Ceiling(.95*$count)-1];Max=$sorted[-1]}
}

function Test-QuietImportStatistics {
    <#
    .SYNOPSIS
    Checks generated arithmetic sequences, malformed values and targeted statistic mutants.
    #>
    $verify={
        $random=[Random]::new(73591)
        foreach($count in 1..64){
            $start=$random.Next(-10000,10000);$step=$random.Next(1,100)
            $values=@(for($i=0;$i -lt $count;$i++){$start+$step*$i})
            $shuffled=@($values|Sort-Object {$random.Next()})
            $s=Get-QuietImportStatistics $shuffled
            if($s.Count -ne $count -or $s.Min -ne $start -or $s.Max -ne $values[-1] -or $s.Median -ne $start+$step*($count-1)/2 -or $s.P95 -ne $values[[int][math]::Ceiling(.95*$count)-1]){throw 'ImportStatisticsProperty: seed 73591'}
        }
        foreach($values in @(@(),@([double]::NaN),@(1,[double]::PositiveInfinity),@([double]::NegativeInfinity,2))){
            $rejected=$false
            try{$null=Get-QuietImportStatistics $values}catch{$rejected=$_.Exception.Message -like 'ImportStatistics*'}
            if(!$rejected){throw 'ImportStatisticsMalformedInputAccepted'}
        }
        foreach($iteration in 1..64){
            $values=[double[]]::new($random.Next(1,65))
            for($i=0;$i -lt $values.Length;$i++){$values[$i]=$random.NextDouble()*20000-10000}
            $values[$random.Next($values.Length)]=@([double]::NaN,[double]::PositiveInfinity,[double]::NegativeInfinity)[$iteration%3]
            $rejected=$false
            try{$null=Get-QuietImportStatistics $values}catch{$rejected=$_.Exception.Message -eq 'ImportStatisticsNonFinite'}
            if(!$rejected){throw 'ImportStatisticsFuzzFailure: seed 73591'}
        }
    }
    & $verify
    $definition=(Get-Command Get-QuietImportStatistics).Definition
    $mutants=@(
        @('($sorted[$count/2-1]+$sorted[$count/2])/2','$sorted[$count/2]'),
        @('[math]::Ceiling(.95*$count)','[math]::Floor(.95*$count)'),
        @('Min=$sorted[0]','Min=$sorted[-1]'),
        @("throw 'ImportStatisticsNonFinite'",'return $null')
    )
    $killed=0
    $outcomes=[Collections.Generic.List[object]]::new()
    foreach($mutation in $mutants){
        if(!$definition.Contains($mutation[0])){throw 'ImportStatisticMutantInvalid'}
        $detected=& {
            param($body,$verify)
            . ([scriptblock]::Create('function Get-QuietImportStatistics {'+$body+'}'))
            try{& $verify;$false}catch{$true}
        } $definition.Replace($mutation[0],$mutation[1]) $verify
        if(!$detected){throw 'ImportStatisticMutantSurvived'}
        $killed++
        $outcomes.Add(@{Original=$mutation[0];Replacement=$mutation[1];State='Killed'})
    }
    [pscustomobject]@{Seed=73591;PropertyCases=64;MalformedCases=68;MutantsKilled=$killed;MutantsTotal=$mutants.Count;Mutations=$outcomes.ToArray()}
}

function Invoke-QuietImportIntegration {
    <#
    .SYNOPSIS
    Measures paired fresh pwsh processes, retaining bounded samples and explicit measurement limits.
    .PARAMETER WorkspaceRoot
    Local monorepo containing the Core module and companion probes.
    .PARAMETER OnProgress
    Optional existing monitor progress callback.
    .PARAMETER Iterations
    Retained baseline/import pairs after one discarded warm-up pair.
    #>
    param([string]$WorkspaceRoot,[scriptblock]$OnProgress,[ValidateRange(3,100)][int]$Iterations=7)
    $checks=Test-QuietImportStatistics
    $manifest=Join-Path $WorkspaceRoot 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1'
    $probe=Join-Path $PSScriptRoot 'Import.Probe.ps1'
    $runner=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
    $samples=[Collections.Generic.List[object]]::new()
    $pairs=[Collections.Generic.List[object]]::new()
    for($iteration=0;$iteration -le $Iterations;$iteration++){
        $pair=@{}
        foreach($mode in $(if($iteration%2){@('Import','Baseline')}else{@('Baseline','Import')})){
            if($OnProgress){& $OnProgress "Fresh pwsh import pair $iteration/$Iterations ($mode)" Running 0 0}
            $invocationWatch=[Diagnostics.Stopwatch]::StartNew()
            $result=quiet -AsObject -Role Infrastructure -TimeoutSeconds 60 -Data ([Text.StringBuilder]::new()) -Output {
                param($event,$runtime)
                if($event.Stream -eq 'stdout'){
                    if($runtime.Data.Length+$event.Text.Length -gt 16384){throw 'ImportProbeOutputLimit'}
                    [void]$runtime.Data.Append($event.Text)
                }
            } -Complete {param($runtime)$runtime.Data.ToString()|ConvertFrom-Json} -FilePath $runner -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',$probe,'-Manifest',$manifest,'-Mode',$mode)
            $invocationWatch.Stop()
            if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis){throw ('ImportProbeFailed: '+$mode+' '+($result.Error|ConvertTo-Json -Compress))}
            $sample=$result.Data
            if($sample.ProcessId -ne $result.Execution.Native.ProcessId -or $sample.ProcessId -eq $PID -or $sample.Mode -cne $mode -or $sample.RuntimeIdentifier -cne [Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier -or $sample.PowerShellVersion -cne $PSVersionTable.PSVersion.ToString() -or $sample.EngineStarted){throw 'ImportProbeIdentityMismatch'}
            foreach($field in @('ElapsedMs','CpuMs','AllocatedBytes')){if(![double]::IsFinite($sample.$field) -or $sample.$field -lt 0){throw 'ImportProbeInvalidMeasurement'}}
            $sample|Add-Member Iteration $iteration
            $sample|Add-Member InvocationElapsedMs $invocationWatch.Elapsed.TotalMilliseconds
            $pair[$mode]=$sample
            if($iteration){$samples.Add($sample)}
        }
        if($iteration){
            $delta=[ordered]@{Iteration=$iteration}
            foreach($field in @('ElapsedMs','CpuMs','AllocatedBytes','ManagedBytesDelta','WorkingSetBytesDelta','PrivateBytesDelta','InvocationElapsedMs')){$delta[$field]=$pair.Import.$field-$pair.Baseline.$field}
            $pairs.Add([pscustomobject]$delta)
        }
    }
    $statistics=[ordered]@{}
    foreach($field in @('ElapsedMs','CpuMs','AllocatedBytes','ManagedBytesDelta','WorkingSetBytesDelta','PrivateBytesDelta','InvocationElapsedMs')){
        $statistics[$field]=@{Import=(Get-QuietImportStatistics @($samples|Where-Object Mode -EQ Import|ForEach-Object $field));Baseline=(Get-QuietImportStatistics @($samples|Where-Object Mode -EQ Baseline|ForEach-Object $field));PairedDelta=(Get-QuietImportStatistics @($pairs|ForEach-Object $field))}
    }
    if($OnProgress){& $OnProgress 'Fresh pwsh import identity, inertness and cost' Passed 1 0}
    [pscustomobject]@{
        Project='FrenchExDev2.QuietCli.Core.PoSh';Passed=1;Failed=0;Kind='FreshSessionImport'
        Manifest=$manifest;ManifestSHA256=(Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
        Profile='Disabled explicitly to isolate import; normal user-profile cost is excluded.'
        WarmupPairs=1;Iterations=$Iterations;Statistics=$statistics;Samples=$samples.ToArray();Pairs=$pairs.ToArray();Validation=$checks
        Limits='Warm filesystem caches, fresh process/module each time. No disk-cold claim, engine startup, first command, retained-memory guarantee, financial cost or performance threshold. CPU and process memory include measurement noise; signed deltas are preserved. InvocationElapsedMs includes startup, probe, JSON, shutdown and parent QuietCli dispatch/callback/telemetry overhead.'
    }
}

function Assert-QuietStartupProbeIdentity {
    <#
    .SYNOPSIS
    Checks the owned native child identity and arm, allowing OS reuse of terminated process IDs.
    .PARAMETER Sample
    Bounded identity returned by the child probe.
    .PARAMETER NativeProcessId
    Actual child PID reported by the parent invocation.
    .PARAMETER Timers
    Expected diagnostic timer arm.
    .PARAMETER Telemetry
    Expected metadata persistence arm.
    #>
    param($Sample,[int]$NativeProcessId,[bool]$Timers,[bool]$Telemetry)
    $checks=[ordered]@{
        ProcessId=@($Sample.ProcessId,$NativeProcessId)
        RuntimeIdentifier=@($Sample.RuntimeIdentifier,[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier)
        PowerShellVersion=@($Sample.PowerShellVersion,$PSVersionTable.PSVersion.ToString())
        Calls=@($Sample.Calls.Count,4)
        MeasurePhases=@($Sample.MeasurePhases,$Timers)
        DatabaseCreated=@($Sample.DatabaseCreated,$Telemetry)
    }
    if($NativeProcessId -le 0 -or $NativeProcessId -eq $PID){throw 'StartupProbeIdentityMismatch: invalid owned child PID'}
    foreach($field in $checks.Keys){
        if($checks[$field][0] -cne $checks[$field][1]){throw ('StartupProbeIdentityMismatch: '+$field+'; '+([ordered]@{Actual=$checks[$field][0];Expected=$checks[$field][1]}|ConvertTo-Json -Compress))}
    }
}

function Test-QuietStartupProbeIdentity {
    <#
    .SYNOPSIS
    Rejects wrong child identities and arms while accepting sequential reuse of a native PID.
    #>
    $nativeProcessId=$PID+1
    $valid=@{ProcessId=$nativeProcessId;RuntimeIdentifier=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;PowerShellVersion=$PSVersionTable.PSVersion.ToString();Calls=@(1,2,3,4);MeasurePhases=$true;DatabaseCreated=$true}
    # Two separate invocations may have the same PID after the first child has exited.
    foreach($invocation in 1..2){Assert-QuietStartupProbeIdentity ([pscustomobject]$valid) $nativeProcessId $true $true}
    $invalid=@{ProcessId=$nativeProcessId+1;RuntimeIdentifier='wrong-rid';PowerShellVersion='wrong-version';Calls=@(1,2,3);MeasurePhases=$false;DatabaseCreated=$false}
    foreach($field in $invalid.Keys){
        $sample=$valid.Clone();$sample[$field]=$invalid[$field];$message=$null
        try{Assert-QuietStartupProbeIdentity ([pscustomobject]$sample) $nativeProcessId $true $true}catch{$message=$_.Exception.Message}
        if(!$message -or !$message.StartsWith('StartupProbeIdentityMismatch: '+$field+';')){throw ('StartupIdentityRegression: '+$field)}
    }
    foreach($invalidPid in @($PID,0)){
        $rejected=$false
        try{Assert-QuietStartupProbeIdentity ([pscustomobject]$valid) $invalidPid $true $true}catch{$rejected=$true}
        if(!$rejected){throw 'StartupParentIdentityAccepted'}
    }
    [pscustomobject]@{ReusedPidInvocations=2;RejectedIdentities=8}
}

function Invoke-QuietStartupIntegration {
    <#
    .SYNOPSIS
    Measures import and first/warm calls in fresh owned processes with telemetry and timers independently toggled.
    .PARAMETER WorkspaceRoot
    Built monorepo; uses its exact Core manifest.
    .PARAMETER RunDirectory
    Owned campaign directory, never the user's configuration or database.
    .PARAMETER Iterations
    Retained repetitions per arm after one discarded warm-up process per arm.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory,[ValidateRange(3,30)][int]$Iterations=7)
    $manifest=[IO.Path]::Combine($WorkspaceRoot,'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
    $probe=[IO.Path]::Combine($PSScriptRoot,'Startup.Probe.ps1')
    $runner=[IO.Path]::Combine($PSHOME,$(if($IsWindows){'pwsh.exe'}else{'pwsh'}))
    $executable=(Get-Command git -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
    $validation=Test-QuietStartupProbeIdentity
    $samples=[Collections.Generic.List[object]]::new()
    $arms=@(@{Telemetry=$false;Timers=$false},@{Telemetry=$true;Timers=$false},@{Telemetry=$false;Timers=$true},@{Telemetry=$true;Timers=$true})
    for($iteration=0;$iteration -le $Iterations;$iteration++){
        foreach($offset in 0..3){
            $arm=$arms[($iteration+$offset)%4]
            $directory=[IO.Path]::Combine($RunDirectory,'startup',([guid]::NewGuid().ToString('N')))
            [void][IO.Directory]::CreateDirectory($directory)
            $hosting=if($env:QUIETCLI_EXPECT_ENGINE_MODE){$env:QUIETCLI_EXPECT_ENGINE_MODE}else{'Auto'}
            $yaml="schemaVersion: 1`ntelemetry:`n  enabled: $(([string]$arm.Telemetry).ToLowerInvariant())`n  database: measurements.sqlite`nengine:`n  hosting: $hosting`n"
            [IO.File]::WriteAllText([IO.Path]::Combine($directory,'config.yaml'),$yaml,[Text.UTF8Encoding]::new($false))
            $arguments=@('-NoLogo','-NoProfile','-NonInteractive','-File',$probe,'-Manifest',$manifest,'-Executable',$executable,'-ConfigurationDirectory',$directory)
            if($arm.Timers){$arguments+='-MeasurePhases'}
            $diagnostic=@{Diagnostic=''}
            $result=quiet -AsObject -Role Infrastructure -TimeoutSeconds 90 -State $diagnostic -Data ([Text.StringBuilder]::new()) -Output {
                param($event,$runtime)
                if($event.Stream -eq 'stdout'){
                    if($runtime.Data.Length+$event.Text.Length -gt 32768){throw 'StartupProbeOutputLimit'}
                    [void]$runtime.Data.Append($event.Text)
                }
                elseif($runtime.State.Diagnostic.Length -lt 4096){$runtime.State.Diagnostic+=$event.Text}
            } -Complete {param($runtime)if($runtime.State.Diagnostic){throw $runtime.State.Diagnostic};$runtime.Data.ToString()|ConvertFrom-Json} -FilePath $runner -ArgumentList $arguments
            if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis){throw ('StartupProbeFailed: outcome='+$result.Outcome+'; exit='+$result.Execution.Native.ExitCode+'; '+$diagnostic.Diagnostic+'; '+(($result.Error|ForEach-Object Message) -join '; '))}
            $sample=$result.Data
            try{Assert-QuietStartupProbeIdentity $sample $result.Execution.Native.ProcessId $arm.Timers $arm.Telemetry}catch{throw ($_.Exception.Message+'; iteration='+$iteration+'; arm='+$offset)}
            if($hosting -cne 'Auto' -and $sample.EngineMode -cne $hosting){throw 'StartupProbeHostingMismatch'}
            foreach($call in $sample.Calls){
                if($call.InvocationMs -lt 0 -or ![double]::IsFinite($call.InvocationMs)){throw 'StartupProbeTimingInvalid'}
                if($arm.Timers -and $arm.Telemetry -and $null -eq $call.SqliteWriteMs){throw 'StartupStorageTimersMissing'}
                if(!$arm.Telemetry -and $null -ne $call.SaveRoundTripMs){throw 'DisabledStartupStorageMeasured'}
            }
            $sample|Add-Member TelemetryEnabled $arm.Telemetry
            $sample|Add-Member Iteration $iteration
            if($iteration){$samples.Add($sample)}
        }
    }
    [pscustomobject]@{Kind='FreshProcessStartup';Iterations=$Iterations;WarmupPerArm=1;Validation=$validation;Samples=$samples.ToArray();Limits='Fresh process/module/engine; warm filesystem caches. Child PID checked against its native invocation; the OS may reuse terminated process IDs. Fixed git --version, three warm calls after the first. Telemetry and diagnostic timers are independent arms with rotating order. Timers add overhead; no speed threshold or causal OS comparison. Queue wait may include prior background preparation. Save round-trip includes the nested storage phases; do not add it to them. SQLite write includes binding, stepping and implicit transaction durability, not pure disk time.'}
}

function Invoke-QuietImportDiagnostics {
    <#
    .SYNOPSIS
    Measures independent fresh-process controls for import, cmdlet first use and source loading.
    .PARAMETER WorkspaceRoot
    Local monorepo supplying the exact Core manifest.
    .PARAMETER OnProgress
    Optional existing integration progress callback.
    #>
    param([string]$WorkspaceRoot,[scriptblock]$OnProgress)
    $runner=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
    $diagnostics=[Collections.Generic.List[object]]::new()
    $passed=0
    foreach($mode in @('Import','Import','Import','CmdletOperations','PreloadManagement','PreloadUtility','PreloadBoth','Read','Parse','DotSource')){
        if($OnProgress){& $OnProgress "Import diagnostic: $mode" Running $passed 0}
        $result=quiet -AsObject -Role Infrastructure -TimeoutSeconds 90 -Data ([Text.StringBuilder]::new()) -Output {
            param($event,$runtime)
            if($event.Stream -eq 'stdout'){
                if($runtime.Data.Length+$event.Text.Length -gt 32768){throw 'ImportDiagnosticOutputLimit'}
                [void]$runtime.Data.Append($event.Text)
            }elseif($event.Stream -eq 'stderr'){
                if(!$runtime.State.ContainsKey('Diagnostic')){$runtime.State.Diagnostic=''}
                if($runtime.State.Diagnostic.Length -lt 4096){$runtime.State.Diagnostic+=$event.Text}
            }
        } -Complete {param($runtime)if($runtime.State.ContainsKey('Diagnostic')){throw $runtime.State.Diagnostic};$runtime.Data.ToString()|ConvertFrom-Json} -FilePath $runner -ArgumentList @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'Import.DiagnosticProbe.ps1'),'-Manifest',(Join-Path $WorkspaceRoot 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1'),'-Mode',$mode)
        if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis){throw ('ImportDiagnosticFailed: '+($result.Error|ConvertTo-Json -Compress))}
        $diagnostics.Add($result.Data)
    }
    [pscustomobject]@{Kind='ImportDiagnostics';Samples=$diagnostics.ToArray();Count=$diagnostics.Count}
}
