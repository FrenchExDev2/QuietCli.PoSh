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
    $manifest=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1'
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
            if($sample.Mode -cne $mode -or $sample.RuntimeIdentifier -cne [Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier -or $sample.PowerShellVersion -cne $PSVersionTable.PSVersion.ToString() -or $sample.EngineStarted){throw 'ImportProbeIdentityMismatch'}
            foreach($field in @('ElapsedMs','CpuMs','AllocatedBytes')){if(![double]::IsFinite($sample.$field) -or $sample.$field -lt 0){throw 'ImportProbeInvalidMeasurement'}}
            $sample|Add-Member Iteration $iteration
            $sample|Add-Member InvocationElapsedMs $invocationWatch.Elapsed.TotalMilliseconds
            $pair[$mode]=$sample
            if($iteration){$samples.Add($sample)}
        }
        if($pair.Import.ProcessId -eq $pair.Baseline.ProcessId){throw 'ImportProbeReusedProcess'}
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
