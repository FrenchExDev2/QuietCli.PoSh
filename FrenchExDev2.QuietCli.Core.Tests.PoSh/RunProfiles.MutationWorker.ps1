#requires -Version 7.6
<#
.SYNOPSIS
Runs one already-mutated sandbox and saves a bounded suite result for its owning scheduler.
.PARAMETER WorkspaceRoot
Checkout supplying the engine-independent process helper.
.PARAMETER Sandbox
Owned mutation sandbox containing the suite.
.PARAMETER Seed
Deterministic property seed.
.PARAMETER Iterations
Property corpus size.
.PARAMETER TimeoutSeconds
Deadline of the owned suite process.
.PARAMETER ConsoleEncoding
Encoding selected by the parent campaign.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$Sandbox,[int]$Seed,[int]$Iterations,[int]$TimeoutSeconds,[string]$ConsoleEncoding='utf-8')
if(!$PSCmdlet.ShouldProcess($Sandbox,'Run one owned mutation suite and save its bounded result')){return}
$ErrorActionPreference='Stop'
Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Ci.Process.psm1') -DisableNameChecking -ErrorAction Stop
$capture=@{Summary=$null}
$result=Invoke-CiProcess -FilePath (Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})) -ArgumentList @('-File',(Join-Path $Sandbox 'FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Tests.ps1'),'-Seed',"$Seed",'-Iterations',"$Iterations",'-ConsoleEncoding',$ConsoleEncoding,'-Skip','profiler:,console:,coldstart-live:,tool-cache-live:') -WorkingDirectory $Sandbox -TimeoutSeconds $TimeoutSeconds -State $capture -OnOutput {
    param($record,$state)
    if($record.Stream -eq 'stdout' -and $record.Text -match '^SUMMARY Passed=(\d+) Failed=(\d+) Skipped=(\d+)$'){
        $state.Summary=@{Passed=[int]$Matches[1];Failed=[int]$Matches[2];Skipped=[int]$Matches[3]}
    }
}
$document=@{Outcome=$result.Outcome;Summary=$capture.Summary;Sandbox=$Sandbox;ProcessId=$PID}
[IO.File]::WriteAllText((Join-Path $Sandbox 'mutation-worker-result.json'),($document|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
