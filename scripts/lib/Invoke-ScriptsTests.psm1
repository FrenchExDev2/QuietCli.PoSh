#Objective: Runs the scripts Pester suites in a supervised worker with a monitor, pinned tools and saved reports.
#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ScriptsTests.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'RunToolCache.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceJson.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ReportPaths.psm1')) -DisableNameChecking -ErrorAction Stop

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
    .PARAMETER Headless
    Disables the visible monitor (CI).
    .PARAMETER RunDirectory
    New run directory; an existing directory is rejected.
    .PARAMETER TimeoutSeconds
    Wall-clock limit for the worker.
    .PARAMETER Offline
    Requires the pinned test tools to be cached already.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$TestsRoot,[Parameter(Mandatory)][string]$ScriptsRoot,[string]$Kind='All',[string[]]$Path=@(),[string[]]$FullNameFilter=@(),[string[]]$Tag=@(),[string[]]$ExcludeTag=@(),[int]$Seed,[switch]$Coverage,[switch]$Headless,[string]$RunDirectory,[int]$TimeoutSeconds=1800,[switch]$Offline)
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
    }
    $requestPath=[IO.Path]::Combine($RunDirectory,'request.json')
    Write-WorkspaceJson $requestPath $request
    Write-Host ("Scripts tests: kind=$Kind files=$($plan.Files.Count) seed=$Seed partial=$($plan.Partial) run=$RunDirectory")
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'Common.psm1')) -DisableNameChecking -ErrorAction Stop
    $runner=[IO.Path]::Combine($PSHOME,$(if($IsWindows){'pwsh.exe'}else{'pwsh'}))
    $command="Import-Module '"+([IO.Path]::Combine($PSScriptRoot,'Invoke-ScriptsTests.psm1')).Replace("'","''")+"' -DisableNameChecking -ErrorAction Stop; Invoke-QuietScriptsTestWorker -RequestPath '"+$requestPath.Replace("'","''")+"'"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $options=@{FilePath=$runner;ArgumentList=@('-NoProfile','-NonInteractive','-EncodedCommand',$encoded);PassThru=$true;RedirectStandardOutput=([IO.Path]::Combine($RunDirectory,'worker.stdout.log'));RedirectStandardError=([IO.Path]::Combine($RunDirectory,'worker.stderr.log'))}
    if($IsWindows){$options.WindowStyle='Hidden'}
    $worker=Start-Process @options
    $monitor=$null
    if(!$Headless){
        $monitorPath=[IO.Path]::Combine(([IO.Path]::GetDirectoryName($PSScriptRoot)),'Watch-Tests.ps1')
        $monitor=Start-Process -FilePath $runner -WindowStyle Normal -ArgumentList @('-NoProfile','-File',(ConvertTo-CiArgument $monitorPath),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory)) -RedirectStandardError ([IO.Path]::Combine($RunDirectory,'monitor.stderr.log')) -PassThru
    }
    $summary=Wait-WorkspaceWorker -Worker $worker -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -Runner $runner -Monitor $monitor -TimeoutSeconds $TimeoutSeconds
    $state=[string]$summary.State.State
    $reportPath=[IO.Path]::Combine($RunDirectory,'report.json')
    $report=if([IO.File]::Exists($reportPath)){Get-Content -LiteralPath $reportPath -Raw -Encoding utf8|ConvertFrom-Json}else{$null}
    [pscustomobject][ordered]@{
        State=$state;Passed=[int]$summary.State.Passed;Failed=[int]$summary.State.Failed;Partial=[bool]$plan.Partial;Seed=$Seed
        RunDirectory=$RunDirectory;Report=$reportPath;Incomplete=$(if($report){[bool]$report.Incomplete}else{$true});ExitCode=(Get-QuietScriptsTestExitCode $state)
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
        Import-Module $request.PesterModulePath -Force -DisableNameChecking -ErrorAction Stop
        $loaded=@(Get-Module Pester)
        if($loaded.Count -ne 1 -or $loaded[0].Version -ne [version]'6.2.0'){throw 'ScriptsTestPesterVersionMismatch'}
        Write-Host ("Seed: $($request.Seed) (replay with -Seed $($request.Seed))")
        $configuration=New-PesterConfiguration -Hashtable $request.Configuration
        $result=Invoke-Pester -Configuration $configuration
        $report=ConvertTo-QuietScriptsTestReport -Result $result -Plan $request.Plan -Seed ([int]$request.Seed) -CoverageTarget $request.CoverageTarget
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
