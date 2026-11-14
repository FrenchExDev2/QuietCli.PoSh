#requires -Version 7.6
function Invoke-QuietCiCompanionWorkers {
    <#
    .SYNOPSIS
    Runs companion suites in bounded isolated processes after the caller has accepted Core.
    .PARAMETER WorkspaceRoot
    Already built checkout, shared read-only by the test processes.
    .PARAMETER RunDirectory
    Parent reports directory; every suite owns a separate child directory and configuration.
    .PARAMETER Selections
    Declared non-Core suites. The caller supplies the accepted Core prerequisite.
    .PARAMETER CoreSummary
    Successful, complete Core result; rejected before any child starts otherwise.
    .PARAMETER ExpectedRuntimeIdentifier
    Required actual host and engine architecture.
    .PARAMETER SkipTty
    Preserves the caller's explicit terminal campaign exclusion.
    .PARAMETER MaxConcurrency
    Maximum simultaneous companion processes; each uses one internal worker.
    .PARAMETER TimeoutSeconds
    Deadline for each owned process tree.
    .PARAMETER OnProgress
    Receives cumulative child pass/failure counters from saved reports.
    .PARAMETER WorkerPath
    Explicit worker for owned process fixtures; defaults to Invoke-TestWorker.ps1.
    .PARAMETER WorkerBudget
    Shared test-worker budget divided among admitted companion slots; omitted preserves one internal slot each.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$WorkspaceRoot,[string]$RunDirectory,[object[]]$Selections,[Parameter(Mandatory)]$CoreSummary,
        [string]$ExpectedRuntimeIdentifier,[switch]$SkipTty,
        [ValidateRange(1,32)][int]$MaxConcurrency=2,[ValidateRange(1,7200)][int]$TimeoutSeconds=1800,
        [scriptblock]$OnProgress,[string]$WorkerPath=([IO.Path]::Combine($PSScriptRoot,'../Invoke-TestWorker.ps1')),[ValidateRange(0,32)][int]$WorkerBudget=0)
    if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,'Run isolated companion suites after Core')){return}
    if($null -eq $CoreSummary -or !$CoreSummary.PSObject.Properties['Failed'] -or $CoreSummary.Failed -ne 0 -or $CoreSummary.Partial -or $CoreSummary.Incomplete){throw 'CompanionFanoutRequiresSuccessfulCompleteCore'}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'Ci.Process.psm1')) -DisableNameChecking -ErrorAction Stop
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($selection in $Selections){
        if($selection.Name -cnotmatch '\A[A-Z][A-Za-z0-9]*\z' -or $selection.Name -ieq 'Core' -or !$names.Add($selection.Name)){throw 'CompanionWorkerSelectionInvalid'}
    }
    if(!$WorkerBudget){$WorkerBudget=[Math]::Max(1,[Math]::Min($MaxConcurrency,$Selections.Count))}
    $MaxConcurrency=[Math]::Min($MaxConcurrency,$WorkerBudget)
    $slots=[Math]::Max(1,[Math]::Min($MaxConcurrency,$Selections.Count))
    $internalConcurrency=[Math]::Max(1,[int][Math]::Floor($WorkerBudget/$slots))
    $pending=[Collections.Generic.Queue[object]]::new()
    foreach($selection in $Selections){$pending.Enqueue($selection)}
    $active=[Collections.Generic.List[object]]::new()
    $completed=[Collections.Generic.List[object]]::new()
    $runner=[IO.Path]::Combine($PSHOME,$(if($IsWindows){'pwsh.exe'}else{'pwsh'}))
    try{
        while($pending.Count -or $active.Count){
            while($pending.Count -and $active.Count -lt $MaxConcurrency){
                $selection=$pending.Dequeue()
                $directory=[IO.Path]::Combine($RunDirectory,('companions/'+$selection.Name))
                if(Test-Path -LiteralPath $directory){throw 'CompanionWorkerDirectoryExists'}
                [void][IO.Directory]::CreateDirectory($directory)
                # Streams remain inherited: no automatic capture, spool or business-output history.
                $arguments=@('-File',$WorkerPath,'-WorkspaceRoot',$WorkspaceRoot,'-RunDirectory',$directory,'-Suite',$selection.Name,'-MaxConcurrency',[string]$internalConcurrency)
                if($SkipTty){$arguments+='-SkipTty'}
                if($ExpectedRuntimeIdentifier){$arguments+=@('-ExpectedRuntimeIdentifier',$ExpectedRuntimeIdentifier)}
                $process=Start-CiProcess -FilePath $runner -ArgumentList $arguments -WorkingDirectory $WorkspaceRoot -Confirm:$false
                $active.Add([pscustomobject]@{Name=$selection.Name;Directory=$directory;Process=$process;Started=[DateTimeOffset]::UtcNow})
            }
            foreach($worker in @($active.ToArray())){
                if(([DateTimeOffset]::UtcNow-$worker.Started).TotalSeconds -gt $TimeoutSeconds){throw ('CompanionWorkerTimeout: '+$worker.Name)}
                if(!$worker.Process.HasExited){continue}
                $path=[IO.Path]::Combine($worker.Directory,'summary.json')
                if(!(Test-Path -LiteralPath $path)){throw ('CompanionWorkerSummaryMissing: '+$worker.Name)}
                $summary=Get-Content -LiteralPath $path -Encoding utf8 -Raw|ConvertFrom-Json
                if($worker.Process.ExitCode -ne 0 -or $summary.State.State -cne 'Success' -or $summary.State.Failed -ne 0 -or @($summary.Suites).Count -ne 1){throw ('CompanionWorkerFailed: '+$worker.Name)}
                $completed.Add([pscustomobject]@{Name=$worker.Name;Summary=$summary})
                $worker.Process.Dispose();[void]$active.Remove($worker)
            }
            if($OnProgress){
                $passed=0;$failed=0
                foreach($entry in $completed){$passed+=$entry.Summary.State.Passed;$failed+=$entry.Summary.State.Failed}
                foreach($worker in $active){
                    $path=[IO.Path]::Combine($worker.Directory,'status.json')
                    if(Test-Path -LiteralPath $path){$progress=Get-Content -LiteralPath $path -Encoding utf8 -Raw|ConvertFrom-Json;$passed+=$progress.Passed;$failed+=$progress.Failed}
                }
                $null=& $OnProgress $passed $failed
            }
            if($active.Count){[void][Threading.Tasks.Task]::Delay(100).GetAwaiter().GetResult()}
        }
        # Preserve declarative suite order independently of completion order.
        foreach($selection in $Selections){($completed|Where-Object Name -CEQ $selection.Name).Summary}
    }finally{
        foreach($worker in $active){try{if(!$worker.Process.HasExited){$worker.Process.Kill($true);$worker.Process.WaitForExit()}}finally{$worker.Process.Dispose()}}
    }
}
Export-ModuleMember -Function Invoke-QuietCiCompanionWorkers
