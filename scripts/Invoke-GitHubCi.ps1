#requires -Version 7.6
<#
.SYNOPSIS
GitHub-only test entry point; executes directly in the selected runner or job container.
.PARAMETER WorkspaceRoot
Checked-out workspace containing the shared test worker.
.PARAMETER RunDirectory
New artifact directory for this run.
.PARAMETER SkipBuild
Uses the verified binaries already prepared for this execution environment.
.PARAMETER ExpectedRuntimeIdentifier
Required native host and engine RID.
.PARAMETER SkipTty
Explicit GitHub qualification scope excluding native terminal campaigns.
.PARAMETER Profiler
Enables the shared independent PowerShell/CLR profiling pass.
.PARAMETER ProfilerModulePath
Prepared pinned PowerShell profiler manifest.
.PARAMETER ClrProfilerPath
Prepared pinned CLR collector.
.PARAMETER Image
Docker fallback only: already verified local image ID. No registry publication occurs here.
.PARAMETER Platform
Docker fallback image distribution.
.PARAMETER TimeoutSeconds
Docker fallback guest deadline; direct execution uses GitHub step/job timeouts.
.PARAMETER Suite
Selected shared companion suite or focused tooling campaign.
.PARAMETER MaxConcurrency
Maximum number of internal test workers used by parallel-safe campaigns.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$RunDirectory,[switch]$SkipBuild,
    [string]$ExpectedRuntimeIdentifier,[switch]$SkipTty,[switch]$Profiler,[string]$ProfilerModulePath,[string]$ClrProfilerPath,
    [string]$Image,[ValidateSet('debian','alpine')][string]$Platform,[ValidateRange(1,7200)][int]$TimeoutSeconds=1800,
    [ValidateRange(1,32)][int]$MaxConcurrency=[Math]::Min(4,[Math]::Max(1,[Environment]::ProcessorCount)))
dynamicparam {
    . (Join-Path $PSScriptRoot 'WorkspaceProjects.ps1')
    $selectedRoot=if($PSBoundParameters.ContainsKey('WorkspaceRoot')){$PSBoundParameters['WorkspaceRoot']}else{Split-Path $PSScriptRoot -Parent}
    New-QuietWorkspaceSuiteParameter -WorkspaceRoot $selectedRoot -Scope Host
}
end {
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true'){throw 'GitHubCiRequiresGitHubActionsContext; use Invoke-WorkspaceCi.ps1 locally.'}
$Suite=if($PSBoundParameters.ContainsKey('Suite')){[string]$PSBoundParameters['Suite']}else{'All'}
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,('Build and run GitHub suite '+$Suite))){return}
. (Join-Path $PSScriptRoot 'Common.ps1')
if(!$SkipBuild){
    $buildRid=if($ExpectedRuntimeIdentifier){$ExpectedRuntimeIdentifier}else{[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier}
    & (Join-Path $PSScriptRoot 'Build-Workspace.ps1') -WorkspaceRoot $WorkspaceRoot -Configuration Release -ReadyToRun -ReadyToRunRuntimeIdentifier $buildRid
}
if(!$RunDirectory){$RunDirectory=Join-Path $WorkspaceRoot ('artifacts/tests/github-'+[guid]::NewGuid().ToString('N').Substring(0,8))}
if(Test-Path -LiteralPath $RunDirectory){throw 'GitHubCiRunDirectoryExists'}
[void][IO.Directory]::CreateDirectory($RunDirectory)
$parameters=@{WorkspaceRoot=$WorkspaceRoot;RunDirectory=$RunDirectory;Suite=$Suite;SkipTty=[bool]$SkipTty;MaxConcurrency=$MaxConcurrency}
if($ExpectedRuntimeIdentifier){$parameters.ExpectedRuntimeIdentifier=$ExpectedRuntimeIdentifier}
if($Profiler){$parameters.Profiler=$true;$parameters.ProfilerModulePath=$ProfilerModulePath;$parameters.ClrProfilerPath=$ClrProfilerPath}
Write-Host ('GitHub CI entry: '+(@{Suite=$Suite;ProcessId=$PID;Runtime=[Environment]::Version.ToString();HostRid=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;DockerFallback=[bool]$Image;RunDirectory=$RunDirectory}|ConvertTo-Json -Compress))
if($Image){
    if(!$Platform){throw 'GitHubDockerFallbackPlatformRequired'}
    $parameters.Image=$Image;$parameters.Platform=$Platform;$parameters.ContainerRuntime='docker';$parameters.GitHubActions=$true;$parameters.TimeoutSeconds=$TimeoutSeconds
    & (Join-Path $PSScriptRoot 'Invoke-ContainerWorker.ps1') @parameters
}else{
    & (Join-Path $PSScriptRoot 'Invoke-TestWorker.ps1') @parameters
}
$summary=Get-Content -LiteralPath (Join-Path $RunDirectory 'summary.json') -Raw -Encoding utf8|ConvertFrom-Json
if($summary.State.State -ne 'Success'){
    Write-WorkspaceFailureDiagnostics -Summary $summary -RunDirectory $RunDirectory
    throw "GitHub companion tests failed. See $RunDirectory"
}
[pscustomobject]@{State=$summary.State.State;Passed=$summary.State.Passed;Failed=$summary.State.Failed;RunDirectory=$RunDirectory}
}
