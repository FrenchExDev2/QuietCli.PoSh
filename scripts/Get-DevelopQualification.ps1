#requires -Version 7.6
<#
.SYNOPSIS
Finds successful merged-PR qualification for the exact develop tree; any miss requires full validation.
.PARAMETER WorkspaceRoot
Checkout at the merged revision.
.PARAMETER Revision
Immutable develop commit.
.PARAMETER Repository
GitHub owner/repository; token is read only from GH_TOKEN.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Revision,[string]$Repository='FrenchExDev2/QuietCli.PoSh')
if(!$PSCmdlet.ShouldProcess($Revision,'Read successful merged PR receipts from GitHub')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiImpact.psm1')) -ErrorAction Stop -DisableNameChecking
$miss=[pscustomobject]@{Reused=$false;Revision=$Revision;Reason='No matching successful PR receipt';RunId=$null}
if(!$env:GH_TOKEN -or $Repository -cne 'FrenchExDev2/QuietCli.PoSh'){return $miss}
$headers=@{Authorization=('Bearer '+$env:GH_TOKEN);Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28'}
$api='https://api.github.com/repos/'+$Repository
try{
    $tree=Read-QuietRepositoryValue $WorkspaceRoot @('rev-parse',($Revision+'^{tree}'))
    if($tree -cnotmatch '\A[a-f0-9]{40}\z'){return $miss}
    $prs=@(Invoke-RestMethod -Uri ($api+'/commits/'+$Revision+'/pulls?per_page=100') -Headers $headers -TimeoutSec 30)
    foreach($pr in $prs){
        if(!$pr.merged_at -or $pr.merge_commit_sha -cne $Revision -or $pr.base.ref -cne 'develop'){continue}
        $runs=Invoke-RestMethod -Uri ($api+'/actions/workflows/companions-ci.yml/runs?event=pull_request&status=success&head_sha='+$pr.head.sha+'&per_page=100') -Headers $headers -TimeoutSec 30
        foreach($run in $runs.workflow_runs){
            if($run.event -cne 'pull_request' -or $run.conclusion -cne 'success' -or $run.head_sha -cne $pr.head.sha -or $run.path -cne '.github/workflows/companions-ci.yml'){continue}
            $artifacts=Invoke-RestMethod -Uri ($api+'/actions/runs/'+$run.id+'/artifacts?per_page=100') -Headers $headers -TimeoutSec 30
            foreach($artifact in $artifacts.artifacts){
                if($artifact.name -cne 'quietcli2-qualification-gate' -or $artifact.expired -or $artifact.size_in_bytes -gt 1048576){continue}
                $response=Invoke-WebRequest -Uri ($api+'/actions/artifacts/'+$artifact.id+'/zip') -Headers $headers -TimeoutSec 30
                $stream=[IO.MemoryStream]::new([byte[]]$response.Content)
                $archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Read)
                try{
                    $entries=@($archive.Entries|Where-Object FullName -CEQ 'receipt.json')
                    if($entries.Count -ne 1 -or $entries[0].Length -gt 16384){continue}
                    $reader=[IO.StreamReader]::new($entries[0].Open(),[Text.UTF8Encoding]::new($false,$true))
                    try{$receipt=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
                    if(Test-QuietDevelopReceipt $receipt $tree ([string]$run.id) ([string]$run.run_attempt)){
                        return [pscustomobject]@{Reused=$true;Revision=$Revision;Tree=$tree;RunId=$run.id;RunAttempt=$run.run_attempt;PullRequest=$pr.number;Reason='Successful PR qualified the identical source tree'}
                    }
                }finally{$archive.Dispose();$stream.Dispose()}
            }
        }
    }
}catch{Write-Host 'PR qualification could not be verified; full qualification is required.'}
return $miss
