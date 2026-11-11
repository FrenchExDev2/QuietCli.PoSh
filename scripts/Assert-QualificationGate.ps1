#requires -Version 7.6
<#
.SYNOPSIS
Emits a revision-bound qualification receipt only after every required job succeeds.
.PARAMETER Suite
Selected companion scope. Local full qualification includes native mutation.
.PARAMETER Revision
Exact workflow commit, never a mutable branch name.
.PARAMETER WindowsResult
Aggregate Windows matrix result supplied by GitHub needs.
.PARAMETER LinuxResult
Aggregate Linux matrix result supplied by GitHub needs.
.PARAMETER PerformanceResult
Matrix profiling/readable-report job result; required for scopes declaring Core evidence.
.PARAMETER SkipTty
Explicit GitHub CI scope excluding TTY/PTY campaigns; recorded as excluded, never passed.
.PARAMETER MutationResult
Native mutation job result supplied by GitHub needs.
.PARAMETER ReceiptPath
Saved qualification decision, including unsuccessful decisions.
.PARAMETER OutputPath
GitHub step output file. The qualified_sha output is appended only on success.
.PARAMETER WorkspaceRoot
Checkout whose suite declarations decide whether Core native evidence is required.
#>
[CmdletBinding(SupportsShouldProcess)]param(
    [string]$Suite='All',
    [switch]$SkipTty,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$Revision,
    [Parameter(Mandatory)][string]$WindowsResult,
    [Parameter(Mandatory)][string]$LinuxResult,
    [string]$PerformanceResult='skipped',
    [Parameter(Mandatory)][string]$MutationResult,
    [Parameter(Mandatory)][string]$ReceiptPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent)
)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Assert-QualificationGate')){return}
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Import-Module (Join-Path $PSScriptRoot 'lib/CiCompanions.psm1')
$selection=Resolve-QuietCiCompanions (Read-QuietCiCompanions $WorkspaceRoot) -Suite $Suite
$mutationRequired=!$SkipTty -and $selection.HasCoreEvidence
$mutationExpected=if($mutationRequired){'success'}else{'skipped'}
$performanceRequired=$selection.HasCoreEvidence
$performanceExpected=if($performanceRequired){'success'}else{'skipped'}
$ready=$WindowsResult -ceq 'success' -and $LinuxResult -ceq 'success' -and $MutationResult -ceq $mutationExpected -and $PerformanceResult -ceq $performanceExpected
[void][IO.Directory]::CreateDirectory((Split-Path ([IO.Path]::GetFullPath($ReceiptPath,$PWD.Path)) -Parent))
Write-WorkspaceJson $ReceiptPath @{Revision=$Revision;Suite=$Suite;Ready=$ready;Windows=$WindowsResult;Linux=$LinuxResult;Performance=$PerformanceResult;PerformanceRequired=$performanceRequired;Mutation=$MutationResult;MutationRequired=$mutationRequired;RunId=$env:GITHUB_RUN_ID;RunAttempt=$env:GITHUB_RUN_ATTEMPT;TtyQualification=$(if($SkipTty){'Excluded'}elseif($mutationRequired){'Required for selected Core evidence'}else{'Not required by selected suites'})}
if(!$ready){throw 'QualificationRejected: every required job must succeed for this revision.'}
[void][IO.File]::AppendAllTextAsync($OutputPath,("qualified_sha=$Revision`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
