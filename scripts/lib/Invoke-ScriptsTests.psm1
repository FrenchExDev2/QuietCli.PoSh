#Objective: Runs the scripts Pester suites in a supervised worker with a monitor, pinned tools and saved reports.
#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ScriptsTests.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'RunToolCache.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceJson.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ReportPaths.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ScriptsWorker.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'PesterProgress.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'Ci.Process.psm1')) -DisableNameChecking -ErrorAction Stop

function Invoke-QuietScriptInvokeScriptsTests {
    <#
    .SYNOPSIS
    Plans, launches and supervises one scripts test run; returns its outcome and exit code.
    .PARAMETER WorkspaceRoot
    Repository root.
    .PARAMETER TestsRoot
    Tests root containing unit/ and integration/.
    .PARAMETER ScriptsRoot
    Scripts root exported as QUIETCLI_SCRIPTS_ROOT; tests import libraries from it.
    .PARAMETER Kind
    Unit, Integration or All.
    .PARAMETER Path
    Optional file or directory selectors inside TestsRoot (partial run).
    .PARAMETER FullNameFilter
    Optional Pester full-name filters (partial run).
    .PARAMETER Tag
    Optional Pester tags (partial run).
    .PARAMETER ExcludeTag
    Optional excluded Pester tags (partial run).
    .PARAMETER Seed
    Seed exported as QUIETCLI_TEST_SEED; generated when 0.
    .PARAMETER Coverage
    Enables JaCoCo coverage on coverage.targets.psd1 and enforces its threshold.
    .PARAMETER MaxConcurrency
    Requested maximum worker processes for independent files. Coverage runs use one worker.
    .PARAMETER Headless
    Disables the visible monitor (CI).
    .PARAMETER RunDirectory
    New run directory; an existing directory is rejected.
    .PARAMETER TimeoutSeconds
    Wall-clock limit for the worker.
    .PARAMETER Offline
    Requires the pinned test tools to be cached already.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$TestsRoot,[Parameter(Mandatory)][string]$ScriptsRoot,[string]$Kind='All',[string[]]$Path=@(),[string[]]$FullNameFilter=@(),[string[]]$Tag=@(),[string[]]$ExcludeTag=@(),[int]$Seed,[switch]$Coverage,[ValidateRange(1,32)][int]$MaxConcurrency=1,[switch]$Headless,[string]$RunDirectory,[int]$TimeoutSeconds=1800,[switch]$Offline)
    $WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot);$ScriptsRoot=[IO.Path]::GetFullPath($ScriptsRoot)
    if(![IO.Directory]::Exists($ScriptsRoot)){throw 'ScriptsTestPathInvalid: scripts-root'}
    $plan=Get-QuietScriptsTestPlan -TestsRoot $TestsRoot -Kind $Kind -Path $Path -FullNameFilter $FullNameFilter -Tag $Tag -ExcludeTag $ExcludeTag
    $targets=if($Coverage){Get-QuietScriptsCoverageTargets -TestsRoot $plan.TestsRoot -ScriptsRoot $ScriptsRoot}else{$null}
    if($Seed -eq 0){$Seed=[Random]::Shared.Next(1,[int]::MaxValue)}
    if(!$Headless -and !$IsWindows){throw 'Use the Windows host launcher for a visible local monitor; Headless is reserved for CI.'}
    $tools=Initialize-QuietTestTools -WorkspaceRoot $WorkspaceRoot -Tool pester -Offline:$Offline
    if([string]::IsNullOrWhiteSpace($RunDirectory)){$RunDirectory=[IO.Path]::Combine((Get-QuietReportRoot $WorkspaceRoot 'scripts-tests'),([DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)))}
    $RunDirectory=[IO.Path]::GetFullPath($RunDirectory)
    if([IO.Directory]::Exists($RunDirectory) -or [IO.File]::Exists($RunDirectory)){throw 'TestRunDirectoryExists'}
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $request=[ordered]@{
        WorkspaceRoot=$WorkspaceRoot;ScriptsRoot=$ScriptsRoot;RunDirectory=$RunDirectory;Seed=$Seed;PesterModulePath=$tools.PesterModulePath
        Plan=$plan;CoverageTarget=$(if($targets){$targets.Threshold}else{$null})
        Configuration=(New-QuietScriptsPesterConfiguration -Plan $plan -RunDirectory $RunDirectory -CoverageTargets $targets)
        MaxConcurrency=$(if($Coverage){1}else{[Math]::Min($MaxConcurrency,$plan.Files.Count)})
    }
    $requestPath=[IO.Path]::Combine($RunDirectory,'request.json')
    Write-WorkspaceJson $requestPath $request
    Write-Host ("Scripts tests: kind=$Kind files=$($plan.Files.Count) seed=$Seed partial=$($plan.Partial) max-workers=$($request.MaxConcurrency) run=$RunDirectory")
    $summary=Invoke-QuietScriptsSupervisedWorker -ModulePath ([IO.Path]::Combine($PSScriptRoot,'Invoke-ScriptsTests.psm1')) -WorkerFunction Invoke-QuietScriptsTestWorker -RequestPath $requestPath -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -Headless:$Headless -TimeoutSeconds $TimeoutSeconds
    $state=[string]$summary.State.State
    $reportPath=[IO.Path]::Combine($RunDirectory,'report.json')
    $report=if([IO.File]::Exists($reportPath)){Get-Content -LiteralPath $reportPath -Raw -Encoding utf8|ConvertFrom-Json}else{$null}
    [pscustomobject][ordered]@{
        State=$state;Passed=[int]$summary.State.Passed;Failed=[int]$summary.State.Failed;Partial=[bool]$plan.Partial;Seed=$Seed
        RunDirectory=$RunDirectory;Report=$reportPath;Incomplete=$(if($report){[bool]$report.Incomplete}else{$true});ExitCode=(Get-QuietScriptsTestExitCode $state)
    }
}

