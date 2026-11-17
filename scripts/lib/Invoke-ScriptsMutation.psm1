#Objective: Runs the scripts mutation campaign: incremental cache, persistent slot workers, unmutated baseline, reports.
#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ScriptMutation.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'RunToolCache.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceJson.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ReportPaths.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ScriptsWorker.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ScriptMutationSlot.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ScriptMutationCache.psm1')) -DisableNameChecking -ErrorAction Stop

function Invoke-QuietScriptInvokeScriptsMutation {
    <#
    .SYNOPSIS
    Validates the targets, prepares the pinned Pester, then launches and supervises one mutation campaign; returns its outcome.
    .PARAMETER WorkspaceRoot
    Repository root: test tools, report root and QUIETCLI_WORKSPACE_ROOT of every test run.
    .PARAMETER ScriptsRoot
    Scripts root holding the target libraries; it is copied, never modified.
    .PARAMETER TestsRoot
    Tests root holding the unit test files of the targets.
    .PARAMETER TargetsPath
    Targets file (mutation.targets.psd1).
    .PARAMETER Target
    Optional target names to run (a CI shard); all targets when empty.
    .PARAMETER ThrottleLimit
    Persistent slot workers, one isolated scripts copy each.
    .PARAMETER Seed
    Test seed shared by the baseline and every mutant run; generated when 0.
    .PARAMETER Headless
    Disables the visible monitor (CI).
    .PARAMETER RunDirectory
    New run directory; an existing directory is rejected.
    .PARAMETER TimeoutSeconds
    Wall-clock limit of the whole campaign.
    .PARAMETER Offline
    Requires the pinned test tools to be cached already.
    .PARAMETER NoCache
    Neither reads nor writes the incremental cache: every mutant runs (qualification).
    .PARAMETER CacheDirectory
    Incremental cache root; defaults to <WorkspaceRoot>/.cache/script-mutation.
    .PARAMETER PruneCache
    After a complete campaign, deletes every cache document this run did not key, so the cache holds only the outcomes
    of the current sources. Every document of targets left out by Target is deleted too: prune a cache dedicated to the
    selected targets (one per CI shard). Rejected with NoCache.
    .PARAMETER RecycleAfter
    Jobs after which a slot worker is replaced by a fresh process.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$ScriptsRoot,[Parameter(Mandatory)][string]$TestsRoot,[Parameter(Mandatory)][string]$TargetsPath,[string[]]$Target=@(),[ValidateRange(1,32)][int]$ThrottleLimit=1,[int]$Seed,[switch]$Headless,[string]$RunDirectory,[int]$TimeoutSeconds=3600,[switch]$Offline,[switch]$NoCache,[string]$CacheDirectory,[switch]$PruneCache,[ValidateRange(1,100000)][int]$RecycleAfter=200)
    if($NoCache -and $PruneCache){throw 'ScriptMutationCacheOptionsConflict'}
    $WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot);$ScriptsRoot=[IO.Path]::GetFullPath($ScriptsRoot);$TestsRoot=[IO.Path]::GetFullPath($TestsRoot)
    if(![IO.Directory]::Exists($ScriptsRoot)){throw 'ScriptMutationPathInvalid: scripts-root'}
    if(![IO.Directory]::Exists($TestsRoot)){throw 'ScriptMutationPathInvalid: tests-root'}
    $targets=@(Read-QuietScriptMutationTargets -Path $TargetsPath -ScriptsRoot $ScriptsRoot -TestsRoot $TestsRoot)
    $selected=@($Target|Where-Object {![string]::IsNullOrWhiteSpace($_)})
    foreach($name in $selected){if(@($targets|Where-Object Name -CEQ $name).Count -eq 0){throw "ScriptMutationTargetUnknown: $name"}}
    if($selected.Count){$targets=@($targets|Where-Object {$_.Name -cin $selected})}
    $platform=Get-QuietScriptsMutationPlatform
    # A stale Equivalent declaration fails here, before any slot starts.
    $counts=foreach($entry in $targets){$all=@(Get-QuietScriptMutants -Text ([IO.File]::ReadAllText($entry.ModulePath)) -Functions $entry.Functions -Module $entry.Module);$null=Select-QuietScriptMutationEquivalents -Mutants $all -Equivalent @($entry.Equivalent) -Platform $platform -Target $entry.Name;$all.Count}
    if($Seed -eq 0){$Seed=[Random]::Shared.Next(1,[int]::MaxValue)}
    if(!$Headless -and !$IsWindows){throw 'Use the Windows host launcher for a visible local monitor; Headless is reserved for CI.'}
    $tools=Initialize-QuietTestTools -WorkspaceRoot $WorkspaceRoot -Tool pester -Offline:$Offline
    if([string]::IsNullOrWhiteSpace($CacheDirectory)){$CacheDirectory=[IO.Path]::Combine($WorkspaceRoot,'.cache','script-mutation')}
    $cache=if($NoCache){''}else{[IO.Path]::GetFullPath($CacheDirectory)}
    if([string]::IsNullOrWhiteSpace($RunDirectory)){$RunDirectory=[IO.Path]::Combine((Get-QuietReportRoot $WorkspaceRoot 'scripts-mutation'),([DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)))}
    $RunDirectory=[IO.Path]::GetFullPath($RunDirectory)
    if([IO.Directory]::Exists($RunDirectory) -or [IO.File]::Exists($RunDirectory)){throw 'TestRunDirectoryExists'}
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $request=[ordered]@{
        WorkspaceRoot=$WorkspaceRoot;ScriptsRoot=$ScriptsRoot;TestsRoot=$TestsRoot;RunDirectory=$RunDirectory;Seed=$Seed;ThrottleLimit=$ThrottleLimit
        PesterModulePath=$tools.PesterModulePath;CacheDirectory=$cache;PruneCache=[bool]$PruneCache;RecycleAfter=$RecycleAfter
        Targets=@($targets|ForEach-Object {[ordered]@{Name=$_.Name;Module=$_.Module;Functions=$_.Functions;UnitTestFiles=$_.UnitTestFiles;Break=$_.Break;Inputs=[string[]]@($_.Inputs);Equivalent=@($_.Equivalent)}})
    }
    $requestPath=[IO.Path]::Combine($RunDirectory,'request.json')
    Write-WorkspaceJson $requestPath $request
    Write-Host ("Scripts mutation: targets=$(@($targets.Name) -join ',') mutants=$(($counts|Measure-Object -Sum).Sum) throttle=$ThrottleLimit seed=$Seed cache=$(if($cache){if($PruneCache){'on,prune'}else{'on'}}else{'off'}) run=$RunDirectory")
    $summary=Invoke-QuietScriptsSupervisedWorker -ModulePath ([IO.Path]::Combine($PSScriptRoot,'Invoke-ScriptsMutation.psm1')) -WorkerFunction Invoke-QuietScriptsMutationWorker -RequestPath $requestPath -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -Headless:$Headless -TimeoutSeconds $TimeoutSeconds
    $state=[string]$summary.State.State
    $reportPath=[IO.Path]::Combine($RunDirectory,'report.json')
    $report=if([IO.File]::Exists($reportPath)){Get-Content -LiteralPath $reportPath -Raw -Encoding utf8|ConvertFrom-Json}else{$null}
    foreach($entry in @(if($report){$report.Targets})){Write-Host ('Mutation score: {0} {1:0.##} % (break {2} %) killed={3} timeout={4} survived={5} compile={6} equivalent={7} cached={8}' -f $entry.Name,[double]$entry.Score,$entry.Break,$entry.Killed,$entry.Timeout,$entry.Survived,$entry.CompileError,$entry.Equivalent,$entry.Cached)}
    $incomplete=$null -eq $report -or $true -eq $report.PSObject.Properties['Incomplete']?.Value
    if($report -and $incomplete){Write-Host ('Mutation stopped: target={0} not-run={1}; {2}' -f $report.Crash.Target,(@($report.Crash.NotRun) -join ','),$report.Crash.Error)}
    [pscustomobject][ordered]@{
        State=$state;Passed=[bool]($report -and $report.Passed);Incomplete=$incomplete;Seed=$Seed;RunDirectory=$RunDirectory;Report=$reportPath
        Markdown=[IO.Path]::Combine($RunDirectory,'report.md');Targets=@(if($report){$report.Targets|Select-Object Name,Score,Break,Passed,Killed,Timeout,Survived,CompileError,Equivalent,Cached})
        ExitCode=$(if($state -ceq 'Success' -and $report -and $report.Passed){0}else{1})
    }
}

