#Objective: Persistent mutation slot workers: one reused pwsh per slot, file job protocol, watchdog, state reset between runs.
#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ScriptsTests.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceJson.psm1')) -DisableNameChecking -ErrorAction Stop

function Get-QuietScriptsMutationSlotState {
    <#
    .SYNOPSIS
    Captures the process state a test run may change: environment variables, global variable names and location.
    #>
    [CmdletBinding()]
    param()
    $environment=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()){$environment[[string]$entry.Key]=[string]$entry.Value}
    $globals=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($variable in Get-Variable -Scope Global){[void]$globals.Add($variable.Name)}
    [pscustomobject]@{Environment=$environment;Globals=$globals;Location=(Get-Location).ProviderPath}
}

function Restore-QuietScriptsMutationSlotState {
    <#
    .SYNOPSIS
    Puts the process back in a captured state and unloads every module imported from the code under test.
    .DESCRIPTION
    Environment variables added by a run are removed and changed ones restored. Global variables created by a run are
    removed, unless constant or read-only. Modules whose path lies under one of the roots are removed, so the next run
    re-imports the slot sources, including nested imports that a plain Import-Module would otherwise reuse.
    Returns the number of modules removed.
    .PARAMETER State
    Result of Get-QuietScriptsMutationSlotState.
    .PARAMETER Roots
    Directories whose modules must be reloaded (slot scripts root and tests root).
    #>
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][string[]]$Roots)
    $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    foreach($entry in @([Environment]::GetEnvironmentVariables().GetEnumerator())){
        # [NullString]::Value deletes the variable: a $null argument reaches .NET as '' and leaves it set to the empty string.
        if(!$State.Environment.ContainsKey([string]$entry.Key)){[Environment]::SetEnvironmentVariable([string]$entry.Key,[NullString]::Value)}
    }
    foreach($pair in $State.Environment.GetEnumerator()){
        if([Environment]::GetEnvironmentVariable($pair.Key) -cne $pair.Value){[Environment]::SetEnvironmentVariable($pair.Key,$pair.Value)}
    }
    foreach($variable in @(Get-Variable -Scope Global)){
        if($State.Globals.Contains($variable.Name)){continue}
        if($variable.Options -band ([Management.Automation.ScopedItemOptions]::Constant -bor [Management.Automation.ScopedItemOptions]::ReadOnly)){continue}
        Remove-Variable -Name $variable.Name -Scope Global -Force -ErrorAction SilentlyContinue
    }
    Set-Location -LiteralPath $State.Location
    [Environment]::CurrentDirectory=$State.Location
    $prefixes=@($Roots|ForEach-Object {[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($_))+[IO.Path]::DirectorySeparatorChar})
    $stale=@(Get-Module -All|Where-Object {$path=$_.Path;$path -and @($prefixes|Where-Object {$path.StartsWith($_,$comparison)}).Count})
    foreach($module in $stale){Remove-Module -ModuleInfo $module -Force -ErrorAction SilentlyContinue}
    $stale.Count
}