function Invoke-QuietScriptsFileWorkers {
    <#
    .SYNOPSIS
    Distributes whole test files among isolated processes, then merges their reports.
    .PARAMETER Request
    Parent request, including filters, pinned Pester and worker limit.
    .PARAMETER Status
    Parent progress record owned by the caller.
    #>
    param([Collections.IDictionary]$Request,[Collections.IDictionary]$Status)
    $parallel=[Collections.Generic.List[string]]::new()
    $serial=[Collections.Generic.List[string]]::new()
    foreach($file in $Request.Plan.Files){
        $tokens=$null;$parseErrors=$null
        $null=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$parseErrors)
        $optOut=$tokens | Where-Object {$_.Kind -eq 'Comment' -and $_.Text -match '^#\s*pester:no-parallel\b'} | Select-Object -First 1
        if($optOut){$serial.Add($file)}else{$parallel.Add($file)}
    }
    $slots=[Math]::Min([int]$Request.MaxConcurrency,$parallel.Count)
    if($slots -lt 2){return}
    $groups=@(for($slot=0;$slot -lt $slots;$slot++){
        ,@(for($index=$slot;$index -lt $parallel.Count;$index+=$slots){$parallel[$index]})
    })
    if($serial.Count){$groups+=,@($serial.ToArray())}

    $workers=[Collections.Generic.List[object]]::new()
    $pwsh=[IO.Path]::Combine($PSHOME,$(if($IsWindows){'pwsh.exe'}else{'pwsh'}))
    $statusPath=[IO.Path]::Combine($Request.RunDirectory,'status.json')
    $modulePath=[IO.Path]::Combine($PSScriptRoot,'Invoke-ScriptsTests.psm1')
    $command='Import-Module $args[0] -DisableNameChecking -ErrorAction Stop; Invoke-QuietScriptsTestWorker -RequestPath $args[1]'
    try{
        for($index=0;$index -lt $groups.Count;$index++){
            $directory=[IO.Path]::Combine($Request.RunDirectory,'files',[string]($index+1))
            $files=$groups[$index]
            $plan=[ordered]@{};foreach($entry in $Request.Plan.GetEnumerator()){$plan[$entry.Key]=$entry.Value}
            $plan.Files=$files
            $child=@{
                WorkspaceRoot=$Request.WorkspaceRoot;ScriptsRoot=$Request.ScriptsRoot;RunDirectory=$directory
                Seed=$Request.Seed;PesterModulePath=$Request.PesterModulePath;Plan=$plan;MaxConcurrency=1
                Configuration=(New-QuietScriptsPesterConfiguration -Plan $plan -RunDirectory $directory)
            }
            $childPath=[IO.Path]::Combine($directory,'request.json')
            Write-WorkspaceJson $childPath $child
            $process=Start-CiProcess -FilePath $pwsh -WorkingDirectory $Request.WorkspaceRoot -Confirm:$false -ArgumentList @('-NoProfile','-NonInteractive','-CommandWithArgs',$command,$modulePath,$childPath)
            $workers.Add([pscustomobject]@{Process=$process;Directory=$directory;Status=$null})
            if($index+1 -lt $slots){continue}

            do{
                $running=$false
                $counts=@{TestPassed=0;TestFailed=0}
                $rows=@(foreach($worker in $workers){
                    if(!$worker.Process.HasExited){$running=$true}
                    $path=[IO.Path]::Combine($worker.Directory,'status.json')
                    try{$worker.Status=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop}
                    catch [IO.IOException]{Write-Verbose "Pester worker $($worker.Process.Id) status is temporarily unavailable"}
                    $observed=$worker.Status
                    foreach($key in @('TestPassed','TestFailed')){$counts[$key]+=[int]$observed.$key}
                    [ordered]@{Platform='Fichiers';State=($observed.State ?? 'Starting');Identity=[string]$worker.Process.Id;StartedUtc=$observed.StartedUtc;FinishedUtc=$observed.FinishedUtc;TestPassed=$observed.TestPassed;TestFailed=$observed.TestFailed}
                })
                $Status.Passed=$Status.TestPassed=$counts.TestPassed
                $Status.Failed=$Status.TestFailed=$counts.TestFailed
                $Status.Runs=$rows
                $Status.Case='Pester file workers'
                Write-WorkspaceJson $statusPath $Status
                if($running){[void][Threading.Tasks.Task]::Delay(250).GetAwaiter().GetResult()}
            }while($running)
        }
        $reports=@(foreach($worker in $workers){
            if($worker.Process.ExitCode -ne 0 -or $worker.Status.State -notin @('Success','Failed') -or $worker.Status.ProcessId -ne $worker.Process.Id){
                throw ('ScriptsTestFileWorkerFailed: '+$worker.Directory)
            }
            Get-Content -LiteralPath ([IO.Path]::Combine($worker.Directory,'report.json')) -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        })
        $report=[ordered]@{Project='Scripts.Tests';Kind=$Request.Plan.Kind;Partial=$Request.Plan.Partial;Seed=$Request.Seed;Files=$Request.Plan.Files;Coverage=$null}
        foreach($key in @('Passed','Failed','TestPassed','TestFailed','Skipped','NotRun','Total')){
            $report[$key]=[int](($reports | ForEach-Object {$_[$key]} | Measure-Object -Sum).Sum)
        }
        $report.Cases=@($reports | ForEach-Object {$_.Cases})
        $report.Incomplete=$report.Total -eq 0 -or @($reports|Where-Object {$_.Incomplete -and $_.Total -gt 0}).Count -gt 0
        $report.State=if($report.Failed -or $report.Incomplete){'Failed'}else{'Success'}

        $junit=[xml]'<testsuites />'
        $attributes=@{tests=0;failures=0;errors=0;disabled=0;time=0.0}
        foreach($worker in $workers){
            $source=[xml][IO.File]::ReadAllText([IO.Path]::Combine($worker.Directory,'results.junit.xml'),[Text.Encoding]::UTF8)
            foreach($key in @($attributes.Keys)){$attributes[$key]+=[double]::Parse(('0'+$source.DocumentElement.GetAttribute($key)),[Globalization.CultureInfo]::InvariantCulture)}
            foreach($suite in $source.SelectNodes('/testsuites/testsuite')){[void]$junit.DocumentElement.AppendChild($junit.ImportNode($suite,$true))}
        }
        foreach($key in $attributes.Keys){$junit.DocumentElement.SetAttribute($key,$attributes[$key].ToString([Globalization.CultureInfo]::InvariantCulture))}
        [IO.File]::WriteAllText([IO.Path]::Combine($Request.RunDirectory,'results.junit.xml'),$junit.OuterXml,[Text.UTF8Encoding]::new($false))
        $report
    }finally{
        foreach($worker in $workers){
            try{if(!$worker.Process.HasExited){$worker.Process.Kill($true);$worker.Process.WaitForExit()}}finally{$worker.Process.Dispose()}
        }
    }
}

