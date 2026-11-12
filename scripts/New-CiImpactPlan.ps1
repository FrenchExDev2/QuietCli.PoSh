#requires -Version 7.6
<#
.SYNOPSIS
Writes a conservative PR/develop CI plan from the complete Git diff and verified same-tree PR receipts.
.PARAMETER WorkspaceRoot
Selected checkout.
.PARAMETER Base
Immutable PR base or push-before revision.
.PARAMETER Revision
Immutable workflow revision.
.PARAMETER Event
pull_request or push; a develop push may reuse verified PR evidence.
.PARAMETER OutputPath
GitHub job output file.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Base,[Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Revision,[ValidateSet('pull_request','push')][string]$Event='pull_request',[Parameter(Mandatory)][string]$OutputPath)
if(!$PSCmdlet.ShouldProcess($Revision,'Resolve changed suites and save the CI execution plan')){return}
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Import-Module (Join-Path $PSScriptRoot 'lib/CiImpact.psm1') -ErrorAction Stop
$state=@{Text=[Text.StringBuilder]::new()}
$diff=Invoke-CiProcess -FilePath git -ArgumentList @('diff','--no-renames','--name-only','-z',$Base,$Revision,'--') -WorkingDirectory $WorkspaceRoot -State $state -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){[void]$s.Text.Append($e.Text)}}
if($diff.Outcome -ne 'Success'){throw 'CiImpactCompleteDiffRequired'}
$paths=@($state.Text.ToString().Split([char]0,[StringSplitOptions]::RemoveEmptyEntries))
$plan=Get-QuietCiImpact -WorkspaceRoot $WorkspaceRoot -ChangedPaths $paths
$reuse=$null
if($Event -ceq 'push' -and ($plan.RunProducts -or $plan.RunTooling)){
    $reuse=& (Join-Path $PSScriptRoot 'Get-DevelopQualification.ps1') -WorkspaceRoot $WorkspaceRoot -Revision $Revision
    if($reuse.Reused){$plan.RunProducts=$false;$plan.RunTooling=$false}
    else{$plan.Suite='All';$plan.RunProducts=$true;$plan.RunTooling=$true}
}
$directory=Join-Path $WorkspaceRoot 'artifacts/ci-plan';[void][IO.Directory]::CreateDirectory($directory)
Write-WorkspaceJson (Join-Path $directory 'plan.json') @{Base=$Base;Revision=$Revision;Event=$Event;Plan=$plan;Reuse=$reuse}
$values="suite=$($plan.Suite)`nrun_products=$($plan.RunProducts.ToString().ToLowerInvariant())`nrun_tooling=$($plan.RunTooling.ToString().ToLowerInvariant())`n"
[IO.File]::AppendAllText($OutputPath,$values,[Text.UTF8Encoding]::new($false))
$plan