function Get-QuietScriptsMutationPlatform {
    <#
    .SYNOPSIS
    Names the current platform as the Equivalent declarations do: Windows, MacOS or Linux.
    #>
    if($IsWindows){'Windows'}elseif($IsMacOS){'MacOS'}else{'Linux'}
}

function Copy-QuietScriptsMutationTree {
    <#
    .SYNOPSIS
    Copies a scripts tree into a new slot directory, skipping links, and returns the copy root.
    .PARAMETER Source
    Scripts root to copy.
    .PARAMETER Destination
    New directory.
    #>
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination)
    [void][IO.Directory]::CreateDirectory($Destination)
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($Source)
    while($pending.Count){
        $directory=$pending.Pop()
        $relative=[IO.Path]::GetRelativePath($Source,$directory)
        $target=if($relative -ceq '.'){$Destination}else{[IO.Path]::Combine($Destination,$relative)}
        [void][IO.Directory]::CreateDirectory($target)
        foreach($entry in [IO.DirectoryInfo]::new($directory).EnumerateFileSystemInfos()){
            if($entry.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)){continue}
            if($entry -is [IO.DirectoryInfo]){$pending.Push($entry.FullName)}else{[IO.File]::Copy($entry.FullName,[IO.Path]::Combine($target,$entry.Name))}
        }
    }
    $Destination
}