function Start-QuietScriptsMutationSlot {
    <#
    .SYNOPSIS
    Starts one persistent slot worker in a hidden pwsh and returns its handle.
    .PARAMETER Index
    Slot number.
    .PARAMETER Directory
    New control directory for this worker generation (requests, jobs, results, logs).
    .PARAMETER ScriptsRoot
    Slot scripts copy, exported as QUIETCLI_SCRIPTS_ROOT.
    .PARAMETER TestsRoot
    Tests root.
    .PARAMETER WorkspaceRoot
    Repository root, exported as QUIETCLI_WORKSPACE_ROOT.
    .PARAMETER PesterModulePath
    Pinned Pester manifest.
    .PARAMETER Seed
    Test seed exported as QUIETCLI_TEST_SEED.
    #>
    param([Parameter(Mandatory)][int]$Index,[Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$ScriptsRoot,[Parameter(Mandatory)][string]$TestsRoot,[Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$PesterModulePath,[int]$Seed)
    if([IO.Directory]::Exists($Directory)){throw 'ScriptMutationSlotDirectoryExists'}
    [void][IO.Directory]::CreateDirectory($Directory)
    $parent=[Diagnostics.Process]::GetCurrentProcess()
    $requestPath=[IO.Path]::Combine($Directory,'slot.json')
    Write-WorkspaceJson $requestPath ([ordered]@{
        Index=$Index;Directory=$Directory;ScriptsRoot=$ScriptsRoot;TestsRoot=$TestsRoot;WorkspaceRoot=$WorkspaceRoot;PesterModulePath=$PesterModulePath;Seed=$Seed
        ParentProcessId=$parent.Id;ParentStartTicks=$parent.StartTime.ToUniversalTime().Ticks
    })
    $runner=[IO.Path]::Combine($PSHOME,$(if($IsWindows){'pwsh.exe'}else{'pwsh'}))
    $command='[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); $OutputEncoding=[Console]::OutputEncoding; $ErrorActionPreference=''Stop''; Import-Module '''+$PSCommandPath.Replace("'","''")+''' -DisableNameChecking -ErrorAction Stop; Invoke-QuietScriptsMutationSlotWorker -RequestPath '''+$requestPath.Replace("'","''")+''''
    $options=@{FilePath=$runner;ArgumentList=@('-NoProfile','-NonInteractive','-OutputFormat','Text','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)));PassThru=$true;RedirectStandardOutput=[IO.Path]::Combine($Directory,'worker.stdout.log');RedirectStandardError=[IO.Path]::Combine($Directory,'worker.stderr.log')}
    if($IsWindows){$options.WindowStyle='Hidden'}
    $process=Start-Process @options
    [pscustomobject]@{Index=$Index;Directory=$Directory;ScriptsRoot=$ScriptsRoot;Process=$process;Sequence=0;Jobs=0;Job=$null;Alive=$true}
}

function Submit-QuietScriptsMutationJob {
    <#
    .SYNOPSIS
    Hands one test run to an idle slot: writes job-<n>.json and records its deadline on the handle.
    .PARAMETER Slot
    Live, idle handle from Start-QuietScriptsMutationSlot.
    .PARAMETER Name
    Run name (baseline or mutant id), for diagnosis.
    .PARAMETER UnitTestFiles
    Test files relative to the tests root.
    .PARAMETER Bail
    Stops the run at its first failed test (Pester Run.SkipRemainingOnFailure = Run).
    .PARAMETER TimeoutSeconds
    Deadline after which the watchdog kills the worker.
    #>
    param([Parameter(Mandatory)]$Slot,[Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string[]]$UnitTestFiles,[switch]$Bail,[Parameter(Mandatory)][ValidateRange(1,86400)][int]$TimeoutSeconds)
    if(!$Slot.Alive){throw 'ScriptMutationSlotDead'}
    if($null -ne $Slot.Job){throw 'ScriptMutationSlotBusy'}
    $Slot.Sequence=[int]$Slot.Sequence+1
    $now=[DateTimeOffset]::UtcNow
    Write-WorkspaceJson ([IO.Path]::Combine($Slot.Directory,'job-'+$Slot.Sequence+'.json')) ([ordered]@{Sequence=$Slot.Sequence;Name=$Name;UnitTestFiles=[string[]]$UnitTestFiles;Bail=[bool]$Bail})
    $Slot.Job=[pscustomobject]@{Sequence=$Slot.Sequence;Name=$Name;Started=$now;Deadline=$now.AddSeconds($TimeoutSeconds)}
}

function Receive-QuietScriptsMutationJob {
    <#
    .SYNOPSIS
    Returns the outcome {State, Passed, Failed, Seconds, TimedOut, Error} of a slot's current job, or $null while it runs.
    .DESCRIPTION
    A saved result wins over everything else. A worker that exited without a result, or saved an unreadable or
    mismatched result, yields Crash; a job past its deadline gets its worker tree killed and yields Timeout with
    TimedOut. In these cases the slot is marked dead and must be restarted. A received job frees the slot.
    .PARAMETER Slot
    Handle with a submitted job.
    .PARAMETER Now
    Clock used for the deadline (tests).
    #>
    param([Parameter(Mandatory)]$Slot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    $job=$Slot.Job
    if($null -eq $job){throw 'ScriptMutationSlotIdle'}
    $resultPath=[IO.Path]::Combine($Slot.Directory,'result-'+$job.Sequence+'.json')
    $seconds=[Math]::Round(($Now-$job.Started).TotalSeconds,1)
    $outcome=$null
    if([IO.File]::Exists($resultPath)){
        # Strict UTF-8: an invalid byte makes the result invalid instead of decoding to U+FFFD.
        $strict=[Text.Encoding]::GetEncoding('utf-8',[Text.EncoderFallback]::ExceptionFallback,[Text.DecoderFallback]::ExceptionFallback)
        $saved=try{[IO.File]::ReadAllText($resultPath,$strict)|ConvertFrom-Json -ErrorAction Stop}catch{$null}
        if($null -ne $saved -and [string]$saved.Sequence -ceq [string]$job.Sequence){
            $outcome=[pscustomobject][ordered]@{State=[string]$saved.State;Passed=[int]$saved.Passed;Failed=[int]$saved.Failed;Seconds=[double]$saved.Seconds;TimedOut=$false;Error=[string]$saved.Error}
        }else{
            # The worker and the parent no longer agree on the sequence: restart rather than trust it.
            $outcome=[pscustomobject][ordered]@{State='Crash';Passed=0;Failed=0;Seconds=$seconds;TimedOut=$false;Error='ScriptMutationSlotResultInvalid'}
            $Slot.Alive=$false
        }
    }elseif($Slot.Process.HasExited){
        $outcome=[pscustomobject][ordered]@{State='Crash';Passed=0;Failed=0;Seconds=$seconds;TimedOut=$false;Error=('ScriptMutationSlotExited: '+$Slot.Process.ExitCode)}
        $Slot.Alive=$false
    }elseif($Now -ge $job.Deadline){
        try{$Slot.Process.Kill($true)}catch{Write-Verbose ('Slot worker already stopped: '+$_.Exception.Message)}
        $null=$Slot.Process.WaitForExit(30000)
        $outcome=[pscustomobject][ordered]@{State='Timeout';Passed=0;Failed=0;Seconds=$seconds;TimedOut=$true;Error='ScriptMutationSlotTimeout'}
        $Slot.Alive=$false
    }else{return}
    foreach($path in @([IO.Path]::Combine($Slot.Directory,'job-'+$job.Sequence+'.json'),$resultPath)){if([IO.File]::Exists($path)){[IO.File]::Delete($path)}}
    $Slot.Job=$null;$Slot.Jobs=[int]$Slot.Jobs+1
    $outcome
}

function Wait-QuietScriptsMutationJob {
    <#
    .SYNOPSIS
    Blocks until the slot's current job has an outcome and returns it.
    .PARAMETER Slot
    Handle with a submitted job.
    .PARAMETER PollMilliseconds
    Delay between checks.
    #>
    param([Parameter(Mandatory)]$Slot,[ValidateRange(1,5000)][int]$PollMilliseconds=25)
    while($true){
        $outcome=Receive-QuietScriptsMutationJob -Slot $Slot
        if($null -ne $outcome){return $outcome}
        [void][Threading.Tasks.Task]::Delay($PollMilliseconds).GetAwaiter().GetResult()
    }
}

function Stop-QuietScriptsMutationSlot {
    <#
    .SYNOPSIS
    Asks a slot worker to exit, kills it after a grace period, and marks the handle dead.
    .PARAMETER Slot
    Handle from Start-QuietScriptsMutationSlot.
    .PARAMETER GraceMilliseconds
    Time allowed for a clean exit.
    #>
    param([Parameter(Mandatory)]$Slot,[ValidateRange(0,60000)][int]$GraceMilliseconds=5000)
    if(!$Slot.Process.HasExited){
        if([IO.Directory]::Exists($Slot.Directory)){[IO.File]::WriteAllText([IO.Path]::Combine($Slot.Directory,'stop'),'')}
        if(!$Slot.Process.WaitForExit($GraceMilliseconds)){
            try{$Slot.Process.Kill($true)}catch{Write-Verbose ('Slot worker already stopped: '+$_.Exception.Message)}
            $null=$Slot.Process.WaitForExit(30000)
        }
    }
    $Slot.Alive=$false
    $Slot.Process.Dispose()
}

function Test-QuietScriptsMutationSlotPester {
    <#
    .SYNOPSIS
    True when exactly one Pester module is loaded and it is the pinned 6.2.0.
    .PARAMETER Modules
    Loaded Pester modules, as returned by Get-Module Pester.
    #>
    param([AllowEmptyCollection()][object[]]$Modules=@())
    $Modules.Count -eq 1 -and $Modules[0].Version -eq [version]'6.2.0'
}

function Test-QuietScriptsMutationSlotParent {
    <#
    .SYNOPSIS
    True while the recorded parent still runs: the process exists, has not exited, and started within one second of the recorded start.
    .DESCRIPTION
    On Linux, .NET derives a process start time from the boot time, which another process computes again with a few
    milliseconds of drift, so an exact comparison would make every worker exit after its first job. The tolerance
    still tells a reused process id apart, because its new owner started after the parent exited.
    .PARAMETER Process
    Process found under the recorded id, or $null when none was found.
    .PARAMETER StartTicks
    Recorded parent start time, in UTC ticks.
    #>
    param([AllowNull()]$Process,[Parameter(Mandatory)][long]$StartTicks)
    if($null -eq $Process -or $Process.HasExited){return $false}
    [Math]::Abs($Process.StartTime.ToUniversalTime().Ticks-$StartTicks) -le [TimeSpan]::TicksPerSecond
}

function Invoke-QuietScriptsMutationSlotJob {
    <#
    .SYNOPSIS
    Runs one job in the current process: resets the state, runs Pester on the job's files and returns the saved result.
    .DESCRIPTION
    State is Corrupted, without running anything, when the worker no longer holds exactly the pinned Pester: the
    caller restarts the slot and runs the job again instead of blaming its mutant.
    .PARAMETER Request
    Slot request (slot.json).
    .PARAMETER Job
    Job document.
    .PARAMETER State
    Captured state to restore before the run.
    .PARAMETER Scope
    Empty dynamic module Pester is called from, so test files resolve libraries globally.
    .PARAMETER PesterModules
    Pester modules loaded after the state reset; read from the session when omitted. Tests pass it instead of mocking
    Get-Module, because a slot worker already holds a trusted ScriptMutationSlot module of the same name, which makes
    Mock -ModuleName ScriptMutationSlot ambiguous when this library is itself under mutation.
    #>
    param([Parameter(Mandatory)][Collections.IDictionary]$Request,[Parameter(Mandatory)][Collections.IDictionary]$Job,[Parameter(Mandatory)]$State,[Parameter(Mandatory)][psmoduleinfo]$Scope,[AllowEmptyCollection()][object[]]$PesterModules)
    $started=[Diagnostics.Stopwatch]::StartNew()
    try{
        $null=Restore-QuietScriptsMutationSlotState -State $State -Roots @($Request.ScriptsRoot,$Request.TestsRoot)
        # A previous run that unloaded or replaced Pester must not fail, and so falsely kill, this one.
        if(!$PSBoundParameters.ContainsKey('PesterModules')){$PesterModules=@(Get-Module Pester)}
        if(!(Test-QuietScriptsMutationSlotPester -Modules $PesterModules)){
            return [ordered]@{Sequence=$Job.Sequence;State='Corrupted';Passed=0;Failed=0;Seconds=0.0;Error='ScriptMutationSlotCorrupted: Pester'}
        }
        $env:QUIETCLI_TEST_SEED=[string]$Request.Seed
        $env:QUIETCLI_SCRIPTS_ROOT=$Request.ScriptsRoot
        $env:QUIETCLI_WORKSPACE_ROOT=$Request.WorkspaceRoot
        $plan=Get-QuietScriptsTestPlan -TestsRoot $Request.TestsRoot -Kind Unit -Path ([string[]]@($Job.UnitTestFiles))
        $settings=New-QuietScriptsPesterConfiguration -Plan $plan -RunDirectory $Request.Directory
        $settings.TestResult.Enabled=$false
        $settings.Output.Verbosity='None'
        if($Job.Bail){$settings.Run.SkipRemainingOnFailure='Run'}
        $configuration=New-PesterConfiguration -Hashtable $settings
        $result=& $Scope { param($InvokePester,$Configuration) & $InvokePester -Configuration $Configuration } (Get-Command Invoke-Pester) $configuration
        $report=ConvertTo-QuietScriptsTestReport -Result $result -Plan $plan -Seed ([int]$Request.Seed)
        [ordered]@{Sequence=$Job.Sequence;State=[string]$report.State;Passed=[int]$report.Passed;Failed=[int]$report.Failed;Seconds=[Math]::Round($started.Elapsed.TotalSeconds,1);Error=$null}
    }catch{
        [ordered]@{Sequence=$Job.Sequence;State='Crash';Passed=0;Failed=1;Seconds=[Math]::Round($started.Elapsed.TotalSeconds,1);Error=$_.Exception.Message}
    }
}

function Invoke-QuietScriptsMutationSlotWorker {
    <#
    .SYNOPSIS
    Worker body: imports the pinned Pester once, then runs job-<n>.json files in order until stop, or until its parent exits.
    .PARAMETER RequestPath
    slot.json written by Start-QuietScriptsMutationSlot.
    #>
    param([Parameter(Mandatory)][string]$RequestPath)
    $ErrorActionPreference='Stop'
    $PSStyle.OutputRendering='PlainText'
    $request=Get-Content -LiteralPath $RequestPath -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable
    # Global, as in the Invoke-ScriptsTests worker: test files must resolve Describe/It to the pinned Pester.
    Import-Module $request.PesterModulePath -Force -Global -DisableNameChecking -ErrorAction Stop
    if(!(Test-QuietScriptsMutationSlotPester -Modules @(Get-Module Pester -All))){throw 'ScriptsTestPesterVersionMismatch'}
    $scope=New-Module -Name QuietScriptsMutationScope -ScriptBlock {}
    $state=Get-QuietScriptsMutationSlotState
    $sequence=1
    $lastParentCheck=[Diagnostics.Stopwatch]::StartNew()
    while(![IO.File]::Exists([IO.Path]::Combine($request.Directory,'stop'))){
        if($lastParentCheck.Elapsed.TotalSeconds -ge 2){
            $lastParentCheck.Restart()
            $parent=$null
            try{$parent=[Diagnostics.Process]::GetProcessById([int]$request.ParentProcessId)}catch{$parent=$null}
            if(!(Test-QuietScriptsMutationSlotParent -Process $parent -StartTicks ([long]$request.ParentStartTicks))){return}
        }
        $jobPath=[IO.Path]::Combine($request.Directory,'job-'+$sequence+'.json')
        if(![IO.File]::Exists($jobPath)){[void][Threading.Tasks.Task]::Delay(20).GetAwaiter().GetResult();continue}
        $job=Get-Content -LiteralPath $jobPath -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable
        $result=Invoke-QuietScriptsMutationSlotJob -Request $request -Job $job -State $state -Scope $scope
        Write-WorkspaceJson ([IO.Path]::Combine($request.Directory,'result-'+$sequence+'.json')) $result
        $sequence++
    }
}

Export-ModuleMember -Function Test-QuietScriptsMutationSlotPester,Test-QuietScriptsMutationSlotParent,Get-QuietScriptsMutationSlotState,Restore-QuietScriptsMutationSlotState,Start-QuietScriptsMutationSlot,Submit-QuietScriptsMutationJob,Receive-QuietScriptsMutationJob,Wait-QuietScriptsMutationJob,Stop-QuietScriptsMutationSlot,Invoke-QuietScriptsMutationSlotJob,Invoke-QuietScriptsMutationSlotWorker
