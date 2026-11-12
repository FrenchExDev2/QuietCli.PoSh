#requires -Version 7.6
<#
.SYNOPSIS
Runs companion suites with a dedicated local monitor; CI uses the same saved state.
.PARAMETER WorkspaceRoot
QuietCli2 root.
.PARAMETER Profiler
Enables a separate pinned PowerShell and CLR profiling pass, outside benchmark samples.
.PARAMETER ProfilerModulePath
Explicit Profiler 4.3.0 manifest; the launcher prepares a private cache when omitted.
.PARAMETER ClrProfilerPath
Explicit pinned dotnet-trace DLL.
.PARAMETER SkipTty
Excludes native TTY/PTY execution from this run; local runs include it by default.
.PARAMETER Suite
Core, Git, Vagrant, All, Import, mandatory Integration, explicit-repository RealStatus, or complete RunProfiles/RunProfilesMutation tooling qualification.
.PARAMETER RunDirectory
New output directory; generated when omitted.
.PARAMETER Headless
CI-only output mode, without a monitor process or monitor reopen instruction.
.PARAMETER SkipBuild
Uses already built engine and test fixture.
.PARAMETER TimeoutSeconds
Maximum worker time before a saved Timeout state.
.PARAMETER RepositoryConfig
UTF-8 JSON array of existing repository roots; required by RealStatus.
.PARAMETER ExpectedRuntimeIdentifier
Required actual PowerShell and engine runtime identifier; detects accidental architecture emulation.
.PARAMETER Case
Development only: wildcard selecting owning companion cases by name; the run is partial and never qualifies a delivery.
.PARAMETER StopOnFirstFailure
Development only: stops the owning companion at the first observed failing case; the run is incomplete.
.PARAMETER DotNetSuite
Focused .NET tooling campaign, used only with Suite DotNet.
.PARAMETER MaxConcurrency
Maximum number of internal test workers used by parallel-safe campaigns.
#>
[CmdletBinding(SupportsShouldProcess)]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$RunDirectory,[switch]$Headless,[switch]$SkipBuild,[ValidateRange(1,7200)][int]$TimeoutSeconds=1800,[ValidatePattern('^[a-z0-9-]+$')][string]$ExpectedRuntimeIdentifier,[string]$RepositoryConfig,[switch]$SkipTty,[switch]$Profiler,[string]$ProfilerModulePath,[string]$ClrProfilerPath,[string]$Case,[switch]$StopOnFirstFailure,[ValidateSet('Readiness','Provisioning','Layout','Locks','All')][string]$DotNetSuite='All',[ValidateRange(1,32)][int]$MaxConcurrency=[Math]::Min(4,[Math]::Max(1,[Environment]::ProcessorCount)))
dynamicparam {
    . (Join-Path $PSScriptRoot 'WorkspaceProjects.ps1')
    $selectedRoot=if($PSBoundParameters.ContainsKey('WorkspaceRoot')){$PSBoundParameters['WorkspaceRoot']}else{Split-Path $PSScriptRoot -Parent}
    New-QuietWorkspaceSuiteParameter -WorkspaceRoot $selectedRoot -Scope Host
}
end {
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Invoke-WorkspaceCi')){return}
$Suite=if($PSBoundParameters.ContainsKey('Suite')){[string]$PSBoundParameters['Suite']}else{'All'}
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
if($Suite -ceq 'All' -or $Suite -cin @(Get-QuietWorkspaceProjects $WorkspaceRoot|Where-Object {!$_.IsTest}|ForEach-Object Suite)){$null=& (Join-Path $PSScriptRoot 'Test-TestCaseMetadata.ps1') -WorkspaceRoot $WorkspaceRoot}
if($Profiler){
    if($Suite -notin @('Core','All','Integration')){throw 'ProfilerRequiresCoreIntegration'}
    if(!$ProfilerModulePath -or !$ClrProfilerPath){
        $tools=& (Join-Path $PSScriptRoot 'Initialize-Profilers.ps1') -OutputDirectory (Join-Path (Get-QuietReportRoot $WorkspaceRoot 'profilers') 'pinned')
        $ProfilerModulePath=$tools.ProfilerModulePath;$ClrProfilerPath=$tools.ClrProfilerPath
    }
}
if(!$SkipBuild -and $Suite -notin @('DotNet','RunProfilesMutation')){& (Join-Path $PSScriptRoot 'Build-Workspace.ps1') -WorkspaceRoot $WorkspaceRoot -Suite $Suite}
if(!$RunDirectory){$RunDirectory=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'tests') ([DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))}
if(Test-Path -LiteralPath $RunDirectory){throw 'TestRunDirectoryExists'}
[void][IO.Directory]::CreateDirectory($RunDirectory)
$runner=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
$workerPath=Join-Path $PSScriptRoot 'Invoke-TestWorker.ps1'
$monitorPath=Join-Path $PSScriptRoot 'Watch-Tests.ps1'
$workerArguments=@('-File',(ConvertTo-CiArgument ($workerPath)),'-WorkspaceRoot',(ConvertTo-CiArgument ($WorkspaceRoot)),'-RunDirectory',(ConvertTo-CiArgument ($RunDirectory)),'-Suite',$Suite,'-MaxConcurrency',$MaxConcurrency)
if($Suite -eq 'DotNet'){$workerArguments+=@('-DotNetSuite',$DotNetSuite)}
if($Suite -eq 'RealStatus' -and !$RepositoryConfig){throw 'RealStatusRequiresRepositoryConfig'}
if($RepositoryConfig){$workerArguments+=@('-RepositoryConfig',(ConvertTo-CiArgument ([IO.Path]::GetFullPath($RepositoryConfig,$PWD.Path))))}
if($Profiler){$workerArguments+=@('-Profiler','-ProfilerModulePath',(ConvertTo-CiArgument ($ProfilerModulePath)),'-ClrProfilerPath',(ConvertTo-CiArgument ($ClrProfilerPath)))}
if($Case){$workerArguments+=@('-Case',(ConvertTo-CiArgument ($Case)))}
if($SkipTty){$workerArguments+='-SkipTty'}
if($StopOnFirstFailure){$workerArguments+='-StopOnFirstFailure'}
if($ExpectedRuntimeIdentifier){$workerArguments+=@('-ExpectedRuntimeIdentifier',$ExpectedRuntimeIdentifier)}
$options=@{FilePath=$runner;ArgumentList=$workerArguments;PassThru=$true;RedirectStandardOutput=(Join-Path $RunDirectory 'worker.stdout.log');RedirectStandardError=(Join-Path $RunDirectory 'worker.stderr.log')}
if($IsWindows){$options.WindowStyle='Hidden'}
$worker=Start-Process @options
$monitor=$null
if(!$Headless){
    if(!$IsWindows){$worker.Kill($true);throw 'Use the Windows host launcher for a visible local monitor; Headless is reserved for CI.'}
    $monitor=Start-Process -FilePath $runner -WindowStyle Normal -ArgumentList @('-File',(ConvertTo-CiArgument ($monitorPath)),'-RunDirectory',(ConvertTo-CiArgument ($RunDirectory))) -RedirectStandardError (Join-Path $RunDirectory 'monitor.stderr.log') -PassThru
    "Monitor: pwsh -File `"$monitorPath`" -RunDirectory `"$RunDirectory`""
}
$summary=Wait-WorkspaceWorker -Worker $worker -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -Runner $runner -Monitor $monitor -TimeoutSeconds $TimeoutSeconds
[pscustomobject]@{State=$summary.State.State;Passed=$summary.State.Passed;Failed=$summary.State.Failed;RunDirectory=$RunDirectory}
if($summary.State.State -ne 'Success'){
    Write-WorkspaceFailureDiagnostics -Summary $summary -RunDirectory $RunDirectory
    if($summary.State.State -eq 'Cancelled'){throw "Companion tests cancelled. See $RunDirectory"}
    throw "Companion tests failed. See $RunDirectory"
}

}
