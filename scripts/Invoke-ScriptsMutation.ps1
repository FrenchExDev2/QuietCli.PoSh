#requires -Version 7.6
<#
.SYNOPSIS
Stryker-style mutation testing of scripts/lib targets: each mutant runs the target's unit tests in an isolated scripts copy on a persistent slot worker, reusing cached outcomes.
.PARAMETER Target
Target names from the targets file (a CI shard); all targets when omitted.
.PARAMETER ThrottleLimit
Persistent slot workers, each with its own scripts copy (default: half the processors, at least 1).
.PARAMETER Seed
Test seed shared by the baseline and every mutant run; generated and recorded when omitted.
.PARAMETER Headless
Disables the visible monitor (CI).
.PARAMETER RunDirectory
New run directory; defaults under the scripts-mutation report root.
.PARAMETER TimeoutSeconds
Wall-clock limit of the whole campaign (default 3600).
.PARAMETER WorkspaceRoot
Repository root; defaults to the parent of this scripts directory.
.PARAMETER ScriptsRoot
Scripts root holding the target libraries (copied, never modified); defaults to this directory.
.PARAMETER TestsRoot
Tests root; defaults to <workspace>/test/scripts.
.PARAMETER TargetsPath
Targets file; defaults to <TestsRoot>/mutation.targets.psd1.
.PARAMETER Offline
Requires the pinned test tools to be cached already.
.PARAMETER NoCache
Runs every mutant and leaves the incremental cache untouched.
.PARAMETER NoInputCache
Runs every mutant without using saved outcomes or baselines, and saves fresh results.
.PARAMETER CacheDirectory
Incremental cache root; defaults to <WorkspaceRoot>/.cache/script-mutation.
.PARAMETER PruneCache
After a complete campaign, deletes the cache documents this run did not key (use a cache dedicated to the selected
targets, as each CI shard does). Rejected with -NoCache.
.PARAMETER RecycleAfter
Jobs after which a slot worker is replaced by a fresh process (default 200).
#>
[CmdletBinding(SupportsShouldProcess)]
param([string[]]$Target=@(),[ValidateRange(1,32)][int]$ThrottleLimit=([Math]::Max(1,[Math]::Min(32,[int][Math]::Floor([Environment]::ProcessorCount/2)))),[ValidateRange(0,2147483647)][int]$Seed=0,[switch]$Headless,[string]$RunDirectory,[ValidateRange(60,86400)][int]$TimeoutSeconds=3600,[string]$WorkspaceRoot=([IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))),[string]$ScriptsRoot=$PSScriptRoot,[string]$TestsRoot,[string]$TargetsPath,[switch]$Offline,[switch]$NoCache,[switch]$NoInputCache,[string]$CacheDirectory,[switch]$PruneCache,[ValidateRange(1,100000)][int]$RecycleAfter=200)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Invoke-ScriptsMutation')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Invoke-ScriptsMutation.psm1')) -DisableNameChecking -ErrorAction Stop
if([string]::IsNullOrWhiteSpace($TestsRoot)){$TestsRoot=[IO.Path]::Combine($WorkspaceRoot,'test','scripts')}
if([string]::IsNullOrWhiteSpace($TargetsPath)){$TargetsPath=[IO.Path]::Combine($TestsRoot,'mutation.targets.psd1')}
$outcome=Invoke-QuietScriptInvokeScriptsMutation -WorkspaceRoot $WorkspaceRoot -ScriptsRoot $ScriptsRoot -TestsRoot $TestsRoot -TargetsPath $TargetsPath -Target $Target -ThrottleLimit $ThrottleLimit -Seed $Seed -Headless:$Headless -RunDirectory $RunDirectory -TimeoutSeconds $TimeoutSeconds -Offline:$Offline -NoCache:$NoCache -NoInputCache:$NoInputCache -CacheDirectory $CacheDirectory -PruneCache:$PruneCache -RecycleAfter $RecycleAfter
$outcome
if($outcome.ExitCode -ne 0){throw "Scripts mutation $($outcome.State); passed=$($outcome.Passed). See $($outcome.Markdown)"}