function Invoke-QuietScriptsMutationWorker {
    <#
    .SYNOPSIS
    Worker body: per target reuses cached outcomes, runs the unmutated baseline twice, then the other mutants on persistent slots.
    .DESCRIPTION
    Each slot owns a scripts copy and one reused pwsh worker (ScriptMutationSlot.psm1). A mutant is written into an idle
    slot's copy, run with bail-on-first-failure, then the original bytes are restored. A slot that times out or crashes
    is restarted, and every slot is recycled after RecycleAfter jobs. The second baseline run in the same worker must
    match the first, which proves that the state reset between runs works for this target. A mutant of a function with
    its own test blocks runs them first, then the other blocks (Get-QuietScriptMutationFocus), once that split has
    passed every baseline test on the unmutated sources; the split is recorded with the baseline. Killed and Survived
    outcomes are written to the cache when it is enabled; with PruneCache, a complete campaign then deletes every cache
    document it did not key.
    .PARAMETER RequestPath
    request.json written by Invoke-QuietScriptInvokeScriptsMutation.
    #>
    param([Parameter(Mandatory)][string]$RequestPath)
    $ErrorActionPreference='Stop'
    $PSStyle.OutputRendering='PlainText'
    $request=Get-Content -LiteralPath $RequestPath -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable
    $runDirectory=$request.RunDirectory
    $cache=[string]$request.CacheDirectory
    $statusPath=[IO.Path]::Combine($runDirectory,'status.json');$summaryPath=[IO.Path]::Combine($runDirectory,'summary.json')
    $status=[ordered]@{
        Project='FrenchExDev2.QuietCli.Scripts.Mutation';Task=('Mutation scripts ('+(@($request.Targets|ForEach-Object {$_.Name}) -join ', ')+')')
        Workspace=$request.WorkspaceRoot;ProjectDirectory=$request.ScriptsRoot;Platform=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier
        StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');ProcessId=$PID;Passed=0;Failed=0;State='Running';Case='Preparing slots';Error=$null;FinishedUtc=$null
    }
    Write-WorkspaceJson $statusPath $status
    $slotsRoot=[IO.Path]::Combine($runDirectory,'slots')
    $logsRoot=[IO.Path]::Combine($runDirectory,'logs')
    $results=[Collections.Generic.List[object]]::new()
    $usedKeys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $report=$null
    # Targets run in request order: the first $finished are complete, $current is the one running (empty outside any).
    $finished=0;$current=''
    $writeReports={param($Crash)
        $built=New-QuietScriptMutationReport -Targets @($request.Targets|Select-Object -First $finished|ForEach-Object {[pscustomobject]@{Name=$_.Name;Module=$_.Module;Functions=[string[]]@($_.Functions);Break=[int]$_.Break}}) -Results $results.ToArray() -Seed ([int]$request.Seed) -Crash $Crash
        Write-WorkspaceJson ([IO.Path]::Combine($runDirectory,'report.json')) $built
        Write-WorkspaceJson ([IO.Path]::Combine($runDirectory,'mutants.json')) @{Mutants=$results.ToArray()}
        [IO.File]::WriteAllText([IO.Path]::Combine($runDirectory,'report.md'),(ConvertTo-QuietScriptMutationMarkdown $built),[Text.UTF8Encoding]::new($false))
        $built
    }
    $count=[int]$request.ThrottleLimit
    $roots=[string[]]::new($count);$slots=[object[]]::new($count);$generations=[int[]]::new($count)
    # The trusted modules that load and run the tests are part of the engine: editing them invalidates the cache.
    $runner=Get-QuietScriptMutationSha256 (@(foreach($name in 'ScriptMutationSlot.psm1','ScriptsTests.psm1'){(Get-FileHash -LiteralPath ([IO.Path]::Combine($PSScriptRoot,$name)) -Algorithm SHA256).Hash}) -join ',')
    $engine='Pester=6.2.0;PowerShell='+$PSVersionTable.PSVersion+';Platform='+[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier+';Runner='+$runner
    # A baseline duration depends on the machine: its key adds the host, so a cache restored elsewhere (CI) reruns it.
    $machine=[Environment]::MachineName+';'+[Environment]::ProcessorCount
    $toResult={param([string]$TargetName,$Mutant,[string]$MutantStatus,[double]$Seconds,[bool]$Cached)
        $result=[ordered]@{Target=$TargetName}
        foreach($property in $Mutant.PSObject.Properties){$result[$property.Name]=$property.Value}
        $result.Status=$MutantStatus;$result.Seconds=$Seconds;$result.Cached=$Cached
        [pscustomobject]$result
    }
    $startSlot={param([int]$Index)
        $generations[$Index]++
        $slots[$Index]=Start-QuietScriptsMutationSlot -Index $Index -Directory ([IO.Path]::Combine($slotsRoot,[string]$Index,'control-'+$generations[$Index])) -ScriptsRoot $roots[$Index] -TestsRoot $request.TestsRoot -WorkspaceRoot $request.WorkspaceRoot -PesterModulePath $request.PesterModulePath -Seed ([int]$request.Seed)
    }
    $retireSlot={param([int]$Index)
        $slot=$slots[$Index]
        if($null -eq $slot){return}
        Stop-QuietScriptsMutationSlot -Slot $slot
        # A worker that wrote to stderr (crash, kill) keeps its log for diagnosis; the slot directory itself is deleted.
        $log=[IO.Path]::Combine($slot.Directory,'worker.stderr.log')
        if([IO.File]::Exists($log) -and ([IO.FileInfo]::new($log)).Length -gt 0){
            [void][IO.Directory]::CreateDirectory($logsRoot)
            [IO.File]::Copy($log,[IO.Path]::Combine($logsRoot,('slot-{0}-{1}.stderr.log' -f $Index,$generations[$Index])),$true)
        }
        $slots[$Index]=$null
    }
    $runJob={param([int]$Index,[string]$Name,[string[]]$Files,[int]$Timeout)
        if($null -eq $slots[$Index] -or !$slots[$Index].Alive){& $retireSlot $Index;& $startSlot $Index}
        Submit-QuietScriptsMutationJob -Slot $slots[$Index] -Name $Name -UnitTestFiles $Files -TimeoutSeconds $Timeout
        Wait-QuietScriptsMutationJob -Slot $slots[$Index]
    }
    # Runs unmutated jobs {Name, Phases} on every slot at once and returns their outcomes by name.
    $runAll={param([object[]]$Jobs,[string[]]$Files,[int]$Timeout)
        $pending=[Collections.Generic.Queue[object]]::new($Jobs);$running=@{};$outcomes=@{}
        while($pending.Count -or $running.Count){
            for($index=0;$index -lt $count -and $pending.Count;$index++){
                if($running.ContainsKey($index)){continue}
                if($null -eq $slots[$index] -or !$slots[$index].Alive -or $slots[$index].Jobs -ge [int]$request.RecycleAfter){& $retireSlot $index;& $startSlot $index}
                $job=$pending.Dequeue()
                Submit-QuietScriptsMutationJob -Slot $slots[$index] -Name $job.Name -UnitTestFiles $Files -Phases $job.Phases -TimeoutSeconds $Timeout
                $running[$index]=$job
            }
            foreach($index in @($running.Keys)){
                $outcome=Receive-QuietScriptsMutationJob -Slot $slots[$index]
                if($null -eq $outcome){continue}
                if($outcome.State -cin @('Crash','Corrupted')){$slots[$index].Alive=$false}
                $outcomes[$running[$index].Name]=$outcome;$running.Remove($index)
            }
            if($running.Count){[void][Threading.Tasks.Task]::Delay(20).GetAwaiter().GetResult()}
        }
        $outcomes
    }
    try{
        Write-Host ("Seed: $($request.Seed) (replay with -Seed $($request.Seed))")
        Write-Host ('Cache: '+$(if($cache){$cache}else{'disabled'}))
        for($index=0;$index -lt $count;$index++){
            $roots[$index]=Copy-QuietScriptsMutationTree -Source $request.ScriptsRoot -Destination ([IO.Path]::Combine($slotsRoot,[string]$index,'scripts'))
            & $startSlot $index
        }
        foreach($targetEntry in @($request.Targets)){
            $current=[string]$targetEntry.Name
            $relative=[string]$targetEntry.Module
            $files=[string[]]@($targetEntry.UnitTestFiles)
            # Each function's own test blocks run first, then the others: a killed mutant usually stops early.
            $focus=Get-QuietScriptMutationFocus -Sources @($files|ForEach-Object {[IO.File]::ReadAllText([IO.Path]::Combine($request.TestsRoot,$_))}) -Functions @($targetEntry.Functions)
            $original=[IO.File]::ReadAllBytes([IO.Path]::Combine($request.ScriptsRoot,$relative))
            $text=[Text.UTF8Encoding]::new($false).GetString($original)
            if($text.Length -and $text[0] -eq [char]0xFEFF){$text=$text.Substring(1)}
            $mutants=@(Get-QuietScriptMutants -Text $text -Functions @($targetEntry.Functions) -Module $relative)
            $split=Select-QuietScriptMutationEquivalents -Mutants $mutants -Equivalent @($targetEntry.Equivalent) -Platform (Get-QuietScriptsMutationPlatform) -Target $targetEntry.Name
            foreach($mutant in $split.Equivalent){$results.Add((& $toResult $targetEntry.Name $mutant 'Equivalent' 0 $false))}
            $fingerprint=if($cache){Get-QuietScriptMutationTargetFingerprint -ScriptsRoot $request.ScriptsRoot -TestsRoot $request.TestsRoot -WorkspaceRoot $request.WorkspaceRoot -Target $targetEntry}else{$null}
            $keys=if($cache){Get-QuietScriptMutantCacheKeys -Mutants $mutants -TargetFingerprint $fingerprint -EngineFingerprint $engine}else{$null}
            if($keys){foreach($value in $keys.Values){[void]$usedKeys.Add($value)}}
            $baselineKey=if($cache){Get-QuietScriptMutationBaselineKey -TargetFingerprint $fingerprint -EngineFingerprint $engine -Machine $machine}else{$null}
            if($baselineKey){[void]$usedKeys.Add($baselineKey)}
            $queue=[Collections.Generic.Queue[object]]::new();$reused=0
            foreach($mutant in $split.Run){
                $source=New-QuietScriptMutantSource -Text $text -Mutant $mutant
                if(!$source.Compiles){$results.Add((& $toResult $targetEntry.Name $mutant 'CompileError' 0 $false));continue}
                $hit=if($cache){Read-QuietScriptMutantCache -Directory $cache -Key $keys[[string]$mutant.Id]}else{$null}
                if($null -ne $hit){$results.Add((& $toResult $targetEntry.Name $mutant $hit.Status $hit.Seconds $true));$reused++;continue}
                $queue.Enqueue([pscustomobject]@{Mutant=$mutant;Text=$source.Text;Retries=0})
            }
            if($queue.Count -eq 0){
                Write-Host ("Progress: Cached $($targetEntry.Name) | mutants=$($mutants.Count) reused=$reused equivalent=$($split.Equivalent.Count)")
                $finished++
                continue
            }
            # A baseline already proven on this machine for the same engine, sources and tests is not run again.
            $known=if($baselineKey){Read-QuietScriptMutationBaseline -Directory $cache -Key $baselineKey}else{$null}
            if($null -ne $known){
                $timeout=Get-QuietScriptMutantTimeout $known.Seconds
                $proven=@($known.Focus|Where-Object {$focus.Contains($_)})
                Write-Host ("Progress: Baseline $($targetEntry.Name) reused | passed=$($known.Passed) seconds=$($known.Seconds) mutant timeout=${timeout}s focused=$($proven.Count)")
            }else{
                $status.Case=('Baseline {0} ({1} mutants, {2} cached)' -f $targetEntry.Name,$mutants.Count,$reused);Write-WorkspaceJson $statusPath $status
                Write-Host ("Progress: Baseline $($targetEntry.Name) | mutants=$($mutants.Count) cached=$reused")
                $baseline=& $runJob 0 'baseline' $files 1800
                if($baseline.State -cne 'Success' -or $baseline.Failed -ne 0 -or $baseline.Passed -eq 0){throw ("ScriptMutationBaselineFailed: {0} state={1} passed={2} failed={3}; {4}" -f $targetEntry.Name,$baseline.State,$baseline.Passed,$baseline.Failed,$baseline.Error)}
                $reuse=& $runJob 0 'baseline-reuse' $files 1800
                if($reuse.State -cne 'Success' -or $reuse.Failed -ne 0 -or $reuse.Passed -ne $baseline.Passed){throw ("ScriptMutationSlotStateLeak: {0} first={1} second={2} state={3}; {4}" -f $targetEntry.Name,$baseline.Passed,$reuse.Passed,$reuse.State,$reuse.Error)}
                $seconds=[Math]::Max($baseline.Seconds,$reuse.Seconds)
                $timeout=Get-QuietScriptMutantTimeout $seconds
                # A split is used only once it runs every baseline test and passes: a block that needs another to run
                # first would otherwise fail and falsely kill the mutants of that function.
                $checks=@($focus.Keys|ForEach-Object {[pscustomobject]@{Name=$_;Phases=@($focus[$_].Focus,$focus[$_].Rest)}})
                $outcomes=if($checks.Count){& $runAll $checks $files $timeout}else{@{}}
                $proven=[Collections.Generic.List[string]]::new()
                foreach($check in $checks){
                    $outcome=$outcomes[$check.Name]
                    if($outcome.State -ceq 'Success' -and $outcome.Failed -eq 0 -and $outcome.Passed -eq $baseline.Passed){$proven.Add($check.Name);continue}
                    Write-Host ("Progress: Focus dropped $($targetEntry.Name) | $($check.Name) state=$($outcome.State) passed=$($outcome.Passed) failed=$($outcome.Failed) expected=$($baseline.Passed)")
                }
                if($baselineKey){$null=Write-QuietScriptMutationBaseline -Directory $cache -Key $baselineKey -Passed $baseline.Passed -Seconds $seconds -Focus $proven.ToArray()}
                Write-Host ("Progress: Baseline $($targetEntry.Name) passed | passed=$($baseline.Passed) seconds=$($baseline.Seconds) reuse=$($reuse.Seconds) mutant timeout=${timeout}s focused=$($proven.Count)/$($focus.Count)")
            }
            $active=@{};$done=0;$total=$queue.Count;$tally=@{Killed=0;Survived=0;Timeout=0}
            while($queue.Count -or $active.Count){
                for($slot=0;$slot -lt $count -and $queue.Count;$slot++){
                    if($active.ContainsKey($slot)){continue}
                    if($null -eq $slots[$slot] -or !$slots[$slot].Alive -or $slots[$slot].Jobs -ge [int]$request.RecycleAfter){& $retireSlot $slot;& $startSlot $slot}
                    $item=$queue.Dequeue()
                    [IO.File]::WriteAllText([IO.Path]::Combine($roots[$slot],$relative),$item.Text,[Text.UTF8Encoding]::new($false))
                    $phases=if($proven -ccontains $item.Mutant.Function){@($focus[$item.Mutant.Function].Focus,$focus[$item.Mutant.Function].Rest)}else{@()}
                    Submit-QuietScriptsMutationJob -Slot $slots[$slot] -Name $item.Mutant.Id -UnitTestFiles $files -Bail -Phases $phases -TimeoutSeconds $timeout
                    $active[$slot]=$item
                }
                foreach($slot in @($active.Keys)){
                    $outcome=Receive-QuietScriptsMutationJob -Slot $slots[$slot]
                    if($null -eq $outcome){continue}
                    $item=$active[$slot];$active.Remove($slot)
                    [IO.File]::WriteAllBytes([IO.Path]::Combine($roots[$slot],$relative),$original)
                    # A crashed worker may hold broken state; a corrupted one was damaged by an earlier run, so its
                    # job is replayed on a fresh worker rather than counted against this mutant.
                    if($outcome.State -cin @('Crash','Corrupted')){$slots[$slot].Alive=$false}
                    if($outcome.State -ceq 'Corrupted'){
                        if($item.Retries -ge 1){throw "ScriptMutationSlotCorrupted: $($targetEntry.Name) $($item.Mutant.Id); $($outcome.Error)"}
                        $item.Retries++;$queue.Enqueue($item)
                        Write-Host ("Progress: Replay $($targetEntry.Name) | $($item.Mutant.Id) on a fresh slot ($($outcome.Error))")
                        continue
                    }
                    $mutantStatus=Get-QuietScriptMutantStatus -State $outcome.State -Failed $outcome.Failed -TimedOut:$outcome.TimedOut
                    if($cache){$null=Write-QuietScriptMutantCache -Directory $cache -Key $keys[[string]$item.Mutant.Id] -Status $mutantStatus -Seconds $outcome.Seconds -Seed ([int]$request.Seed)}
                    $result=& $toResult $targetEntry.Name $item.Mutant $mutantStatus $outcome.Seconds $false
                    $results.Add($result)
                    $done++;$tally[$mutantStatus]++
                    $status.Passed=[int]$status.Passed+$(if($mutantStatus -ceq 'Survived'){0}else{1});$status.Failed=[int]$status.Failed+$(if($mutantStatus -ceq 'Survived'){1}else{0})
                    $status.Case=('{0} {1}/{2} killed={3} timeout={4} survived={5} cached={6}' -f $targetEntry.Name,$done,$total,$tally.Killed,$tally.Timeout,$tally.Survived,$reused)
                    Write-WorkspaceJson $statusPath $status
                    Write-Host ("Progress: Mutate $($targetEntry.Name) | $done/$total $mutantStatus $($result.Mutator) L$($result.Line) killed=$($tally.Killed) timeout=$($tally.Timeout) survived=$($tally.Survived) cached=$reused")
                }
                if($active.Count){[void][Threading.Tasks.Task]::Delay(20).GetAwaiter().GetResult()}
            }
            $finished++
        }
        $current=''
        $report=& $writeReports $null
        # Only a campaign that keyed every selected target prunes: an aborted one would drop outcomes it never reached.
        if($cache -and $request.PruneCache){Write-Host ('Cache: pruned '+(Remove-QuietScriptMutantCacheUnused -Directory $cache -Keys @($usedKeys))+' unused documents, kept '+$usedKeys.Count+' keys')}
        $status.State=$(if($report.Passed){'Success'}else{'Failed'})
        $status.Case=((@($report.Targets)|ForEach-Object {'{0} {1:0.##} % (break {2}, cached {3})' -f $_.Name,[double]$_.Score,$_.Break,$_.Cached}) -join '; ')
    }catch{
        $message=$_.Exception.Message
        Write-Host ('Worker error: '+$message)
        $status.State='Crash';$status.Failed=[int]$status.Failed+1;$status.Error=$message
        $status.Case=('Mutation campaign stopped{0}; {1} of {2} targets finished' -f $(if($current){' in '+$current}),$finished,@($request.Targets).Count)
        # The finished targets keep their report; a complete report already written (a prune failure) is kept as is.
        if($null -eq $report){
            $notRun=[string[]]@($request.Targets|Select-Object -Skip ($finished+[int][bool]$current)|ForEach-Object {[string]$_.Name})
            try{$null=& $writeReports ([pscustomobject]@{Target=$current;Error=$message;NotRun=$notRun})}catch{Write-Host ('Partial report failed: '+$_.Exception.Message)}
        }
    }finally{
        for($index=0;$index -lt $count;$index++){try{& $retireSlot $index}catch{Write-Host ('Slot stop failed: '+$_.Exception.Message)}}
        if([IO.Directory]::Exists($slotsRoot)){try{[IO.Directory]::Delete($slotsRoot,$true)}catch{Write-Host ('Slot cleanup failed: '+$_.Exception.Message)}}
    }
    $status.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson $statusPath $status
    Write-WorkspaceJson $summaryPath @{State=$status}
}

Export-ModuleMember -Function Invoke-QuietScriptInvokeScriptsMutation,Copy-QuietScriptsMutationTree,Invoke-QuietScriptsMutationWorker
