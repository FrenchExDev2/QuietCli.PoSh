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
.PARAMETER ToolingResult
Repository automation and run-profile behavior result.
.PARAMETER ToolingMutationResult
Isolated run-profile mutation campaign result.
.PARAMETER ToolingCompletionResult
Exact source-bound mutation catalogue completeness result.
.PARAMETER ToolingWorkflowResult
Overall reusable workflow result, including setup and artifact failures.
.PARAMETER RequireTooling
Requires both tooling campaigns before accepting this revision.
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
    [string]$ToolingResult='skipped',[string]$ToolingMutationResult='skipped',[switch]$RequireTooling,
    [AllowEmptyString()][string]$ToolingCompletionResult='skipped',[AllowEmptyString()][string]$ToolingWorkflowResult='skipped',
    [Parameter(Mandatory)][string]$ReceiptPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent)
)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Assert-QualificationGate')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiCompanions.psm1')) -DisableNameChecking
$selection=Resolve-QuietCiCompanions (Read-QuietCiCompanions $WorkspaceRoot) -Suite $Suite
$mutationRequired=!$SkipTty -and $selection.HasCoreEvidence
$mutationExpected=if($mutationRequired){'success'}else{'skipped'}
$performanceRequired=$selection.HasCoreEvidence
$performanceExpected=if($performanceRequired){'success'}else{'skipped'}
$toolingExpected=if($RequireTooling){'success'}else{'skipped'}
$toolingReady=if($RequireTooling){$ToolingWorkflowResult -ceq 'success' -and $ToolingResult -ceq 'success' -and $ToolingMutationResult -ceq 'success' -and $ToolingCompletionResult -ceq 'success'}else{$ToolingWorkflowResult -ceq 'skipped' -and $ToolingCompletionResult -ceq 'skipped'}
$ready=$WindowsResult -ceq 'success' -and $LinuxResult -ceq 'success' -and $MutationResult -ceq $mutationExpected -and $PerformanceResult -ceq $performanceExpected -and $ToolingResult -ceq $toolingExpected -and $ToolingMutationResult -ceq $toolingExpected -and $toolingReady
$tree=Read-QuietRepositoryValue $WorkspaceRoot @('rev-parse','HEAD^{tree}')
[void][IO.Directory]::CreateDirectory((Split-Path ([IO.Path]::GetFullPath($ReceiptPath,$PWD.Path)) -Parent))
Write-WorkspaceJson $ReceiptPath @{Revision=$Revision;Tree=$tree;Suite=$Suite;Ready=$ready;Windows=$WindowsResult;Linux=$LinuxResult;Performance=$PerformanceResult;PerformanceRequired=$performanceRequired;Mutation=$MutationResult;MutationRequired=$mutationRequired;Tooling=$ToolingResult;ToolingMutation=$ToolingMutationResult;ToolingCompletion=$ToolingCompletionResult;ToolingWorkflow=$ToolingWorkflowResult;ToolingRequired=[bool]$RequireTooling;RunId=$env:GITHUB_RUN_ID;RunAttempt=$env:GITHUB_RUN_ATTEMPT;TtyQualification=$(if($SkipTty){'Excluded'}elseif($mutationRequired){'Required for selected Core evidence'}else{'Not required by selected suites'})}
if(!$ready){throw 'QualificationRejected: every required job must succeed for this revision.'}
[void][IO.File]::AppendAllTextAsync($OutputPath,("qualified_sha=$Revision`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
