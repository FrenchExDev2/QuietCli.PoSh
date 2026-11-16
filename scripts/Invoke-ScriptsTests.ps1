#requires -Version 7.6
<#
.SYNOPSIS
Runs the Pester 6 unit and integration tests of ./scripts (test/scripts) in a supervised worker with a monitor.
.PARAMETER Kind
Unit, Integration or All (default).
.PARAMETER Path
Files or directories inside TestsRoot; the run becomes partial.
.PARAMETER FullNameFilter
Pester full-name filters; the run becomes partial.
.PARAMETER Tag
Pester tags to include; the run becomes partial.
.PARAMETER ExcludeTag
Pester tags to exclude; the run becomes partial.
.PARAMETER Seed
Seed exported as QUIETCLI_TEST_SEED for property and fuzz tests; generated and recorded when omitted.
.PARAMETER Coverage
Measures JaCoCo coverage of test/scripts/coverage.targets.psd1 and enforces its threshold.
.PARAMETER Headless
Disables the visible monitor (CI).
.PARAMETER RunDirectory
New run directory; defaults under the scripts-tests report root.
.PARAMETER TimeoutSeconds
Wall-clock limit for the worker (default 1800).
.PARAMETER WorkspaceRoot
Repository root; defaults to the parent of this scripts directory.
.PARAMETER TestsRoot
Tests root; defaults to <workspace>/test/scripts.
.PARAMETER ScriptsRoot
Scripts root exported as QUIETCLI_SCRIPTS_ROOT (a mutated copy for mutation testing); defaults to this directory.
.PARAMETER Offline
Requires the pinned test tools to be cached already.
#>
[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('Unit','Integration','All')][string]$Kind='All',[string[]]$Path=@(),[string[]]$FullNameFilter=@(),[string[]]$Tag=@(),[string[]]$ExcludeTag=@(),[ValidateRange(0,2147483647)][int]$Seed=0,[switch]$Coverage,[switch]$Headless,[string]$RunDirectory,[ValidateRange(1,7200)][int]$TimeoutSeconds=1800,[string]$WorkspaceRoot=([IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))),[string]$TestsRoot,[string]$ScriptsRoot=$PSScriptRoot,[switch]$Offline)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Invoke-ScriptsTests')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Invoke-ScriptsTests.psm1')) -DisableNameChecking -ErrorAction Stop
if([string]::IsNullOrWhiteSpace($TestsRoot)){$TestsRoot=[IO.Path]::Combine($WorkspaceRoot,'test','scripts')}
$outcome=Invoke-QuietScriptInvokeScriptsTests -WorkspaceRoot $WorkspaceRoot -TestsRoot $TestsRoot -ScriptsRoot $ScriptsRoot -Kind $Kind -Path $Path -FullNameFilter $FullNameFilter -Tag $Tag -ExcludeTag $ExcludeTag -Seed $Seed -Coverage:$Coverage -Headless:$Headless -RunDirectory $RunDirectory -TimeoutSeconds $TimeoutSeconds -Offline:$Offline
$outcome
if($outcome.ExitCode -ne 0){throw "Scripts tests $($outcome.State). See $($outcome.RunDirectory)"}