function Invoke-QuietScriptsTestWorker {
    <#
    .SYNOPSIS
    Worker body: imports the pinned Pester, runs the planned files once and saves report, status and summary.
    .PARAMETER RequestPath
    request.json written by Invoke-QuietScriptInvokeScriptsTests.
    #>
    param([Parameter(Mandatory)][string]$RequestPath)
    $ErrorActionPreference='Stop'
    $PSStyle.OutputRendering='PlainText'
    $request=Get-Content -LiteralPath $RequestPath -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable
    $runDirectory=$request.RunDirectory
    $statusPath=[IO.Path]::Combine($runDirectory,'status.json');$summaryPath=[IO.Path]::Combine($runDirectory,'summary.json')
    $status=New-QuietScriptsTestStatus -WorkspaceRoot $request.WorkspaceRoot -Plan $request.Plan -ProcessId $PID
    Write-WorkspaceJson $statusPath $status
    try{
        $env:QUIETCLI_TEST_SEED=[string]$request.Seed
        $env:QUIETCLI_SCRIPTS_ROOT=$request.ScriptsRoot
        $env:QUIETCLI_WORKSPACE_ROOT=$request.WorkspaceRoot
        $report=if($request.MaxConcurrency -gt 1){Invoke-QuietScriptsFileWorkers -Request $request -Status $status}
        if(!$report){
            # Global: the test files run outside this module (see below) and must resolve Describe/It to the
            # pinned Pester; otherwise PowerShell autoloads another Pester from PSModulePath, which starts its own run.
            $pester=Import-QuietTestPester -ModulePath $request.PesterModulePath
            Write-Host ("Seed: $($request.Seed) (replay with -Seed $($request.Seed))")
            $configuration=New-PesterConfiguration -Hashtable $request.Configuration
            # The JUnit report is written below, once its texts are XML-safe: Pester's own export fails the whole run on
            # a control character, such as the ANSI colors of an error captured from a child process.
            $junitPath=if($configuration.TestResult.Enabled.Value){$configuration.TestResult.OutputPath.Value}else{$null}
            $configuration.TestResult.Enabled=$false
            # Pester runs the test files in its caller's session state. Calling it from this module would let
            # the trusted libraries imported here shadow the ones the tests import from QUIETCLI_SCRIPTS_ROOT,
            # so it is called from an empty dynamic module whose command lookup falls through to the global scope.
            $testScope=New-Module -Name QuietScriptsTestScope -ScriptBlock {}
            $invoke={& $testScope { param($InvokePester,$Configuration) & $InvokePester -Configuration $Configuration } (Get-Command Pester\Invoke-Pester) $configuration}
            $result=Invoke-QuietPesterWithProgress -Pester $pester -Run $invoke -OnTest {
                param($test,$testState)
                if($testState -ceq 'Running'){return}
                $status[$testState]++
                $status['Test'+$testState]++
                $status.Case="[$testState] $($test.ExpandedPath)"
                Write-WorkspaceJson $statusPath $status
            }
            if($null -ne $junitPath -and $null -ne $result){
                $null=Protect-QuietScriptsTestResult -Result $result
                Export-JUnitReport -Result $result -Path $junitPath
            }
            $report=ConvertTo-QuietScriptsTestReport -Result $result -Plan $request.Plan -Seed ([int]$request.Seed) -CoverageTarget $request.CoverageTarget
        }
        Write-WorkspaceJson ([IO.Path]::Combine($runDirectory,'report.json')) $report
        $status=Update-QuietScriptsTestStatus -Status $status -Report $report
    }catch{
        Write-Host ('Worker error: '+$_.Exception.Message)
        $status=Update-QuietScriptsTestStatus -Status $status -ErrorMessage $_.Exception.Message
    }
    Write-WorkspaceJson $statusPath $status
    Write-WorkspaceJson $summaryPath @{State=$status}
}

Export-ModuleMember -Function Invoke-QuietScriptInvokeScriptsTests,Invoke-QuietScriptsTestWorker
