# Objectif : Lire les états GitHub de chaque job sans exposer de jeton ni relancer les tests.
#requires -Version 7.6
<#
.SYNOPSIS
Read-only GitHub polling worker, with durable success/failure/cancellation/timeout reports.
.PARAMETER RunId
Existing run identifier.
.PARAMETER Repository
GitHub owner/repository.
.PARAMETER WorkspaceRoot
Project workspace to identify in the monitor.
.PARAMETER RunDirectory
Private status and report directory.
#>
[CmdletBinding()]param([long]$RunId,[string]$Repository,[string]$WorkspaceRoot,[string]$RunDirectory)
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot Common.ps1)
function Read-QuietGitHubJson {
    <#
    .SYNOPSIS
    Reads only the selected JSON projection through the documented gh API interface.
    .PARAMETER Endpoint
    GitHub API endpoint under the explicitly selected repository.
    .PARAMETER Projection
    jq projection selecting bounded run/job metadata.
    #>
    param([string]$Endpoint,[string]$Projection)
    $state=@{Json=[Text.StringBuilder]::new()}
    $r=Invoke-CiProcess -FilePath gh -ArgumentList @('api',$Endpoint,'--jq',$Projection) -TimeoutSeconds 45 -State $state -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){if($s.Json.Length+$e.Text.Length -gt 131072){throw 'RemoteStatusTooLarge'};[void]$s.Json.Append($e.Text)}}
    if($r.Outcome -ne 'Success'){throw 'GitHubStatusUnavailable'}
    return $state.Json.ToString()|ConvertFrom-Json
}
$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh + FrenchExDev2.QuietCli.Git.PoSh';Task='CI GitHub images et tests';Workspace=$WorkspaceRoot;ProjectDirectory=(Join-Path $WorkspaceRoot FrenchExDev2.QuietCli.Core.PoSh);Platform='GitHub';State='Running';ProcessId=$PID;Passed=$null;Failed=$null;StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null;Case='Waiting for remote job metadata; test counters unknown';Error=$null;RunId=$RunId;Runs=@()}
try{
    $deadline=[DateTimeOffset]::UtcNow.AddMinutes(58)
    do{
        $run=Read-QuietGitHubJson "repos/$Repository/actions/runs/$RunId" '{status,conclusion,html_url,head_sha,run_started_at}'
        $jobs=@(Read-QuietGitHubJson "repos/$Repository/actions/runs/$RunId/jobs?per_page=100" '.jobs | map({id,name,status,conclusion,started_at,completed_at,runner_name})')
        $state.Runs=@($jobs|ForEach-Object {@{Platform=$_.name;State=if($_.conclusion){$_.conclusion}else{$_.status};StartedUtc=$_.started_at;FinishedUtc=$_.completed_at;Identity=[string]$_.id;Runner=$_.runner_name}})
        $state.Case='Run '+$RunId+' | '+$run.status+' | heartbeat; individual test counts remain unknown';$state.Revision=$run.head_sha
        Write-WorkspaceJson (Join-Path $RunDirectory jobs.json) $jobs
        if($run.status -eq 'completed'){$state.State=switch($run.conclusion){success{'Success'} cancelled{'Cancelled'} timed_out{'Timeout'} default{'Failed'}};break}
        if([DateTimeOffset]::UtcNow -gt $deadline){$state.State='Timeout';$state.Error='Remote run may still be active; it was not cancelled';break}
        Write-WorkspaceJson (Join-Path $RunDirectory status.json) $state
        [void][Threading.Tasks.Task]::Delay(10000).GetAwaiter().GetResult()
    }while($true)
}catch{$state.State='Crash';$state.Error=$_.Exception.Message}
finally{$state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o');Write-WorkspaceJson (Join-Path $RunDirectory summary.json) @{State=$state};Write-WorkspaceJson (Join-Path $RunDirectory status.json) $state}
if($state.State -ne 'Success'){exit 1}
