#requires -Version 7.6
function Get-QuietTestExecutionPolicy {
    <#
    .SYNOPSIS
    Validates inert manifest scheduling declarations with ordered execution as the only default.
    .PARAMETER ManifestPath
    Test companion manifest; no module code is imported.
    .PARAMETER CaseNames
    Complete reviewed case catalogue used to reject orphan overrides.
    #>
    param([Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string[]]$CaseNames)
    $null=[IO.File]::ReadAllText($ManifestPath,[Text.UTF8Encoding]::new($false,$true))
    $manifest=Import-PowerShellDataFile -LiteralPath $ManifestPath -ErrorAction Stop
    $declared=$false;$policy=$null
    if($manifest.ContainsKey('PrivateData')){
        $private=$manifest['PrivateData']
        if($private -isnot [hashtable]){throw 'TestExecutionPolicyPrivateDataInvalid'}
        if($private.ContainsKey('QuietCli')){
            if($private.QuietCli -isnot [hashtable]){throw 'TestExecutionPolicyPrivateDataInvalid'}
            $declared=$private.QuietCli.ContainsKey('TestExecution')
            if($declared){$policy=$private.QuietCli.TestExecution}
        }
    }
    if(!$declared){return @{SchemaVersion=1;DefaultMode='Ordered';DefaultReason='No scheduling declaration: preserve case order.';MaxParallelCases=1;Cases=@{}}}
    if($policy -isnot [hashtable] -or $policy.Count -ne 5){throw 'TestExecutionPolicyInvalid'}
    foreach($key in $policy.Keys){if($key -cnotin @('SchemaVersion','DefaultMode','DefaultReason','MaxParallelCases','Cases')){throw 'TestExecutionPolicyFieldInvalid'}}
    if($policy.SchemaVersion -isnot [int] -or $policy.SchemaVersion -ne 1 -or $policy.DefaultMode -cne 'Ordered' -or $policy.DefaultReason -isnot [string] -or $policy.DefaultReason.Trim().Length -lt 10 -or $policy.MaxParallelCases -isnot [int] -or $policy.MaxParallelCases -lt 1 -or $policy.MaxParallelCases -gt 32 -or $policy.Cases -isnot [hashtable]){throw 'TestExecutionPolicyInvalid'}
    foreach($name in $policy.Cases.Keys){
        if($name -cnotin $CaseNames){throw ('TestExecutionPolicyOrphan: '+$name)}
        $entry=$policy.Cases[$name]
        if($entry -isnot [hashtable] -or !$entry.ContainsKey('Mode') -or !$entry.ContainsKey('Reason') -or $entry.Mode -cnotin @('Ordered','Exclusive','IsolatedProcess') -or $entry.Reason -isnot [string] -or $entry.Reason.Trim().Length -lt 10){throw ('TestExecutionPolicyCaseInvalid: '+$name)}
        foreach($key in $entry.Keys){if($key -cnotin @('Mode','Reason','TimeoutSeconds')){throw ('TestExecutionPolicyCaseFieldInvalid: '+$name)}}
        if($entry.ContainsKey('TimeoutSeconds') -and ($entry.TimeoutSeconds -isnot [int] -or $entry.TimeoutSeconds -lt 1 -or $entry.TimeoutSeconds -gt 7200)){throw ('TestExecutionPolicyTimeoutInvalid: '+$name)}
    }
    $policy
}

function Get-QuietTestExecutionPlan {
    <#
    .SYNOPSIS
    Groups only adjacent opted-in cases and preserves every ordered or exclusive barrier.
    .PARAMETER CaseNames
    Selected case names in their original execution order.
    .PARAMETER Policy
    Policy already validated against the full catalogue.
    .PARAMETER MaxConcurrency
    Shared test-worker budget; isolated cases each receive one internal worker.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$CaseNames,[Parameter(Mandatory)][hashtable]$Policy,[ValidateRange(1,32)][int]$MaxConcurrency=1)
    $limit=[Math]::Min($MaxConcurrency,$Policy.MaxParallelCases)
    $stages=[Collections.Generic.List[object]]::new();$index=0
    foreach($name in $CaseNames){
        $entry=if($Policy.Cases.ContainsKey($name)){$Policy.Cases[$name]}else{@{Mode=$Policy.DefaultMode;Reason=$Policy.DefaultReason}}
        $case=[pscustomobject]@{Name=$name;Index=$index;Mode=$entry.Mode;Reason=$entry.Reason;TimeoutSeconds=if($entry.ContainsKey('TimeoutSeconds')){$entry.TimeoutSeconds}else{300}}
        if($entry.Mode -ceq 'IsolatedProcess' -and $stages.Count -and $stages[$stages.Count-1].Mode -ceq 'IsolatedProcess'){
            $stages[$stages.Count-1].Cases.Add($case)
        }else{
            $list=[Collections.Generic.List[object]]::new();$list.Add($case)
            $stages.Add([pscustomobject]@{Mode=$entry.Mode;Cases=$list})
        }
        $index++
    }
    [pscustomobject]@{SchemaVersion=1;MaxConcurrency=$limit;InternalConcurrency=1;Cases=$CaseNames.Count;Stages=$stages.ToArray()}
}

