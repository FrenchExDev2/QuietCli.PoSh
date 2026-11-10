. (Join-Path $PSScriptRoot 'ReportPaths.ps1')
. (Join-Path $PSScriptRoot 'Ci.Process.ps1')
. (Join-Path $PSScriptRoot 'SourceIdentity.ps1')
. (Join-Path $PSScriptRoot 'RuntimeTargets.ps1')
function Resolve-QuietVirtEngine {
    <#
    .SYNOPSIS
    Selects an explicit container engine or discovers Docker then Podman on PATH without starting either.
    .PARAMETER ContainerRuntime
    Optional explicit engine. Empty selects the first available application, preferring Docker.
    .PARAMETER Available
    Also requires an explicitly selected engine to exist as an application on PATH.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][ValidateSet('','docker','podman')][string]$ContainerRuntime,[switch]$Available)
    if($ContainerRuntime){
        if($Available -and !(Get-Command $ContainerRuntime -CommandType Application -ErrorAction SilentlyContinue)){throw ('QuietVirtEngineUnavailable: '+$ContainerRuntime)}
        return $ContainerRuntime.ToLowerInvariant()
    }
    foreach($candidate in @('docker','podman')){
        if(Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue){return $candidate}
    }
    throw 'QuietVirtEngineUnavailable: install Docker or Podman, or select an available engine explicitly.'
}
function Invoke-WorkspaceNative {
    <#
.SYNOPSIS
Runs a CI tool directly, independently of the product engine, with bounded failure diagnostics.
    .PARAMETER FilePath
    Native executable.
    .PARAMETER Arguments
    Native argument vector.
    .PARAMETER WorkingDirectory
    Explicit operation directory.
    .PARAMETER TimeoutSeconds
    Bounded deadline for the owned administrative process.
    .PARAMETER LogPath
    Optional UTF-8 file receiving every stdout/stderr line as it is produced, in addition to the
    console. Written whether the call succeeds or fails; a failure's thrown message names this
    file so a concurrent (interleaved-console) run still has a readable, attributable trace.
    #>
    param([string]$FilePath,[string[]]$Arguments,[string]$WorkingDirectory,[ValidateRange(1,3600)][int]$TimeoutSeconds=600,[string]$LogPath)
    Write-Host ('Progress: Execute '+$FilePath+' for the current workspace operation.')
    $state=@{Lines=0;Diagnostics=[Collections.Generic.Queue[string]]::new();Writer=$null}
    if($LogPath){
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($LogPath))
        $state.Writer=[IO.StreamWriter]::new($LogPath,$true,[Text.UTF8Encoding]::new($false))
        $state.Writer.AutoFlush=$true
    }
    try{
        $result=Invoke-CiProcess -FilePath $FilePath -ArgumentList $Arguments -TimeoutSeconds $TimeoutSeconds -WorkingDirectory $WorkingDirectory -State $state -OnOutput {
            param($record,$state)
            $state.Lines++
            if($record.Stream -eq 'stderr'){[void][Console]::Error.WriteLineAsync($record.Text).GetAwaiter().GetResult()}else{[void][Console]::Out.WriteLineAsync($record.Text).GetAwaiter().GetResult()}
            if($state.Writer){$state.Writer.WriteLine('['+$record.Stream+'] '+$record.Text)}
            if($record.Text.Trim()){if($state.Diagnostics.Count -ge 10){$null=$state.Diagnostics.Dequeue()};$line=$record.Text;if($line.Length -gt 1024){$line=$line.Substring(0,1024)+'…'};$state.Diagnostics.Enqueue($line)}
        }
        Write-Host ('Summary: '+$FilePath+' = '+$result.Outcome+'; observed lines='+$state.Lines)
        if($result.Outcome -ne 'Success'){
            foreach($line in $state.Diagnostics){Write-Host $line}
            $suffix=if($LogPath){" - full log: $LogPath"}else{''}
            throw "Workspace operation failed: $FilePath ($($result.Outcome))$suffix"
        }
        [pscustomobject]@{Tool=$FilePath;Outcome=$result.Outcome;Lines=$state.Lines;LogPath=$LogPath}
    }finally{if($state.Writer){$state.Writer.Dispose()}}
}
function ConvertTo-QuietByteCount {
    <#
.SYNOPSIS
Parses a human-readable size into a byte count.
    .PARAMETER Size
    A bare non-negative integer (already bytes), or a number immediately or space-separated from a
    decimal unit (`KB`/`MB`/`GB`/`TB`, powers of 1000) or binary unit (`KiB`/`MiB`/`GiB`/`TiB`,
    powers of 1024). Case-insensitive. Examples: `"500KB"`, `"1 MiB"`, `"2GiB"`, `"750"`.
    #>
    param([Parameter(Mandatory)][string]$Size)
    $match = [regex]::Match($Size.Trim(), '^(?<value>\d+(\.\d+)?)\s*(?<unit>[KMGT]i?B)?$', 'IgnoreCase')
    if (!$match.Success) { throw ('QuietByteCountInvalid: ' + $Size) }
    $value = [double]$match.Groups['value'].Value
    $unit = $match.Groups['unit'].Value.ToUpperInvariant()
    $multiplier = switch ($unit) {
        '' { 1 }
        'KB' { 1000 }; 'KIB' { 1024 }
        'MB' { 1000L * 1000 }; 'MIB' { 1024L * 1024 }
        'GB' { 1000L * 1000 * 1000 }; 'GIB' { 1024L * 1024 * 1024 }
        'TB' { 1000L * 1000 * 1000 * 1000 }; 'TIB' { 1024L * 1024 * 1024 * 1024 }
        default { throw ('QuietByteCountInvalid: ' + $Size) }
    }
    [long]($value * $multiplier)
}
function Write-WorkspaceJson {
    <#
.SYNOPSIS
Publishes UTF-8 JSON atomically, creating missing destination directories for reports and monitors.
    .PARAMETER Path
    Destination JSON path.
    .PARAMETER Value
    State metadata.
    #>
    param([string]$Path,$Value)
    $Path=[IO.Path]::GetFullPath($Path,$PWD.Path)
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    $json=(ConvertTo-Json -InputObject $Value -Depth 32).Replace("`r`n","`n").Replace("`r","`n")
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    try{
        [void][IO.File]::WriteAllTextAsync($temporary,$json,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        for($attempt=0;$attempt -le 5;$attempt++){
            try{[IO.File]::Move($temporary,$Path,$true);break}catch{
                $code=$_.Exception.GetBaseException().HResult -band 65535
                if(!$IsWindows -or $attempt -eq 5 -or $code -notin @(5,32,33) -or ![IO.File]::Exists($Path)){throw}
                [void][Threading.Tasks.Task]::Delay(20).GetAwaiter().GetResult()
            }
        }
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Stop-WorkspaceWorker {
    <#
    .SYNOPSIS
    Cancels an explicitly selected local Windows worker after verifying ownership and saving its terminal report.
    .PARAMETER WorkspaceRoot
    Exact workspace recorded by the worker.
    .PARAMETER RunDirectory
    Owned run directory printed by Invoke-WorkspaceCi.
    .PARAMETER Reason
    Explicit cancellation reason retained with the interrupted evidence.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory,[string]$Reason='Cancelled by user request.')
    if(!$IsWindows){throw 'WorkspaceWorkerCancellationRequiresWindows'}
    $statusPath=Join-Path $RunDirectory status.json
    $state=Get-Content -LiteralPath $statusPath -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable -DateKind String
    if($state.State -in @('Success','Failed','Crash','Timeout','Cancelled')){return [pscustomobject]@{State=$state.State;Stopped=$false;RunDirectory=$RunDirectory}}
    if([IO.Path]::GetFullPath($state.Workspace) -ine [IO.Path]::GetFullPath($WorkspaceRoot)){throw 'WorkspaceWorkerOwnershipMismatch'}
    $worker=Get-Process -Id ([int]$state.ProcessId) -ErrorAction Stop
    $metadata=Get-CimInstance Win32_Process -Filter ('ProcessId='+$worker.Id)
    $expectedScript=Join-Path ([IO.Path]::GetFullPath($WorkspaceRoot)) scripts/Invoke-TestWorker.ps1
    if($worker.ProcessName -ine 'pwsh' -or !$metadata -or
        !$metadata.CommandLine.Replace('/','\').Contains($expectedScript.Replace('/','\')) -or
        !$metadata.CommandLine.Replace('/','\').Contains([IO.Path]::GetFullPath($RunDirectory).Replace('/','\')) -or
        [Math]::Abs(($worker.StartTime.ToUniversalTime()-[DateTimeOffset]::Parse($state.StartedUtc).UtcDateTime).TotalSeconds) -gt 30){throw 'WorkspaceWorkerOwnershipMismatch'}
    if(!$PSCmdlet.ShouldProcess(('PID '+$worker.Id+'; '+$RunDirectory),'Save cancellation and stop the owned worker tree')){return}
    $state.State='Cancelled';$state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o');$state.Case='Cancelled by explicit request';$state.Error=$Reason
    $null=Write-WorkspaceJson (Join-Path $RunDirectory summary.json) @{State=$state;Suites=@();Cancellation=@{Reason=$Reason;Qualified=$false}}
    $null=Write-WorkspaceJson $statusPath $state
    if(!$worker.HasExited){$worker.Kill($true);[void]$worker.WaitForExitAsync().GetAwaiter().GetResult()}
    [pscustomobject]@{State='Cancelled';Stopped=$true;RunDirectory=$RunDirectory}
}
function Wait-WorkspaceWorker {
    <#
    .SYNOPSIS
    Supervises one owned worker, reopens its monitor when needed and saves every terminal outcome.
    .PARAMETER Worker
    Process created by the current launcher.
    .PARAMETER RunDirectory
    Dedicated directory containing this worker's status and reports.
    .PARAMETER WorkspaceRoot
    Absolute source workspace.
    .PARAMETER Runner
    PowerShell executable used to reopen a visible monitor.
    .PARAMETER Monitor
    Optional dedicated visible monitor process; null in headless CI.
    .PARAMETER TimeoutSeconds
    Maximum wall-clock duration before terminating the owned worker tree.
    #>
    param([Diagnostics.Process]$Worker,[string]$RunDirectory,[string]$WorkspaceRoot,[string]$Runner,[Diagnostics.Process]$Monitor,[int]$TimeoutSeconds)
    . (Join-Path $PSScriptRoot ReportStreaming.ps1)
    $started=[DateTimeOffset]::UtcNow;$deadline=$started.AddSeconds($TimeoutSeconds);$timedOut=$false;$monitorRestarts=0;$monitorFailure=$false
    $monitorPath=Join-Path $PSScriptRoot 'Watch-Tests.ps1'
    $streams=@(New-QuietReportStream (Join-Path $RunDirectory worker.stdout.log);New-QuietReportStream (Join-Path $RunDirectory worker.stderr.log))
    $nextHeartbeat=$started
    while(!$Worker.HasExited){
        foreach($stream in $streams){foreach($line in (Read-QuietReportStream $stream -MaxLines 4)){if($line){Write-Host ('[report] '+$line)}}}
        if([DateTimeOffset]::UtcNow -ge $nextHeartbeat){
            Write-Host ('Progress: Follow active report | elapsed='+[int]([DateTimeOffset]::UtcNow-$started).TotalSeconds+'s | observed lines='+(($streams|ForEach-Object TotalLines|Measure-Object -Sum).Sum)+' | PID='+$Worker.Id)
            $nextHeartbeat=[DateTimeOffset]::UtcNow.AddSeconds(10)
        }
        if($Monitor -and $Monitor.HasExited){
            $terminal=$false
            $currentStatus=Join-Path $RunDirectory 'status.json'
            if(Test-Path -LiteralPath $currentStatus){try{$current=Get-Content -LiteralPath $currentStatus -Raw -Encoding utf8|ConvertFrom-Json;$terminal=$current.State -in @('Success','Failed','Crash','Timeout','Cancelled') -and (Test-Path -LiteralPath (Join-Path $RunDirectory 'summary.json'))}catch{}}
            if(!$terminal){
                if($monitorRestarts -ge 3){$Worker.Kill($true);$monitorFailure=$true;break}
                $monitorRestarts++
                $Monitor=Start-Process -FilePath $Runner -WindowStyle Normal -ArgumentList @('-File',(ConvertTo-CiArgument ($monitorPath)),'-RunDirectory',(ConvertTo-CiArgument ($RunDirectory))) -RedirectStandardError (Join-Path $RunDirectory "monitor-restart-$monitorRestarts.stderr.log") -PassThru
            }
        }
        if([DateTimeOffset]::UtcNow -gt $deadline){$Worker.Kill($true);$timedOut=$true;break}
        [void][Threading.Tasks.Task]::Delay(500).GetAwaiter().GetResult()
    }
    $summaryPath=Join-Path $RunDirectory 'summary.json';$statusPath=Join-Path $RunDirectory 'status.json'
    if($timedOut -or $monitorFailure -or !(Test-Path -LiteralPath $summaryPath)){
        $state=if(Test-Path -LiteralPath $statusPath){Get-Content -LiteralPath $statusPath -Encoding utf8 -Raw|ConvertFrom-Json -AsHashtable}else{@{Project='FrenchExDev2.QuietCli.Core.PoSh + FrenchExDev2.QuietCli.Git.PoSh';Task='Tests compagnons';Workspace=$WorkspaceRoot;ProjectDirectory=$WorkspaceRoot;Platform=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;StartedUtc=$started.ToString('o');ProcessId=$Worker.Id;Passed=0;Failed=0}}
        $state.State=if($timedOut){'Timeout'}else{'Crash'};$state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o');$state.Failed=[int]$state.Failed+1
        # Preserve valid monitor identity even if a faulty worker replaced its status with a progress DTO.
        foreach($field in @{Project='FrenchExDev2.QuietCli.Core.Tests.PoSh';Task='Tests compagnons';Workspace=$WorkspaceRoot;ProjectDirectory=$WorkspaceRoot;Platform=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;StartedUtc=$started.ToString('o');ProcessId=$Worker.Id}.GetEnumerator()){if(!$state[$field.Key]){$state[$field.Key]=$field.Value}}
        $state.Case='Worker terminated without a complete report';$state.Error='See worker.stderr.log; owned native processes may need explicit cleanup.'
        if($monitorFailure){$state.Case='Visible monitor failed after three bounded restarts';$state.Error='See monitor*.stderr.log. The owned worker was stopped to prevent repeated windows.'}
        if($state.ContainsKey('ContainerId')){$state.Cleanup='Unconfirmed: worker terminated before cleanup receipt'}
        Write-WorkspaceJson $summaryPath @{State=$state};Write-WorkspaceJson $statusPath $state
    }
    foreach($stream in $streams){foreach($line in (Read-QuietReportStream $stream -MaxLines 6)){if($line){Write-Host ('[report] '+$line)}}}
    $saved=Get-Content -LiteralPath $summaryPath -Encoding utf8 -Raw|ConvertFrom-Json
    Write-Host ('Summary: '+($saved.State|Select-Object Project,Task,State,Passed,Failed,Error|ConvertTo-Json -Compress))
    return $saved
}
function Write-WorkspaceFailureDiagnostics {
    <#
    .SYNOPSIS
    Prints bounded saved failure details without asking a CI operator to open a desktop monitor.
    .PARAMETER Summary
    Terminal worker summary containing state and optional companion suite reports.
    .PARAMETER RunDirectory
    Directory retaining the full diagnostic files.
    #>
    param([Parameter(Mandatory)]$Summary,[Parameter(Mandatory)][string]$RunDirectory)
    Write-Host ('CI terminal state: '+($Summary.State|Select-Object Project,Platform,State,Passed,Failed,Error|ConvertTo-Json -Compress))
    $suites=if($Summary.PSObject.Properties['Suites']){@($Summary.Suites)}else{@()}
    $failures=@($suites|ForEach-Object {$_.Cases}|Where-Object State -NE Passed)
    foreach($case in $failures|Select-Object -First 8){
        $message=($case|Select-Object Name,State,Error|ConvertTo-Json -Compress)
        if($message.Length -gt 2048){$message=$message.Substring(0,2048)+'…'}
        Write-Host ('CI failed case: '+$message)
    }
    Write-Host ("CI reports: $RunDirectory | failed cases shown: $([Math]::Min(8,$failures.Count))/$($failures.Count)")
}
