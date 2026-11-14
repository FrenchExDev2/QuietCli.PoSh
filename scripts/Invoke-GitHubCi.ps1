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
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/WorkspaceProjects.psm1')) -DisableNameChecking -ErrorAction Stop
    $selectedRoot=if($PSBoundParameters.ContainsKey('WorkspaceRoot')){$PSBoundParameters['WorkspaceRoot']}else{Split-Path $PSScriptRoot -Parent}
    New-QuietWorkspaceSuiteParameter -WorkspaceRoot $selectedRoot -Scope Host
}
end {
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true'){throw 'GitHubCiRequiresGitHubActionsContext; use Invoke-WorkspaceCi.ps1 locally.'}
$Suite=if($PSBoundParameters.ContainsKey('Suite')){[string]$PSBoundParameters['Suite']}else{'All'}
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,('Build and run GitHub suite '+$Suite))){return}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
$WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path)
if($RunDirectory){$RunDirectory=[IO.Path]::GetFullPath($RunDirectory,$PWD.Path)}
$mutationShard=$false;$shardIndex=0;$shardCount=0
if($Suite -ceq 'RunProfilesMutation' -and ($env:QUIETCLI_MUTATION_SHARD_INDEX -or $env:QUIETCLI_MUTATION_SHARD_COUNT)){
    if(![int]::TryParse($env:QUIETCLI_MUTATION_SHARD_INDEX,[ref]$shardIndex) -or ![int]::TryParse($env:QUIETCLI_MUTATION_SHARD_COUNT,[ref]$shardCount) -or $shardCount -lt 2 -or $shardCount -gt 32 -or $shardIndex -lt 0 -or $shardIndex -ge $shardCount -or $env:GITHUB_SHA -cnotmatch '\A[a-f0-9]{40}\z' -or $Image -or $Profiler){throw 'GitHubMutationShardContextInvalid'}
    $mutationShard=$true
}
if($Suite -ceq 'All' -or $Suite -cin @(Get-QuietWorkspaceProjects $WorkspaceRoot|Where-Object {!$_.IsTest}|ForEach-Object {$_.Suite})){$null=& ([IO.Path]::Combine($PSScriptRoot,'Test-TestCaseMetadata.ps1')) -WorkspaceRoot $WorkspaceRoot}
if(!$SkipBuild -and $Suite -ne 'RunProfilesMutation'){
    $buildRid=if($ExpectedRuntimeIdentifier){$ExpectedRuntimeIdentifier}else{[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier}
    $build=@{WorkspaceRoot=$WorkspaceRoot;Suite=$Suite;Configuration='Release';ReadyToRun=$true;ReadyToRunRuntimeIdentifier=@($buildRid)}
    if($Suite -notin @('Tooling','Distribution','GalleryPreview')){$build.RuntimeIdentifier=@($buildRid)}
    & ([IO.Path]::Combine($PSScriptRoot,'Build-Workspace.ps1')) @build
}
if(!$RunDirectory){$RunDirectory=[IO.Path]::Combine($WorkspaceRoot,('artifacts/tests/github-'+[guid]::NewGuid().ToString('N').Substring(0,8)))}
if(Test-Path -LiteralPath $RunDirectory){throw 'GitHubCiRunDirectoryExists'}
[void][IO.Directory]::CreateDirectory($RunDirectory)
$parameters=@{WorkspaceRoot=$WorkspaceRoot;RunDirectory=$RunDirectory;Suite=$Suite;SkipTty=[bool]$SkipTty;MaxConcurrency=$MaxConcurrency}
if($ExpectedRuntimeIdentifier){$parameters.ExpectedRuntimeIdentifier=$ExpectedRuntimeIdentifier}
if($Profiler){$parameters.Profiler=$true;$parameters.ProfilerModulePath=$ProfilerModulePath;$parameters.ClrProfilerPath=$ClrProfilerPath}
Write-Host ('GitHub CI entry: '+(@{Suite=$Suite;ProcessId=$PID;Runtime=[Environment]::Version.ToString();HostRid=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;DockerFallback=[bool]$Image;RunDirectory=$RunDirectory}|ConvertTo-Json -Compress))
if($Image){
    if(!$Platform){throw 'GitHubDockerFallbackPlatformRequired'}
    $parameters.Image=$Image;$parameters.Platform=$Platform;$parameters.ContainerRuntime='docker';$parameters.GitHubActions=$true;$parameters.TimeoutSeconds=$TimeoutSeconds
    & ([IO.Path]::Combine($PSScriptRoot,'Invoke-ContainerWorker.ps1')) @parameters
}else{
    & ([IO.Path]::Combine($PSScriptRoot,'Invoke-TestWorker.ps1')) @parameters
}
$summary=Get-Content -LiteralPath ([IO.Path]::Combine($RunDirectory,'summary.json')) -Raw -Encoding utf8|ConvertFrom-Json
$suiteSummaries=if($summary.PSObject.Properties['Suites']){@($summary.Suites)}else{@()}
if($mutationShard){
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/MutationShards.psm1')) -ErrorAction Stop -DisableNameChecking
    $reportFile=Get-Item -LiteralPath ([IO.Path]::Combine($RunDirectory,'run-profiles-mutation.json')) -ErrorAction Stop
    if($reportFile.Length -gt 2097152 -or $reportFile.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'MutationShardReportInvalid'}
    $report=[IO.File]::ReadAllText($reportFile.FullName,[Text.UTF8Encoding]::new($false,$true))|ConvertFrom-Json
    $catalogue=@((Import-PowerShellDataFile -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Mutation.Catalogue.psd1'))).Mutants)
    $shard=Assert-QuietMutationShard -Report $report -Catalogue $catalogue -SourceSHA256 (Get-QuietRunProfileMutationIdentity $WorkspaceRoot) -Revision $env:GITHUB_SHA -Index $shardIndex -Count $shardCount
    if($suiteSummaries.Count -ne 1){throw 'GitHubMutationShardSummaryInvalid'}
    $mutationSummary=$suiteSummaries[0]
    if($mutationSummary.Project -cne 'RunProfiles' -or $mutationSummary.Mutation -isnot [bool] -or !$mutationSummary.Mutation -or $mutationSummary.Partial -isnot [bool] -or !$mutationSummary.Partial -or $mutationSummary.Incomplete -isnot [bool] -or $mutationSummary.Incomplete -or $mutationSummary.Failed -ne 0 -or $mutationSummary.Skipped -ne 0 -or $mutationSummary.Passed -ne $shard.Killed -or $summary.State.Failed -ne 0 -or $summary.State.Passed -ne $shard.Killed){throw 'GitHubMutationShardSummaryInvalid'}
}elseif(@($suiteSummaries|Where-Object {$_ -and (($_.PSObject.Properties['Partial'] -and $_.Partial) -or ($_.PSObject.Properties['Incomplete'] -and $_.Incomplete))}).Count){throw 'GitHubCiRequiresCompleteUnfilteredSuites'}
if($summary.State.State -ne 'Success'){
    Write-WorkspaceFailureDiagnostics -Summary $summary -RunDirectory $RunDirectory
    throw "GitHub companion tests failed. See $RunDirectory"
}
[pscustomobject]@{State=$summary.State.State;Passed=$summary.State.Passed;Failed=$summary.State.Failed;RunDirectory=$RunDirectory;Partial=$mutationShard}
}