function Invoke-QuietTestCaseWorkers {
    <#
    .SYNOPSIS
    Executes an opted-in batch with bounded isolated processes and validated terminal case receipts.
    .PARAMETER WorkspaceRoot
    Stable built checkout, read-only for eligible cases.
    .PARAMETER RunDirectory
    Parent evidence directory; each admission creates an exclusive child directory.
    .PARAMETER Cases
    Ordered planned cases, all explicitly marked IsolatedProcess.
    .PARAMETER MaxConcurrency
    Maximum simultaneous case workers; each child receives MaxConcurrency one.
    .PARAMETER StopOnFirstFailure
    Stops admission after an observed failure and drains already admitted cases.
    .PARAMETER SkipTty
    Forwards the selected terminal exclusion scope.
    .PARAMETER ExpectedRuntimeIdentifier
    Preserves the parent's required native architecture.
    .PARAMETER OnCase
    Parent-only callback receiving a name, Running or terminal state, and an optional result.
    .PARAMETER CancellationToken
    Cancels admission and terminates all owned process trees through finally.
    .PARAMETER WorkerPath
    Default shared test worker or an owned protocol fixture for scheduler assertions.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory,[Parameter(Mandatory)][object[]]$Cases,
        [ValidateRange(1,32)][int]$MaxConcurrency=2,[switch]$StopOnFirstFailure,[switch]$SkipTty,[string]$ExpectedRuntimeIdentifier,
        [scriptblock]$OnCase,[Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None,
        [string]$WorkerPath=(Join-Path $PSScriptRoot '../Invoke-TestWorker.ps1'))
    if(!$PSCmdlet.ShouldProcess($RunDirectory,'Run explicitly isolated test cases with bounded child workers')){return}
    . (Join-Path $PSScriptRoot '../Ci.Process.ps1')
    $pending=[Collections.Generic.Queue[object]]::new();$names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($case in $Cases){
        if($case.Mode -cne 'IsolatedProcess' -or !$names.Add($case.Name) -or $case.TimeoutSeconds -lt 1 -or $case.TimeoutSeconds -gt 7200 -or $case.Index -lt 0){throw 'TestCaseWorkerSelectionInvalid'}
        $pending.Enqueue($case)
    }
    $active=[Collections.Generic.List[object]]::new();$completed=@{};$stop=$false;$peak=0
    $runner=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
    try{
        while($pending.Count -or $active.Count){
            $CancellationToken.ThrowIfCancellationRequested()
            # Reap before admitting replacements so an observed failure closes admission immediately.
            foreach($worker in @($active.ToArray())){
                $errorText=$null;$caseResult=$null
                if(!$worker.Process.HasExited -and $worker.Clock.Elapsed.TotalSeconds -le $worker.Case.TimeoutSeconds){continue}
                if(!$worker.Process.HasExited){
                    $worker.Process.Kill($true);$worker.Process.WaitForExit();$errorText='TestCaseWorkerTimeout'
                }else{
                    try{
                        $path=Join-Path $worker.Directory 'summary.json'
                        if(!(Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -gt 4194304){throw 'TestCaseWorkerSummaryMissingOrOversized'}
                        $report=Get-Content -LiteralPath $path -Raw -Encoding utf8|ConvertFrom-Json
                        if(@($report.Suites).Count -ne 1){throw 'TestCaseWorkerSuiteCountInvalid'}
                        $suite=$report.Suites[0]
                        if(@($suite.Cases).Count -ne 1 -or $suite.Cases[0].Name -cne $worker.Case.Name -or !$suite.Partial -or $suite.Incomplete){throw 'TestCaseWorkerSelectionMismatch'}
                        $caseResult=$suite.Cases[0]
                        $success=$caseResult.State -ceq 'Passed'
                        if($caseResult.State -cnotin @('Passed','Failed') -or $suite.Passed -ne [int]$success -or $suite.Failed -ne [int](!$success) -or $report.State.Passed -ne $suite.Passed -or $report.State.Failed -ne $suite.Failed -or $report.State.State -cne $(if($success){'Success'}else{'Failed'}) -or $worker.Process.ExitCode -ne $(if($success){0}else{1})){throw 'TestCaseWorkerOutcomeMismatch'}
                        if($report.State.ProcessId -ne $worker.Process.Id -or ($ExpectedRuntimeIdentifier -and $report.State.Platform -cne $ExpectedRuntimeIdentifier)){throw 'TestCaseWorkerIdentityMismatch'}
                    }catch{$errorText='TestCaseWorkerInfrastructure: '+$_.Exception.Message}
                }
                $result=[pscustomobject]@{Name=$worker.Case.Name;State=if($errorText){'Failed'}else{$caseResult.State};Error=if($errorText){$errorText}else{$caseResult.Error};ExecutionMode='IsolatedProcess';WorkerProcessId=$worker.Process.Id;RunDirectory=$worker.Directory;InternalConcurrency=1;StartedUtc=$worker.StartedUtc;FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')}
                $completed[$worker.Case.Name]=$result
                $receiptPath=Join-Path $worker.Directory 'case-result.json'
                [IO.File]::WriteAllText(($receiptPath+'.tmp'),(($result|ConvertTo-Json -Depth 6)+"`n"),[Text.UTF8Encoding]::new($false))
                [IO.File]::Move(($receiptPath+'.tmp'),$receiptPath)
                if($OnCase){$null=& $OnCase $result.Name $result.State $result}
                if($StopOnFirstFailure -and $result.State -ceq 'Failed'){$stop=$true}
                $worker.Process.Dispose();[void]$active.Remove($worker)
            }
            while(!$stop -and $pending.Count -and $active.Count -lt $MaxConcurrency){
                $CancellationToken.ThrowIfCancellationRequested()
                $case=$pending.Dequeue()
                $digest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($case.Name))).Substring(0,12).ToLowerInvariant()
                $directory=Join-Path $RunDirectory ('core-cases/{0:D4}-{1}' -f $case.Index,$digest)
                if(Test-Path -LiteralPath $directory){throw 'TestCaseWorkerDirectoryExists'}
                [void][IO.Directory]::CreateDirectory($directory)
                $arguments=@('-File',$WorkerPath,'-WorkspaceRoot',$WorkspaceRoot,'-RunDirectory',$directory,'-Suite','Core','-Case',([Management.Automation.WildcardPattern]::Escape($case.Name)),'-CaseWorker','-MaxConcurrency','1')
                if($SkipTty){$arguments+='-SkipTty'}
                if($ExpectedRuntimeIdentifier){$arguments+=@('-ExpectedRuntimeIdentifier',$ExpectedRuntimeIdentifier)}
                $process=Start-CiProcess -FilePath $runner -ArgumentList $arguments -WorkingDirectory $WorkspaceRoot -Confirm:$false
                $active.Add([pscustomobject]@{Case=$case;Directory=$directory;Process=$process;Clock=[Diagnostics.Stopwatch]::StartNew();StartedUtc=[DateTimeOffset]::UtcNow.ToString('o')})
                $peak=[Math]::Max($peak,$active.Count)
                if($OnCase){$null=& $OnCase $case.Name 'Running' ([pscustomobject]@{WorkerProcessId=$process.Id;RunDirectory=$directory;InternalConcurrency=1})}
            }
            if($stop -and !$active.Count){break}
            if($active.Count){[void][Threading.Tasks.Task]::Delay(50).GetAwaiter().GetResult()}
        }
        [pscustomobject]@{Cases=@(foreach($case in $Cases){if($completed.ContainsKey($case.Name)){$completed[$case.Name]}});NotStarted=@($pending.ToArray()|ForEach-Object Name);MaxActive=$peak;MaxConcurrency=$MaxConcurrency;InternalConcurrency=1}
    }finally{
        foreach($worker in $active){try{if(!$worker.Process.HasExited){$worker.Process.Kill($true);$worker.Process.WaitForExit()}}finally{$worker.Process.Dispose()}}
    }
}
Export-ModuleMember -Function Get-QuietTestExecutionPolicy,Get-QuietTestExecutionPlan,Invoke-QuietTestCaseWorkers
