# Objectif : Refuser une livraison sans qualification complète de la révision courante.
#requires -Version 7.6
<#
.SYNOPSIS
Emits a revision-bound qualification receipt only after every required job succeeds.
.PARAMETER Suite
Core/All requires native mutation; Git-only development explicitly skips it.
.PARAMETER Revision
Exact workflow commit, never a mutable branch name.
.PARAMETER WindowsResult
Aggregate Windows matrix result supplied by GitHub needs.
.PARAMETER LinuxResult
Aggregate Linux matrix result supplied by GitHub needs.
.PARAMETER MutationResult
Native mutation job result supplied by GitHub needs.
.PARAMETER ReceiptPath
Saved qualification decision, including unsuccessful decisions.
.PARAMETER OutputPath
GitHub step output file. The qualified_sha output is appended only on success.
#>
[CmdletBinding()]param(
    [ValidateSet('All','Core','Git')][string]$Suite='All',
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$Revision,
    [Parameter(Mandatory)][string]$WindowsResult,
    [Parameter(Mandatory)][string]$LinuxResult,
    [Parameter(Mandatory)][string]$MutationResult,
    [Parameter(Mandatory)][string]$ReceiptPath,
    [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$mutationExpected=if($Suite -eq 'Git'){'skipped'}else{'success'}
$ready=$WindowsResult -ceq 'success' -and $LinuxResult -ceq 'success' -and $MutationResult -ceq $mutationExpected
[void][IO.Directory]::CreateDirectory((Split-Path ([IO.Path]::GetFullPath($ReceiptPath,$PWD.Path)) -Parent))
Write-WorkspaceJson $ReceiptPath @{Revision=$Revision;Suite=$Suite;Ready=$ready;Windows=$WindowsResult;Linux=$LinuxResult;Mutation=$MutationResult;MutationRequired=($Suite -ne 'Git')}
if(!$ready){throw 'QualificationRejected: every required job must succeed for this revision.'}
[void][IO.File]::AppendAllTextAsync($OutputPath,("qualified_sha=$Revision`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
