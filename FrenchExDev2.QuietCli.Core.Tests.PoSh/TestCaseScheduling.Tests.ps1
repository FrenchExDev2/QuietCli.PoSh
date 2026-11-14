function Test-QuietCaseScheduling {
    <#
    .SYNOPSIS
    Proves manifest validation, barrier preservation, bounded overlap, failure admission and process cleanup.
    .PARAMETER WorkspaceRoot
    Checkout supplying the engine-independent scheduler and its process helper.
    .PARAMETER RunDirectory
    Owned fixtures and evidence; no existing user files or external services are used.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    . (Join-Path $PSScriptRoot 'GitMutationScheduling.Tests.ps1')
    try{Test-QuietGitMutationScheduling -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}catch{
        Write-WorkspaceJson (Join-Path $RunDirectory 'git-mutation-scheduling-failure.json') @{Message=$_.Exception.Message;Stack=$_.ScriptStackTrace;Position=$_.InvocationInfo.PositionMessage}
        throw
    }
    $root=Join-Path $RunDirectory 'test-case-scheduling';[void][IO.Directory]::CreateDirectory($root)
    $utf8=[Text.UTF8Encoding]::new($false)
    $manifest=Join-Path $root 'fixture.psd1'
    $valid=@'
@{PrivateData=@{QuietCli=@{TestExecution=@{
 SchemaVersion=1;DefaultMode='Ordered';DefaultReason='Preserve owned fixture order.';MaxParallelCases=2
 Cases=@{'a'=@{Mode='IsolatedProcess';Reason='Owns its complete fixture state.';TimeoutSeconds=30};'b'=@{Mode='Exclusive';Reason='Measures process-wide allocation state.'}}
}}}}
'@
    [IO.File]::WriteAllText($manifest,$valid,$utf8)
    $policy=Get-QuietTestExecutionPolicy -ManifestPath $manifest -CaseNames @('a','b','c')
    Assert-QuietEqual $policy.MaxParallelCases 2
    $damages=@(
        @('SchemaVersion=1','SchemaVersion=2'),@('DefaultMode=''Ordered''','DefaultMode=''IsolatedProcess'''),
        @('MaxParallelCases=2','MaxParallelCases=0'),@('MaxParallelCases=2','MaxParallelCases=33'),@('MaxParallelCases=2','MaxParallelCases=''2'''),
        @('DefaultReason=''Preserve owned fixture order.''','DefaultReason='''''),@('SchemaVersion=1','Unexpected=1'),
        @("'a'=@{","'orphan'=@{"),@("Mode='Exclusive'","Mode='Unknown'"),@('TimeoutSeconds=30','TimeoutSeconds=0'),
        @('TimeoutSeconds=30','TimeoutSeconds=''30'''),@('TimeoutSeconds=30','Timeout=30'),@("Reason='Owns its complete fixture state.';",''),
        @('TestExecution=@{',"TestExecution=`$null;Ignored=@{")
    )
    foreach($damage in $damages){
        [IO.File]::WriteAllText($manifest,$valid.Replace($damage[0],$damage[1]),$utf8)
        $rejected=$false;try{$null=Get-QuietTestExecutionPolicy -ManifestPath $manifest -CaseNames @('a','b','c')}catch{$rejected=$_.Exception.Message.StartsWith('TestExecutionPolicy',[StringComparison]::Ordinal)}
        Assert-QuietEqual $rejected $true 'Malformed execution declarations must fail closed'
    }
    [IO.File]::WriteAllText($manifest,'@{}',$utf8)
    $default=Get-QuietTestExecutionPolicy -ManifestPath $manifest -CaseNames @('a','b','c')
    Assert-QuietEqual $default.DefaultMode Ordered
    Assert-QuietEqual $default.MaxParallelCases 1
    $random=[Random]::new(111188)
    foreach($iteration in 1..64){
        $names=@(foreach($index in 0..19){'case-é漢-'+$index})
        $overrides=@{}
        foreach($name in $names){$overrides[$name]=@{Mode=@('Ordered','Exclusive','IsolatedProcess')[$random.Next(3)];Reason='Independent generated scheduling fixture.'}}
        $generated=@{DefaultMode='Ordered';DefaultReason='Keep order';MaxParallelCases=$random.Next(1,9);Cases=$overrides}
        $budget=$random.Next(1,9);$plan=Get-QuietTestExecutionPlan -CaseNames $names -Policy $generated -MaxConcurrency $budget
        Assert-QuietEqual ((@($plan.Stages|ForEach-Object {$_.Cases.Name})) -join '|') ($names -join '|')
        Assert-QuietEqual $plan.MaxConcurrency ([Math]::Min($budget,$generated.MaxParallelCases))
        foreach($stage in $plan.Stages){
            if($stage.Mode -ceq 'IsolatedProcess'){
                Assert-QuietEqual @($stage.Cases|Where-Object Mode -CNE IsolatedProcess).Count 0 'Exclusive and ordered barriers cannot enter a parallel batch'
            }else{Assert-QuietEqual $stage.Cases.Count 1 'Barriers remain individual ordered stages'}
        }
    }
    $makeCase={param($name,$index,$timeout=60)[pscustomobject]@{Name=$name;Index=$index;Mode='IsolatedProcess';TimeoutSeconds=$timeout}}
    $worker=Join-Path $root 'worker.ps1'
    $source=@'
[CmdletBinding(SupportsShouldProcess)]
param($WorkspaceRoot,$RunDirectory,$Suite,$Case,[switch]$CaseWorker,[int]$MaxConcurrency,[switch]$SkipTty,$ExpectedRuntimeIdentifier)
if(!$PSCmdlet.ShouldProcess($RunDirectory,'Run owned case protocol fixture')){return}
$ErrorActionPreference='Stop'
$name=[Management.Automation.WildcardPattern]::Unescape($Case)
if($name -notlike $Case -or !$CaseWorker -or $MaxConcurrency -ne 1 -or $Suite -cne 'Core'){throw 'OwnedWorkerArgumentsInvalid'}
$start=[DateTimeOffset]::UtcNow
$record=@{Name=$name;PID=$PID;StartedUtc=$start.ToString('o');InternalConcurrency=$MaxConcurrency;SkipTty=[bool]$SkipTty;Rid=$ExpectedRuntimeIdentifier;Configuration=(Join-Path $RunDirectory 'config');Database=(Join-Path $RunDirectory 'private.sqlite')}
[IO.File]::WriteAllText((Join-Path $RunDirectory 'started.json'),($record|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$parent=Split-Path $RunDirectory -Parent
if($name -eq 'slow'){
 while(!@(Get-ChildItem $parent -Recurse -Filter case-result.json|Where-Object {(Get-Content $_.FullName -Raw -Encoding utf8|ConvertFrom-Json).Name -eq 'fail'}).Count){if(([DateTimeOffset]::UtcNow-$start).TotalSeconds -gt 40){throw 'OwnedFailureObservationBarrierFailed'};[Threading.Thread]::Sleep(20)}
}
if(Test-Path (Join-Path (Split-Path $parent -Parent) 'require-overlap')){
 while(@(Get-ChildItem $parent -Recurse -Filter started.json).Count -lt 2){if(([DateTimeOffset]::UtcNow-$start).TotalSeconds -gt 15){throw 'OwnedOverlapBarrierFailed'};[Threading.Thread]::Sleep(20)}
}
if($name -eq 'timeout'){[Threading.Thread]::Sleep(30000)}else{[Threading.Thread]::Sleep(300)}
if($name -eq 'missing'){exit 0}
$failed=$name -eq 'fail';$record.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
[IO.File]::WriteAllText((Join-Path $RunDirectory 'finished.json'),($record|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$summary=@{State=@{State=if($failed){'Failed'}else{'Success'};Passed=[int](!$failed);Failed=[int]$failed;ProcessId=$PID;Platform=$ExpectedRuntimeIdentifier};Suites=@(@{Partial=$true;Incomplete=$false;Passed=[int](!$failed);Failed=[int]$failed;Cases=@(@{Name=if($name -eq 'wrong'){'other'}else{$name};State=if($failed){'Failed'}else{'Passed'};Error=if($failed){'owned assertion failure'}else{$null}})})}
if($name -eq 'contradiction'){$summary.State.Failed=1}
[IO.File]::WriteAllText((Join-Path $RunDirectory 'summary.json'),($summary|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
if($failed){exit 1}
'@
    [IO.File]::WriteAllText($worker,$source,$utf8)
    $cases=@((& $makeCase 'a' 0),(& $makeCase 'bracket [é]*?' 1),(& $makeCase 'c' 2))
    $parallel=Join-Path $root parallel;[void][IO.Directory]::CreateDirectory($parallel)
    [IO.File]::WriteAllText((Join-Path $parallel 'require-overlap'),'owned barrier',$utf8)
    $result=Invoke-QuietTestCaseWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory $parallel -Cases $cases -MaxConcurrency 2 -WorkerPath $worker -SkipTty -ExpectedRuntimeIdentifier fixture-rid
    Assert-QuietEqual $result.MaxActive 2
    Assert-QuietEqual @($result.Cases|Where-Object State -CNE Passed).Count 0
    Assert-QuietEqual ($result.Cases.Name -join '|') ($cases.Name -join '|') 'Receipt order follows declarations, not completion order'
    $observed=@(Get-ChildItem $parallel -Recurse -Filter finished.json|ForEach-Object {Get-Content $_.FullName -Raw -Encoding utf8|ConvertFrom-Json})
    Assert-QuietEqual @($observed.PID|Select-Object -Unique).Count 3
    Assert-QuietEqual @($observed.Configuration|Select-Object -Unique).Count 3
    Assert-QuietEqual @($observed.Database|Select-Object -Unique).Count 3
    Assert-QuietEqual @($observed|Where-Object {$_.InternalConcurrency -ne 1 -or !$_.SkipTty -or $_.Rid -cne 'fixture-rid'}).Count 0
    $a=$observed|Where-Object Name -CEQ a;$b=$observed|Where-Object Name -CEQ 'bracket [é]*?'
    if([DateTimeOffset]$a.StartedUtc -ge [DateTimeOffset]$b.FinishedUtc -or [DateTimeOffset]$b.StartedUtc -ge [DateTimeOffset]$a.FinishedUtc){throw 'TestCaseWorkersDidNotOverlap'}
    $serial=Invoke-QuietTestCaseWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory (Join-Path $root serial) -Cases $cases -MaxConcurrency 1 -WorkerPath $worker
    Assert-QuietEqual $serial.MaxActive 1
    Assert-QuietEqual (($serial.Cases|ForEach-Object {$_.Name+'='+$_.State}) -join '|') (($result.Cases|ForEach-Object {$_.Name+'='+$_.State}) -join '|') 'Serial and parallel outcomes agree'
    $failureCases=@((& $makeCase 'fail' 0),(& $makeCase 'slow' 1),(& $makeCase 'pending' 2))
    $stopped=Invoke-QuietTestCaseWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory (Join-Path $root stopped) -Cases $failureCases -MaxConcurrency 2 -WorkerPath $worker -StopOnFirstFailure
    Assert-QuietEqual $stopped.Cases.Count 2 'Already admitted workers are drained'
    Assert-QuietEqual ($stopped.NotStarted -join '|') pending 'Observed failure closes admission'
    Assert-QuietEqual ($stopped.Cases|Where-Object Name -CEQ fail).Error 'owned assertion failure'
    $failures=0
    foreach($name in @('missing','wrong','contradiction','timeout')){
        $bad=Invoke-QuietTestCaseWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory (Join-Path $root $name) -Cases @(& $makeCase $name 0 $(if($name -ceq 'timeout'){1}else{30})) -MaxConcurrency 1 -WorkerPath $worker
        Assert-QuietEqual $bad.Cases[0].State Failed
        if($bad.Cases[0].Error -notlike 'TestCaseWorker*'){throw 'TestCaseWorkerInfrastructureAccepted'}
        if(Get-Process -Id $bad.Cases[0].WorkerProcessId -ErrorAction SilentlyContinue){throw 'TimedOutOrCompletedWorkerStillRunning'}
        $failures++
    }
    $cancel=[Threading.CancellationTokenSource]::new();$cancelState=@{PID=0}
    try{
        $cancelled=$false
        try{$null=Invoke-QuietTestCaseWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory (Join-Path $root cancelled) -Cases @(& $makeCase timeout 0) -MaxConcurrency 1 -WorkerPath $worker -CancellationToken $cancel.Token -OnCase {param($name,$state,$detail)if($state -ceq 'Running'){$cancelState.PID=$detail.WorkerProcessId;$cancel.Cancel()}}}catch{$cancelled=$_.Exception -is [OperationCanceledException] -or $_.Exception.InnerException -is [OperationCanceledException]}
        Assert-QuietEqual $cancelled $true
        if(!$cancelState.PID -or (Get-Process -Id $cancelState.PID -ErrorAction SilentlyContinue)){throw 'CancelledWorkerNotCleanedUp'}
    }finally{$cancel.Dispose()}
    $preview=Join-Path $root preview
    $null=Invoke-QuietTestCaseWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory $preview -Cases $cases -WorkerPath $worker -WhatIf
    Assert-QuietEqual (Test-Path -LiteralPath $preview) $false
    # Mutate the actual library in a complete owned dependency layout, then assert independent invariants.
    $mutantRoot=Join-Path $root mutant;[void][IO.Directory]::CreateDirectory((Join-Path $mutantRoot lib))
    Copy-Item (Join-Path $WorkspaceRoot scripts/lib/Ci.Process.psm1) $mutantRoot
    $library=[IO.File]::ReadAllText((Join-Path $WorkspaceRoot scripts/lib/TestCaseScheduling.psm1),[Text.Encoding]::UTF8)
    $limitAnchor='$active.Count -lt $MaxConcurrency'
    $barrierAnchor='$entry.Mode -ceq ''IsolatedProcess'' -and $stages.Count'
    foreach($anchor in @($limitAnchor,$barrierAnchor)){if(([regex]::Matches($library,[regex]::Escape($anchor))).Count -ne 1){throw 'TestCaseSchedulingMutationAnchorMissing'}}
    $mutantPath=Join-Path $mutantRoot lib/Mutant.psm1
    [IO.File]::WriteAllText($mutantPath,$library.Replace($limitAnchor,'$active.Count -lt 32').Replace($barrierAnchor,'$stages.Count'),$utf8)
    Import-Module $mutantPath -Prefix Mutant -Force
    try{
        $mutant=Invoke-MutantQuietTestCaseWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory (Join-Path $root mutant-limit) -Cases $cases -MaxConcurrency 1 -WorkerPath $worker
        if($mutant.MaxActive -le 1 -or @($mutant.Cases|Where-Object State -CNE Passed).Count){throw 'ConcurrencyLimitMutantNotIndependentlyDetected'}
        $mutantPolicy=@{MaxParallelCases=2;DefaultMode='Ordered';DefaultReason='Keep barriers';Cases=@{a=@{Mode='IsolatedProcess';Reason='Owned state'};b=@{Mode='Exclusive';Reason='Global measurement'}}}
        $mutantPlan=Get-MutantQuietTestExecutionPlan -CaseNames @('a','b') -Policy $mutantPolicy -MaxConcurrency 2
        if(!@($mutantPlan.Stages|Where-Object {$_.Mode -ceq 'IsolatedProcess' -and @($_.Cases|Where-Object Mode -CNE IsolatedProcess).Count}).Count){throw 'ExclusiveBarrierMutantNotDetected'}
    }finally{Remove-Module Mutant -Force}
    Write-WorkspaceJson (Join-Path $root 'summary.json') @{PolicyRejections=$damages.Count;PlanProperties=64;Seed=111188;ObservedPeak=$result.MaxActive;IsolatedProcesses=$observed.Count;SerialParallelEquivalent=$true;InfrastructureRejections=$failures;CancellationCleanup=$true;PreviewNoEffects=$true;MutantsKilled=2}
}
